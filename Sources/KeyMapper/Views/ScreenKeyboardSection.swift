import AppKit
import KeyMapperCore
import SwiftUI

/// Controls for keyboards with their own display (clock, backlight, device settings).
struct ScreenKeyboardSection: View {
    @Environment(AppModel.self) private var model
    let device: KeyboardDevice
    let channel: ScreenKeyboardChannel
    @State private var tab: Tab = .usage

    enum Tab: Hashable, CaseIterable {
        case usage, display, clock, lighting, settings

        var title: String {
            switch self {
            case .usage: return L("Yapay zekâ kullanımı")
            case .display: return L("LED ekran")
            case .clock: return L("Saat")
            case .lighting: return L("Işık")
            case .settings: return L("Ayarlar")
            }
        }
    }

    private var tabs: [Tab] { channel.link == .wired ? Tab.allCases : [.lighting] }
    private var status: ScreenKeyboardStatus { model.screenStatus[device.id] ?? .init() }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow(text: L("Ekran ve ışık"))
                Spacer()
                statusLine
            }
            if tabs.count > 1 {
                Picker(L("Bölüm"), selection: $tab) {
                    ForEach(tabs, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 560)
            }
            switch tabs.contains(tab) ? tab : tabs[0] {
            case .usage: UsagePanel()
            case .display: LEDDisplayPane(device: device)
            case .clock: ClockPane(device: device)
            case .lighting: LightingPane(device: device)
            case .settings: SettingsPane(device: device)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.line))
        .disabled(status.working != nil)
    }

    @ViewBuilder
    private var statusLine: some View {
        HStack(spacing: 8) {
            if let working = status.working {
                ProgressView().controlSize(.small)
                Text(working)
            } else {
                switch status.link {
                case .idle, .ready:
                    Text(channel.link == .wired ? L("USB kablosu") : L("2.4 GHz alıcı"))
                case .busy:
                    Image(systemName: "lock.fill")
                    Text(L("Başka bir uygulama (AMG65 Studio) klavyeyi kullanıyor"))
                    Button(L("Tekrar dene")) { Task { await model.retryScreenKeyboard(device) } }
                        .buttonStyle(SecondaryButtonStyle(height: 24))
                case .needsReconnect:
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.error)
                    Text(L("Gönderim durduruldu; kabloyu çıkarıp yeniden takın"))
                case let .failed(message):
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.error)
                    Text(message).lineLimit(2)
                    Button(L("Tekrar dene")) { Task { await model.retryScreenKeyboard(device) } }
                        .buttonStyle(SecondaryButtonStyle(height: 24))
                }
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(Theme.textSecondary)
    }
}

// MARK: - Clock

private struct ClockPane: View {
    @Environment(AppModel.self) private var model
    let device: KeyboardDevice

    var body: some View {
        let prefs = model.preferences(for: device)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button(L("Saati Mac ile eşitle")) { Task { await model.syncClock(device) } }
                    .buttonStyle(PrimaryButtonStyle(height: 28))
                Text(lastSync(prefs.lastClockSync))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
            Toggle(L("Bağlanınca, uyandıktan sonra ve 6 saatte bir otomatik eşitle"), isOn: Binding(
                get: { prefs.autoClock },
                set: { value in model.updatePreferences(for: device) { $0.autoClock = value } }
            ))
            Text(L("Saat dilimi: %@", TimeZone.autoupdatingCurrent.localizedName(for: .generic, locale: L10n.current.locale)
                    ?? TimeZone.autoupdatingCurrent.identifier))
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
        }
        .font(.system(size: 13))
    }

    private func lastSync(_ date: Date?) -> String {
        guard let date else { return L("Henüz eşitlenmedi") }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = L10n.current.locale
        return L("Son eşitleme: %@", formatter.localizedString(for: date, relativeTo: Date()))
    }
}

// MARK: - Lighting

private struct LightingPane: View {
    @Environment(AppModel.self) private var model
    let device: KeyboardDevice

