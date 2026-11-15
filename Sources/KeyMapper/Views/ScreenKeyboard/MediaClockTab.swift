import AppKit
import KeyMapperCore
import SwiftUI
import UniformTypeIdentifiers

/// The LCD picture, the clock, and the LED matrix's own animation. Both uploads write the keyboard's flash memory.
struct MediaClockTab: View {
    let device: KeyboardDevice

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AdaptiveColumns(minimum: 340) {
                LCDCard(device: device)
                ClockCard(device: device)
            }
            StripAnimationCard(device: device)
        }
        .font(.system(size: 13))
    }
}

/// Measured on the AMG65 (Studio): about 5.8 blocks of 4 KB per second, acknowledged one by one.
private let blocksPerSecond = 5.8

private func durationText(_ seconds: Double) -> String {
    Duration.seconds(max(1, seconds.rounded()))
        .formatted(.units(allowed: [.minutes, .seconds], width: .abbreviated).locale(L10n.current.locale))
}

private func chooseFile(_ types: [UTType]) -> URL? {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = types
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    return panel.runModal() == .OK ? panel.url : nil
}

// MARK: - LCD

private struct LCDCard: View {
    @Environment(AppModel.self) private var model
    let device: KeyboardDevice
    @State private var file: URL?
    @State private var fill = true
    @State private var animation: AMG65LCDAnimation?
    @State private var blocks = 0
    @State private var loading = false
    @State private var loadFailed = false
    @State private var dropTargeted = false

    var body: some View {
        let busy = model.isScreenBusy(device)
        ScreenCard(title: L("LCD ekran resmi")) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    preview
                    if let animation, animation.frames.count > 1 {
                        HStack(spacing: 4) {
                            ForEach(Array(animation.frames.prefix(5).enumerated()), id: \.offset) { _, frame in
                                Image(decorative: frame, scale: 1).resizable().aspectRatio(contentMode: .fit)
                                    .frame(width: 34).clipShape(RoundedRectangle(cornerRadius: 2))
                            }
                            if animation.frames.count > 5 {
                                Text("+\(animation.frames.count - 5)").font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                            }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    dropZone
                    Segmented(label: L("Yerleşim"), selection: Binding(get: { fill }, set: { fill = $0; reload() }),
                              options: [(true, L("Doldur")), (false, L("Sığdır"))], maxWidth: 200)
                    if let animation {
                        Text(L("%@ kare · tahmini süre %@", "\(min(animation.frames.count, AMG65LCDFormat.maxFrames))",
                               durationText(Double(blocks) / blocksPerSecond)))
                            .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                        if animation.truncated {
                            Text(L("Klavye en çok %@ kare alır; fazlası atlanır.", "\(AMG65LCDFormat.maxFrames)"))
                                .font(.system(size: 11)).foregroundStyle(Theme.modified)
                        }
                    }
                }
            }
            UploadStatus(device: device, kind: .lcd)
            FlashWarning(text: L("Klavyenin kalıcı belleğine yazılır. Yükleme bitene kadar kabloyu çıkarmayın."))
            HStack {
                TestedTag(tested: false)
                Spacer()
                Button(L("Klavyeye yükle")) {
                    guard let animation else { return }
                    Task { await model.uploadLCD(device, animation: animation) }
                }
                .buttonStyle(PrimaryButtonStyle(height: 28))
                .disabled(animation == nil || busy)
            }
        }
    }

    private var preview: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        return ZStack {
            shape.fill(Color.black)
            if let frame = animation?.frames.first {
                Image(decorative: frame, scale: 1).resizable().aspectRatio(contentMode: .fit)
            } else if loading {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "photo").font(.system(size: 22)).foregroundStyle(.white.opacity(0.35))
            }
        }
        .frame(width: 192, height: 108)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Theme.line))
        .accessibilityLabel(L("LCD önizlemesi"))
    }

    private var dropZone: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return VStack(alignment: .leading, spacing: 6) {
            Text(file?.lastPathComponent ?? L("Resim veya GIF bırakın")).lineLimit(1).truncationMode(.middle)
            Text(loadFailed ? L("Bu dosya okunamadı.") : L("PNG, JPG veya GIF; 240 × 135'e uyarlanır."))
                .font(.system(size: 11)).foregroundStyle(loadFailed ? Theme.error : Theme.textTertiary)
            Button(file == nil ? L("Dosya seç…") : L("Başka dosya seç…")) {
                if let url = chooseFile([.png, .jpeg, .gif, .image]) { load(url) }
            }
            .buttonStyle(SecondaryButtonStyle(height: 24))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(dropTargeted ? Theme.accentTint : Color.clear))
        .overlay(shape.strokeBorder(dropTargeted ? Theme.accent : Theme.line, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            load(url)
            return true
        } isTargeted: { dropTargeted = $0 }
    }

    private func load(_ url: URL) {
        file = url
        reload()
    }

    /// Decoding and scaling a GIF can take a moment; it runs off the main thread.
    private func reload() {
        guard let file else { return }
        loading = true
        loadFailed = false
        let fill = fill
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> (AMG65LCDAnimation, Int)? in
                guard let animation = AMG65LCDAnimation.load(url: file, fill: fill) else { return nil }
                return (animation, animation.buffer().blocks)
            }.value
            guard file == self.file else { return }
            loading = false
            animation = result?.0
            blocks = result?.1 ?? 0
            loadFailed = result == nil
        }
    }
}

