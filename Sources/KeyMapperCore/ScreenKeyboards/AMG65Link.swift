import Darwin
import Foundation

public enum ScreenKeyboardError: LocalizedError, Equatable {
    /// Another program (e.g. AMG65 Studio's bridge) holds the keyboard's vendor channel.
    case busy
    /// An earlier transaction stopped half way; nothing is sent until the keyboard is reconnected.
    case needsReconnect
    /// The keyboard answered a packet with a failure status.
    case rejected(step: String, status: UInt8)
    /// No (or a wrong) acknowledgement for a packet.
    case noAcknowledgement(step: String)
    /// The end reply's checksum differs from the data that was sent.
    case checksumMismatch
    /// The feature needs the USB cable (the receiver doesn't carry it).
    case needsCable
    /// The matrix was busy and dropped a live frame (RAM only); the next frame may be sent after a pause.
    case frameBusy

    public var errorDescription: String? {
        switch self {
        case .busy:
            return L("Klavyeyi şu an başka bir uygulama kullanıyor (ör. AMG65 Studio). O uygulamayı kapatıp tekrar deneyin.")
        case .needsReconnect:
            return L("Önceki işlem yarıda kaldığı için klavyeye gönderim durduruldu. Kabloyu çıkarıp yeniden takın.")
        case let .rejected(step, status):
            return L("Klavye \"%@\" paketini reddetti (durum 0x%@); gönderim durduruldu. Kabloyu çıkarıp yeniden takın.",
                     step, String(format: "%02X", status))
        case let .noAcknowledgement(step):
            return L("Klavye \"%@\" paketini onaylamadı; gönderim durduruldu. Kabloyu çıkarıp yeniden takın.", step)
        case .checksumMismatch:
            return L("Klavyenin sağlama toplamı gönderilen veriyle eşleşmedi; gönderim durduruldu. Kabloyu çıkarıp yeniden takın.")
        case .needsCable:
            return L("Bu özellik için klavyeyi USB kablosuyla bağlayın.")
        case .frameBusy:
            return L("LED ekran meşguldü; kare atlandı.")
        }
    }
}

/// Serialised transactions with a LEOBOG AMG65 over its vendor HID interface.
///
/// Safety rules (from AMG65 Studio, verified on the keyboard):
/// - every packet must be acknowledged; a failure status, a missing or wrong acknowledgement or a checksum
///   mismatch stops all sending until the keyboard is reconnected (a new IORegistry id), and the stop survives
///   an app restart;
/// - no packet is ever retried, because a repeated packet would corrupt the transaction;
/// - the per-user lock `/private/tmp/amg65-hid-<uid>.lock` is held while connected, the same lock AMG65 Studio
///   takes, so two programs never interleave packets.
public final class AMG65Link: @unchecked Sendable {
    public let channel: ScreenKeyboardChannel
    private let connection: RawHIDConnection
    private let lock: Int32
    private var liveFramesActive = false
    private var lastFrame = Date.distantPast