    var body: some View {
        let prefs = model.preferences(for: device)
        let lighting = prefs.lighting
        let effect = AMG65Protocol.effects.first { $0.id == lighting.mode } ?? AMG65Protocol.effects[0]
        VStack(alignment: .leading, spacing: 12) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    label(L("Efekt"))
                    Picker(L("Efekt"), selection: binding(\.mode)) {
                        ForEach(AMG65Protocol.effects) { Text($0.title).tag($0.id) }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 240)
                }
                if effect.usesColor {
                    GridRow {
                        label(L("Renk"))
                        HStack(spacing: 12) {
                            ColorPicker(L("Renk"), selection: colorBinding, supportsOpacity: false)
                                .labelsHidden()
                                .disabled(lighting.colorful)
                            Toggle(L("Gökkuşağı"), isOn: binding(\.colorful))
                        }
                    }
                }
                GridRow {
                    label(L("Parlaklık"))
                    stepSlider(binding(\.brightness), range: 0...5)
                }
                if effect.usesSpeed {
                    GridRow {
                        label(L("Hız"))
                        stepSlider(binding(\.speed), range: 0...5)
                    }
                }
                if effect.usesDirection {
                    GridRow {
                        label(L("Yön"))
                        Picker(L("Yön"), selection: binding(\.direction)) {
                            Text(L("Yön %@", "1")).tag(UInt8(0))
                            Text(L("Yön %@", "2")).tag(UInt8(1))
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(maxWidth: 200)
                    }
                }
            }
            ApplyRow(pending: prefs.appliedLighting != lighting,
                     note: L("Klavye ışık ayarlarını geri okuyamaz; burada son gönderilen ayarlar görünür.")) {
                Task { await model.applyScreenLighting(device) }
            }
        }
        .font(.system(size: 13))
    }

    private func label(_ text: String) -> some View { Text(text).foregroundStyle(Theme.textSecondary) }

    private func binding<T>(_ path: WritableKeyPath<AMG65Lighting, T>) -> Binding<T> {
        Binding(
            get: { model.preferences(for: device).lighting[keyPath: path] },
            set: { value in model.updatePreferences(for: device) { $0.lighting[keyPath: path] = value } }
        )
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: {
                let c = model.preferences(for: device).lighting.color
                return Color(red: Double(c.r) / 255, green: Double(c.g) / 255, blue: Double(c.b) / 255)
            },
            set: { color in
                guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
                let value = RGB24(r: UInt8((rgb.redComponent * 255).rounded()), g: UInt8((rgb.greenComponent * 255).rounded()),
                                     b: UInt8((rgb.blueComponent * 255).rounded()))
                model.updatePreferences(for: device) {
                    $0.lighting.color = value
                    $0.lighting.colorful = false
                }
            }
        )
    }
}

// MARK: - Settings

private struct SettingsPane: View {
    @Environment(AppModel.self) private var model
    let device: KeyboardDevice

    var body: some View {
        let prefs = model.preferences(for: device)
        VStack(alignment: .leading, spacing: 12) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    Text(L("LED ekran parlaklığı")).foregroundStyle(Theme.textSecondary)
                    stepSlider(binding(\.screenBrightness), range: 1...7)
                }
                GridRow {
                    Text(L("Uyku")).foregroundStyle(Theme.textSecondary)
                    Picker(L("Uyku"), selection: binding(\.sleep)) {
                        Text(L("Hiçbir zaman")).tag(UInt8(0))
                        Text(L("%@ dakika", "1")).tag(UInt8(1))
                        Text(L("%@ dakika", "5")).tag(UInt8(2))
                        Text(L("%@ dakika", "30")).tag(UInt8(3))
                    }
                    .labelsHidden()
                    .frame(maxWidth: 160)
                }
            }
            Toggle(L("Fn tuşu basılı tutmak yerine aç/kapa çalışsın"), isOn: binding(\.fnToggle))
            Toggle(L("Oyun modu"), isOn: binding(\.gameMode))
            if prefs.settings.gameMode {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle(L("Alt+Tab'ı engelle"), isOn: binding(\.blockAltTab))
                    Toggle(L("Alt+F4'ü engelle"), isOn: binding(\.blockAltF4))
                    Toggle(L("Windows tuşunu engelle"), isOn: binding(\.blockWindowsKey))
                }
                .padding(.leading, 20)
            }
            ApplyRow(pending: prefs.appliedSettings != prefs.settings,
                     note: L("LED ekran parlaklığı doğrulandı; uyku, Fn ve oyun modunun bu klavyedeki etkisi henüz doğrulanmadı.")) {
                Task { await model.applyScreenSettings(device) }
            }
        }
        .font(.system(size: 13))
    }

    private func binding<T>(_ path: WritableKeyPath<AMG65DeviceSettings, T>) -> Binding<T> {
        Binding(
            get: { model.preferences(for: device).settings[keyPath: path] },
            set: { value in model.updatePreferences(for: device) { $0.settings[keyPath: path] = value } }
        )
    }
}

// MARK: - Shared

private struct ApplyRow: View {
    let pending: Bool
    let note: String
    let apply: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(note)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            if pending {
                Text(L("Gönderilmedi")).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.modified)
            }
            Button(L("Klavyeye gönder"), action: apply)
                .buttonStyle(PrimaryButtonStyle(height: 28))
        }
    }
}

/// A slider that snaps to whole steps and shows the value.
private func stepSlider(_ value: Binding<UInt8>, range: ClosedRange<UInt8>) -> some View {
    HStack(spacing: 8) {
        Slider(value: Binding(get: { Double(value.wrappedValue) }, set: { value.wrappedValue = UInt8($0.rounded()) }),
               in: Double(range.lowerBound)...Double(range.upperBound), step: 1)
            .frame(maxWidth: 220)
        Text("\(value.wrappedValue)").monospacedDigit().foregroundStyle(Theme.textSecondary).frame(width: 20, alignment: .trailing)
    }
}