// MARK: - Clock

private struct ClockCard: View {
    @Environment(AppModel.self) private var model
    let device: KeyboardDevice

    var body: some View {
        let prefs = model.preferences(for: device)
        ScreenCard(title: L("Saat")) {
            TimelineView(.everyMinute) { context in
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.date.formatted(.dateTime.hour().minute().locale(L10n.current.locale)))
                        .font(.system(size: 36, weight: .semibold, design: .rounded)).monospacedDigit()
                    Text(context.date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(L10n.current.locale)))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(L("Saat dilimi: %@", TimeZone.autoupdatingCurrent.localizedName(for: .generic, locale: L10n.current.locale)
                        ?? TimeZone.autoupdatingCurrent.identifier))
                // The schedule's dates are minute boundaries, so the text is measured from the real time.
                TimelineView(.periodic(from: .now, by: 5)) { _ in
                    Text(ClockText.lastSync(prefs.lastClockSync, now: Date(), short: false))
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(Theme.textSecondary)
            Button(L("Saati Mac ile eşitle")) { Task { await model.syncClock(device) } }
                .buttonStyle(SecondaryButtonStyle(height: 26))
                .disabled(model.isScreenBusy(device))
            Rectangle().fill(Theme.line).frame(height: 1)
            SwitchRow(label: L("Otomatik eşitle"), isOn: Binding(
                get: { prefs.autoClock },
                set: { value in model.updatePreferences(for: device) { $0.autoClock = value } }
            ))
            Text(L("Klavye bağlanınca, Mac uyanınca, saat dilimi değişince ve 6 saatte bir."))
                .font(.system(size: 11)).foregroundStyle(Theme.textTertiary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - LED matrix animation

private struct StripAnimationCard: View {
    @Environment(AppModel.self) private var model
    let device: KeyboardDevice
    @AppStorage("screenKeyboard.strip.target") private var targetRaw = AMG65StripTarget.animation.rawValue
    @AppStorage("screenKeyboard.strip.fromText") private var fromText = true
    @AppStorage("screenKeyboard.strip.text") private var text = "KEYMAPPER"
    @AppStorage("screenKeyboard.strip.color") private var colorHex = "#7BDCB0"
    @AppStorage("screenKeyboard.strip.delay") private var delay = 10
    @AppStorage("screenKeyboard.strip.brightness") private var brightness = 5
    @State private var gif: AMG65StripAnimation?
    @State private var gifFailed = false
    @State private var started = Date()

    private var target: AMG65StripTarget { AMG65StripTarget(rawValue: targetRaw) ?? .animation }
    private var color: RGB24 { RGB24(hex: colorHex) ?? RGB24(r: 0x7B, g: 0xDC, b: 0xB0) }

    private var animation: AMG65StripAnimation? {
        if fromText {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? nil : .scrollingText(trimmed, color: color)
        }
        return gif
    }

    var body: some View {
        let frameMs = AMG65StripAnimation.estimatedFrameMs(delay: UInt16(delay))
        // Built once per change, not on every preview tick.
        let animation = self.animation
        ScreenCard(title: L("LED ekran animasyonu")) {
            AdaptiveColumns(minimum: 300) {
                VStack(alignment: .leading, spacing: 10) {
                    SettingRow(label: L("Hedef"), labelWidth: 80) {
                        Segmented(label: L("Hedef"), selection: $targetRaw, options: [
                            (AMG65StripTarget.animation.rawValue, L("Animasyon")), (AMG65StripTarget.boot.rawValue, L("Açılış animasyonu")),
                        ], maxWidth: 260)
                    }
                    SettingRow(label: L("Kaynak"), labelWidth: 80) {
                        Segmented(label: L("Kaynak"), selection: $fromText, options: [(true, L("Metin")), (false, "GIF")], maxWidth: 160)
                    }
                    if fromText {
                        SettingRow(label: L("Metin"), labelWidth: 80) {
                            HStack(spacing: 8) {
                                TextField(L("Metin"), text: Binding(get: { text }, set: { text = String($0.prefix(48)) }))
                                    .textFieldStyle(.roundedBorder)
                                ColorPicker(L("Renk"), selection: Binding(
                                    get: { Color(color) }, set: { if let value = RGB24($0) { colorHex = value.hex } }
                                ), supportsOpacity: false).labelsHidden()
                            }
                        }
                    } else {
                        SettingRow(label: L("Dosya"), labelWidth: 80) {
                            HStack(spacing: 8) {
                                Text(gif?.name ?? (gifFailed ? L("Bu dosya okunamadı.") : L("Dosya seçilmedi")))
                                    .lineLimit(1).truncationMode(.middle)
                                    .foregroundStyle(gifFailed ? Theme.error : Theme.textSecondary)
                                Button(L("Dosya seç…")) {
                                    guard let url = chooseFile([.gif, .png, .jpeg, .image]) else { return }
                                    gif = AMG65StripAnimation.load(url: url)
                                    gifFailed = gif == nil
                                }
                                .buttonStyle(SecondaryButtonStyle(height: 24))
                            }
                        }
                    }
                    SettingRow(label: L("Hız"), labelWidth: 80) {
                        HStack(spacing: 8) {
                            Slider(value: Binding(get: { Double(delay) }, set: { delay = Int($0.rounded()) }), in: 1...100)
                                .accessibilityLabel(L("Hız"))
                            Text(L("kare başına ~%@ ms", "\(Int(frameMs.rounded()))"))
                                .monospacedDigit().font(.system(size: 11)).foregroundStyle(Theme.textSecondary).frame(width: 120, alignment: .trailing)
                        }
                    }
                    SettingRow(label: L("Parlaklık"), labelWidth: 80) {
                        StepPicker(value: Binding(get: { UInt8(brightness) }, set: { brightness = Int($0) }), range: 1...5, label: L("Parlaklık"))
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    TimelineView(.periodic(from: started, by: frameMs / 1000)) { context in
                        let frames = animation?.frames ?? []
                        let index = frames.isEmpty ? 0 : Int(context.date.timeIntervalSince(started) * 1000 / frameMs) % frames.count
                        LEDMatrixPreview(pixels: frames.isEmpty ? [] : scaled(frames[index]))
                    }
                    if let animation {
                        let count = min(animation.frames.count, target.maxFrames)
                        // Same size as `AMG65StripAnimation.buffer`: 4 header bytes, 3 per LED per frame, AA 55, 4 KB blocks.
                        let blocks = (4 + count * AMG65StripFormat.leds * 3 + 2 + 4095) / 4096
                        Text(L("%@ kare · tahmini süre %@", "\(count)", durationText(Double(blocks) / blocksPerSecond)))
                            .font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                        if animation.frames.count > target.maxFrames {
                            Text(L("Bu hedef en çok %@ kare alır; fazlası atlanır.", "\(target.maxFrames)"))
                                .font(.system(size: 11)).foregroundStyle(Theme.modified)
                        }
                    }
                    if model.preferences(for: device).display.enabled {
                        Text(L("Yapay zekâ kullanımı LED ekranda açıkken klavye onu gösterir; bu animasyon, gösterimi kapatınca oynar."))
                            .font(.system(size: 11)).foregroundStyle(Theme.textTertiary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            UploadStatus(device: device, kind: .strip)
            FlashWarning(text: L("Klavyenin kalıcı belleğine yazılır ve klavyedeki animasyonun yerini alır."))
            HStack {
                TestedTag(tested: false)
                Spacer()
                Button(L("Klavyeye yükle")) {
                    guard let animation else { return }
                    Task {
                        await model.uploadStrip(device, animation: animation, target: target, delay: UInt8(clamping: delay),
                                                brightness: UInt8(clamping: brightness))
                    }
                }
                .buttonStyle(PrimaryButtonStyle(height: 28))
                .disabled(animation == nil || model.isScreenBusy(device))
            }
        }
    }

    /// The preview shows the brightness the keyboard will get.
    private func scaled(_ frame: [RGB24]) -> [RGB24] {
        let k = Double(brightness) / 5
        return frame.map { RGB24(r: UInt8(Double($0.r) * k), g: UInt8(Double($0.g) * k), b: UInt8(Double($0.b) * k)) }
    }
}

/// Progress of a running upload, or why the last one stopped.
private struct UploadStatus: View {
    @Environment(AppModel.self) private var model
    let device: KeyboardDevice
    let kind: ScreenUploadState.Kind

    var body: some View {
        if let state = model.screenUploads[device.id], state.kind == kind {
            if state.isRunning {
                HStack(spacing: 10) {
                    ProgressView(value: state.progress)
                    Text(state.progress.formatted(.percent.precision(.fractionLength(0)).locale(L10n.current.locale)))
                        .monospacedDigit().font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                }
            } else if let error = state.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12)).foregroundStyle(Theme.error)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