    public init(channel: ScreenKeyboardChannel) throws {
        guard !Self.isBlocked(channel.registryID) else { throw ScreenKeyboardError.needsReconnect }
        let fd = open("/private/tmp/amg65-hid-\(getuid()).lock", O_RDWR | O_CREAT | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw ScreenKeyboardError.busy }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(fd)
            throw ScreenKeyboardError.busy
        }
        do {
            connection = try RawHIDConnection(registryID: channel.registryID, reportSize: channel.reportSize)
        } catch {
            Darwin.close(fd)
            throw error
        }
        self.channel = channel
        self.lock = fd
    }

    deinit { close() }

    private var closed = false

    public func close() {
        guard !closed else { return }
        closed = true
        if liveFramesActive { try? run(AMG65Protocol.stopLiveFrames) }
        connection.close()
        Darwin.close(lock)
    }

    public var isClosed: Bool { closed || connection.isClosed }

    // MARK: Cable

    /// Runs one transaction. Live frames are ended first when something else is sent.
    public func run(_ steps: [AMG65Protocol.Step]) throws {
        guard channel.link == .wired else { throw ScreenKeyboardError.needsCable }
        guard !Self.isBlocked(channel.registryID) else { throw ScreenKeyboardError.needsReconnect }
        let isFrame = steps.contains { $0.kind == .command && $0.bytes[1] == 0x35 }
        let isStop = steps == AMG65Protocol.stopLiveFrames
        if liveFramesActive && !isFrame && !isStop {
            try transact(AMG65Protocol.stopLiveFrames, liveFrame: false)
            liveFramesActive = false
        }
        do {
            try transact(steps, liveFrame: isFrame)
        } catch ScreenKeyboardError.frameBusy {
            liveFramesActive = true
            throw ScreenKeyboardError.frameBusy
        }
        if isFrame { liveFramesActive = true }
        if isStop { liveFramesActive = false }
    }

    /// Sends one live LED-matrix frame, paced to what the keyboard acknowledges reliably.
    public func showFrame(_ pixels: [RGB24]) throws {
        let wait = AMG65Protocol.minimumFrameInterval - Date().timeIntervalSince(lastFrame)
        if wait > 0 { Thread.sleep(forTimeInterval: wait) }
        try run(AMG65Protocol.liveFrame(pixels))
        lastFrame = Date()
    }

    /// Hands the LED matrix back to the keyboard's own animation.
    public func endFrames() throws {
        guard liveFramesActive else { return }
        try run(AMG65Protocol.stopLiveFrames)
    }

    /// `liveFrame`: a busy status (0xFF) on the frame's end packet drops that frame without stopping the
    /// link. AMG65 Studio treated it as fatal and needed a replug every ~15 minutes; live frames only touch RAM.
    private func transact(_ steps: [AMG65Protocol.Step], liveFrame: Bool) throws {
        let checksum = AMG65Protocol.checksum(steps)
        let hasCountedData = steps.contains { $0.kind == .data }
        for step in steps {
            let reply: [UInt8]
            do {
                // A flush may be answered with 00 00 00 FF, so it doesn't filter on the 04 prefix.
                reply = try connection.exchange(step.bytes, timeout: 1.0, retries: 0,
                                                expecting: step.kind == .flush ? nil : 0x04)
            } catch {
                throw fail(.noAcknowledgement(step: step.label))
            }
            let expected = step.expectedOpcode
            let envelope = reply.count >= 4 && reply[0] == 0x04 && reply[1] == expected && reply[2] == 0
            if envelope && reply[3] == 0xFF && liveFrame && step.kind == .command && step.bytes[1] == 0x02 {
                throw ScreenKeyboardError.frameBusy
            }
            if envelope && reply[3] != 1 { throw fail(.rejected(step: step.label, status: reply[3])) }
            let acknowledged = envelope || (step.kind == .flush && reply.starts(with: [0, 0, 0, 0xFF]))
            guard acknowledged else { throw fail(.noAcknowledgement(step: step.label)) }
            if hasCountedData && step.bytes[1] == 0x02 && step.kind == .command {
                let echoed = reply.count >= 6 ? UInt16(reply[4]) | UInt16(reply[5]) << 8 : nil
                guard echoed == checksum else { throw fail(.checksumMismatch) }
            }
            Thread.sleep(forTimeInterval: 0.010)
        }
    }

    // MARK: Receiver

    /// Sends receiver packets; each reply must echo the packet's command, length and index.
    public func runDongle(_ packets: [[UInt8]]) throws {
        guard channel.link == .dongle else { throw ScreenKeyboardError.needsCable }
        guard !Self.isBlocked(channel.registryID) else { throw ScreenKeyboardError.needsReconnect }
        for (index, packet) in packets.enumerated() {
            let label = L("alıcı paketi %@", "\(index + 1)/\(packets.count)")
            guard packet.count == 32,
                  let reply = try? connection.exchange(packet, timeout: 1.0, retries: 0, expecting: packet[0]),
                  reply.count >= 3, Array(reply.prefix(3)) == Array(packet.prefix(3)) else {
                throw fail(.noAcknowledgement(step: label))
            }
            Thread.sleep(forTimeInterval: 0.010)
        }
    }

    // MARK: Stop after failure

    /// Blocks further sending to this keyboard until it is reconnected, and returns the error to throw.
    private func fail(_ error: ScreenKeyboardError) -> ScreenKeyboardError {
        Self.block(channel.registryID)
        liveFramesActive = false
        return error
    }

    private static let blockedKey = "screenKeyboard.blockedRegistryIDs"

    static func isBlocked(_ registryID: UInt64) -> Bool {
        (UserDefaults.standard.array(forKey: blockedKey) as? [String] ?? []).contains(String(registryID))
    }

    static func block(_ registryID: UInt64) {
        var list = UserDefaults.standard.array(forKey: blockedKey) as? [String] ?? []
        guard !list.contains(String(registryID)) else { return }
        list = Array((list + [String(registryID)]).suffix(16))
        UserDefaults.standard.set(list, forKey: blockedKey)
    }
}
