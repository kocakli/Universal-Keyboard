import AppKit
import KeyMapperCore
import SwiftUI

/// What the AMG65's 63 × 5 LED matrix shows, with a live preview of the same frames the keyboard gets.
struct LEDDisplayTab: View {
    @Environment(AppModel.self) private var model
    let device: KeyboardDevice
    @State private var started = Date()

    var body: some View {
        let display = model.preferences(for: device).display
        VStack(alignment: .leading, spacing: 14) {
            TabHeader(title: L("LED ekranda yapay zekâ kullanımı"),
                      detail: L("Akış açıkken klavye kendi LED animasyonu yerine bu görüntüyü gösterir; kapatınca kendi animasyonuna döner.")) {
                Toggle(L("Göster"), isOn: Binding(
                    get: { display.enabled },
                    set: { value in
                        model.updatePreferences(for: device) { $0.display.enabled = value }
                        model.updateLEDStream(device)
                    }
                ))
                .toggleStyle(.switch)
            }
            TimelineView(.periodic(from: started, by: 0.5)) { context in
                let seconds = context.date.timeIntervalSince(started)
                LEDMatrixPreview(pixels: model.ledScene(for: device, seconds: seconds, step: Int(seconds * 2), now: context.date))
            }
            Text(L("A = Claude, X = Codex, C = Cursor; sayılar kalan yüzdedir. Soluk değerler eski, -- bilinmiyor demektir."))
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
            AdaptiveColumns(minimum: 330) {
                ScreenCard(title: L("Gösterim")) {
                    SettingRow(label: L("Görünüm")) {
                        Segmented(label: L("Görünüm"), selection: binding(\.mode), options: [
                            (.overview, L("Genel bakış")), (.rotate, L("Sırayla")), (.text, L("Metin")),
                        ])
                    }
                    SettingRow(label: L("Araç")) {
                        Segmented(label: L("Araç"), selection: binding(\.trackedProvider), options: [
                            ("all", L("Tümü")), ("claude", "Claude"), ("codex", "Codex"), ("cursor", "Cursor"),
                        ])
                    }
                    if display.mode == .text {
                        SettingRow(label: L("Metin")) {
                            HStack(spacing: 8) {
                                TextField(L("Metin"), text: Binding(
                                    get: { display.text },
                                    set: { value in model.updatePreferences(for: device) { $0.display.text = LEDDisplaySettings.sanitized(value) } }
                                ))
                                .textFieldStyle(.roundedBorder)
                                ColorPicker(L("Renk"), selection: Binding(
                                    get: { Color(display.textColor) },
                                    set: { color in if let value = RGB24(color) { model.updatePreferences(for: device) { $0.display.textColor = value } } }
                                ), supportsOpacity: false).labelsHidden()
                            }
                        }
                    }
                    SettingRow(label: L("Parlaklık")) { PercentSlider(value: binding(\.brightness), label: L("Parlaklık")) }
                    SettingRow(label: L("Efekt")) {
                        WrapLayout(spacing: 6, lineSpacing: 6) {
                            ForEach(LEDTextEffect.allCases, id: \.self) { effect in
                                Button(Self.title(effect)) { model.updatePreferences(for: device) { $0.display.textEffect = effect } }
                                    .buttonStyle(PillButtonStyle(isOn: display.textEffect == effect, height: 26))
                            }
                        }
                    }
                }
                ScreenCard(title: L("Etkinlik")) {
                    SwitchRow(label: L("Araç çalışırken veya onay beklerken göster"), isOn: binding(\.activityEnabled))
                    SwitchRow(label: L("Karakterle göster"), isOn: binding(\.mascotEnabled))
                        .disabled(!display.activityEnabled)
                    if !model.activityEnabled {
                        Text(L("Etkinlik için Yapay zekâ sekmesinde “Araçların ne yaptığını izle”yi açın."))
                            .font(.system(size: 11)).foregroundStyle(Theme.textTertiary).fixedSize(horizontal: false, vertical: true)
                    }
                    Rectangle().fill(Theme.line).frame(height: 1)
                    SettingRow(label: L("Claude renk dengesi"), labelWidth: 130) {
                        PercentSlider(value: binding(\.claudeGreenGain), label: L("Claude renk dengesi"))
                    }
                    Text(L("Bazı klavyelerde Claude'un turuncusu sarı görünür; yeşili azaltarak düzeltin."))
                        .font(.system(size: 11)).foregroundStyle(Theme.textTertiary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .font(.system(size: 13))
    }

    static func title(_ effect: LEDTextEffect) -> String {
        switch effect {
        case .none: return L("Yok")
        case .scan: return L("Tarama")
        case .breathe: return L("Nefes")
        case .matrix: return L("Matris")
        case .scroll: return L("Kayan")
        }
    }

    private func binding<T>(_ path: WritableKeyPath<LEDDisplaySettings, T>) -> Binding<T> {
        Binding(
            get: { model.preferences(for: device).display[keyPath: path] },
            set: { value in model.updatePreferences(for: device) { $0.display[keyPath: path] = value } }
        )
    }
}

/// Label on the left, switch on the right.
struct SwitchRow: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(label).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Toggle(label, isOn: $isOn).toggleStyle(.switch).controlSize(.small).labelsHidden()
        }
        .font(.system(size: 13))
    }
}

/// 0…1 as a slider with the percentage beside it.
struct PercentSlider: View {
    @Binding var value: Double
    let label: String

    var body: some View {
        HStack(spacing: 8) {
            Slider(value: $value, in: 0...1).accessibilityLabel(label)
            Text(value.formatted(.percent.precision(.fractionLength(0)).locale(L10n.current.locale)))
                .monospacedDigit().foregroundStyle(Theme.textSecondary).frame(width: 44, alignment: .trailing)
        }
    }
}

/// The 63 × 5 matrix drawn as dots (brightness-scaled colours lifted so dim values stay visible).
/// Without a height it fills the width; with one it is a fixed-size thumbnail.
struct LEDMatrixPreview: View {
    let pixels: [RGB24]
    var height: CGFloat?

    var body: some View {
        let columns = LEDMatrixRenderer.width, rows = LEDMatrixRenderer.height
        let canvas = Canvas { context, size in
            let cell = min(size.width / CGFloat(columns), size.height / CGFloat(rows))
            let inset = max(cell * 0.12, 0.5)
            for y in 0..<rows {
                for x in 0..<columns {
                    let index = y * columns + x
                    let pixel = index < pixels.count ? pixels[index] : .off
                    let rect = CGRect(x: CGFloat(x) * cell + inset, y: CGFloat(y) * cell + inset, width: cell - 2 * inset, height: cell - 2 * inset)
                    let color = pixel.isOff
                        ? Color.white.opacity(0.07)
                        : Color(red: lift(pixel.r), green: lift(pixel.g), blue: lift(pixel.b))
                    context.fill(Path(ellipseIn: rect), with: .color(color))
                }
            }
        }
        .aspectRatio(CGFloat(columns) / CGFloat(rows), contentMode: .fit)
        .accessibilityLabel(L("LED ekran önizlemesi"))
        if let height {
            canvas.frame(height: height)
                .padding(.horizontal, 3).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 3, style: .continuous).fill(Color.black))
        } else {
            canvas.frame(maxWidth: 760)
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.black))
        }
    }

    private func lift(_ channel: UInt8) -> Double { channel == 0 ? 0 : 0.25 + 0.75 * Double(channel) / 254 }
}
