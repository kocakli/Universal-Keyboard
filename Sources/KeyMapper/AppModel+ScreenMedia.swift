import AppKit
import KeyMapperCore

/// An upload to a screen keyboard's flash memory. It has its own state (not `send`), because it runs for minutes
/// and most of its errors happen before anything was sent, when the channel stays usable.
struct ScreenUploadState: Equatable {
    enum Kind: Equatable { case lcd, strip }

    var kind: Kind
    /// 0…1 while running.
    var progress: Double = 0
    var isRunning = true
    /// Why the last attempt did not finish (nil while running and after success).
    var error: String?
}

extension AppModel {
    // MARK: Per-key colours

    /// Sends the colour table, then switches the backlight to the per-key mode (the dongle takes both in one go).
    func applyKeyColors(_ device: KeyboardDevice) async {
        guard let channel = device.screenKeyboard else { return }
        let prefs = preferences(for: device)
        let colors = prefs.keyColors, brightness = max(1, min(5, prefs.keyColorBrightness))
        let ok = await send(L("Tuş renkleri gönderiliyor…"), to: device) { link in
            if channel.link == .wired {
                try link.run(AMG65Protocol.customColors(colors))
                try link.run(AMG65Protocol.customColorMode(brightness: brightness))
            } else {
                try link.runDongle(AMG65DongleProtocol.customColors(colors, brightness: brightness))
            }
        }
        if ok {
            updatePreferences(for: device) {
                $0.appliedKeyColors = colors
                $0.appliedKeyColorBrightness = brightness
                $0.lastBacklight = .keyColors
            }
            notice = L("Tuş renkleri klavyeye gönderildi.")
        }
    }

    // MARK: Key table

    /// Sends the whole key table: a slot left out is the factory key, so every send carries the complete map.
    func applyKeyMap(_ device: KeyboardDevice) async {
        guard let channel = device.screenKeyboard else { return }
        let map = preferences(for: device).keyMap
        let slots = map.mapValues(\.slotBytes)
        let ok = await send(L("Tuş atamaları gönderiliyor…"), to: device) { link in
            if channel.link == .wired {
                try link.run(AMG65Protocol.keyTable(slots))
            } else {
                try link.runDongle(AMG65DongleProtocol.keyTable(slots))
            }
        }
        if ok {
            updatePreferences(for: device) { $0.appliedKeyMap = map }
            notice = L("Tuş atamaları klavyeye gönderildi.")
        }
    }

    // MARK: Uploads

    /// Writes a still image or animation to the LCD (cable only).
    func uploadLCD(_ device: KeyboardDevice, animation: AMG65LCDAnimation) async {
        let ok = await upload(.lcd, to: device) { link, progress in
            let (bytes, blocks) = animation.buffer()
            try link.upload(bytes, blocks: blocks, header: AMG65Protocol.lcdUploadHeader(blocks: blocks),
                            applyAfter: false, progress: progress)
        }
        if ok { notice = L("LCD resmi klavyeye yüklendi.") }
    }

    /// Writes an animation to the LED matrix's own memory (cable only). `delay` 1…100, `brightness` 1…5, as in Studio.
    func uploadStrip(_ device: KeyboardDevice, animation: AMG65StripAnimation, target: AMG65StripTarget,
                     delay: UInt8, brightness: UInt8) async {
        let ok = await upload(.strip, to: device) { link, progress in
            let (bytes, blocks) = animation.buffer(delay: UInt16(delay), brightness: Double(brightness) / 5, target: target)
            try link.upload(bytes, blocks: blocks, header: AMG65Protocol.stripUploadHeader(target: target, blocks: blocks),
                            applyAfter: true, progress: progress)
        }
        if ok { notice = L("LED ekran animasyonu klavyeye yüklendi.") }
    }

    private func upload(_ kind: ScreenUploadState.Kind, to device: KeyboardDevice,
                        _ work: @escaping (AMG65Link, @escaping @Sendable (Double) -> Void) throws -> Void) async -> Bool {
        guard screenUploads[device.id]?.isRunning != true, let session = screenSession(for: device) else { return false }
        let id = device.id
        screenUploads[id] = ScreenUploadState(kind: kind)
        // Progress arrives on the session's queue.
        let progress: @Sendable (Double) -> Void = { [weak self] value in
            Task { @MainActor in self?.screenUploads[id]?.progress = value }
        }
        // The upload ends the matrix's live frames; the stream sends its current frame again afterwards.
        defer { ledResend.insert(id) }
        do {
            try await session.perform { link in try work(link, progress) }
            screenUploads[id] = nil
            screenStatus[id, default: .init()].link = .ready
            return true
        } catch let error as ScreenKeyboardError where error.stopsSending {
            // Something was sent and not acknowledged: the keyboard is blocked until it is reconnected.
            screenUploads[id] = ScreenUploadState(kind: kind, isRunning: false, error: error.localizedDescription)
            record(error, device: device)
            return false
        } catch {
            // Nothing was sent (no cable, the USB interface didn't open, a file the keyboard can't take).
            screenUploads[id] = ScreenUploadState(kind: kind, isRunning: false, error: Self.uploadMessage(error))
            return false
        }
    }

    private static func uploadMessage(_ error: Error) -> String {
        switch error {
        case is AMG65UploadError: return L("Bu dosya klavyenin belleğine sığmıyor.")
        case let error as HIDError:
            switch error {
            case .deviceNotFound, .openFailed: return L("Klavyenin yükleme bağlantısı açılamadı. Kabloyu çıkarıp takın ve tekrar deneyin.")
            default: return L("Yükleme başlamadan durdu: %@", error.localizedDescription)
            }
        default: return error.localizedDescription
        }
    }
}

extension ScreenKeyboardError {
    /// Errors raised after something reached the keyboard; the link blocks further sending until a reconnect.
    var stopsSending: Bool {
        switch self {
        case .needsReconnect, .rejected, .noAcknowledgement, .checksumMismatch: return true
        case .busy, .needsCable, .frameBusy: return false
        }
    }
}
