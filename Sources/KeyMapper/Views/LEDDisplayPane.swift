import AppKit
import KeyMapperCore
import SwiftUI

/// What the AMG65's 63 × 5 LED matrix shows, with a live preview of the same frames the keyboard gets.
struct LEDDisplayPane: View {
    @Environment(AppModel.self) private var model
    let device: KeyboardDevice
    @State private var started = Date()

    var body: some View {
        let display = model.preferences(for: device).display
        VStack(alignment: .leading, spacing: 12) {
            Toggle(L("Yapay zekâ kullanımını LED ekranda göster"), isOn: Binding(
                get: { display.enabled },
                set: { value in
                    model.updatePreferences(for: device) { $0.display.enabled = value }
                    model.updateLEDStream(device)
                }
            ))
            TimelineView(.periodic(from: started, by: 0.5)) { context in
                let seconds = context.date.timeIntervalSince(started)
                let scene = LEDScene.frame(settings: display, quotas: model.ledQuotas, activities: [], seconds: seconds,
                                           animationStep: Int(seconds * 2), now: context.date.timeIntervalSince1970)
                LEDMatrixPreview(pixels: scene.pixels)
            }
            Text(L("A = Claude, X = Codex, C = Cursor; sayılar kalan yüzdedir. Soluk değerler eski, -- bilinmiyor demektir."))
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    label(L("Gösterim"))
                    Picker(L("Gösterim"), selection: binding(\.mode)) {
                        Text(L("Genel bakış")).tag(LEDDisplaySettings.Mode.overview)
                        Text(L("Sırayla")).tag(LEDDisplaySettings.Mode.rotate)
                        Text(L("Metin")).tag(LEDDisplaySettings.Mode.text)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 300)
                }
                GridRow {
                    label(L("Araç"))
                    Picker(L("Araç"), selection: binding(\.trackedProvider)) {
                        Text(L("Tümü")).tag("all")
                        Text("Claude").tag("claude")
                        Text("Codex").tag("codex")
                        Text("Cursor").tag("cursor")
                    }
                    .labelsHidden()
                    .frame(maxWidth: 160)
                }
                if display.mode == .text {
                    GridRow {
                        label(L("Metin"))
                        HStack(spacing: 8) {
                            TextField(L("Metin"), text: Binding(
                                get: { display.text },
                                set: { value in model.updatePreferences(for: device) { $0.display.text = LEDDisplaySettings.sanitized(value) } }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 240)
                            ColorPicker(L("Renk"), selection: textColor, supportsOpacity: false).labelsHidden()
                        }
                    }
                }
                GridRow {
                    label(L("Efekt"))
                    Picker(L("Efekt"), selection: binding(\.textEffect)) {
                        Text(L("Yok")).tag(LEDTextEffect.none)
                        Text(L("Tarama")).tag(LEDTextEffect.scan)
                        Text(L("Nefes")).tag(LEDTextEffect.breathe)
                        Text(L("Matris")).tag(LEDTextEffect.matrix)
                        Text(L("Kayan")).tag(LEDTextEffect.scroll)
                    }
                    .labelsHidden()
                    .frame(maxWidth: 160)
                }
                GridRow {
                    label(L("Parlaklık"))
                    percentSlider(binding(\.brightness))
                }
                GridRow {
                    label(L("Claude renk dengesi"))
                    percentSlider(binding(\.claudeGreenGain))
                }
            }
            Text(L("Akış açıkken klavye kendi LED animasyonu yerine bu görüntüyü gösterir; kapatınca kendi animasyonuna döner."))
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 13))
    }

    private func label(_ text: String) -> some View { Text(text).foregroundStyle(Theme.textSecondary) }

    private func binding<T>(_ path: WritableKeyPath<LEDDisplaySettings, T>) -> Binding<T> {
        Binding(
            get: { model.preferences(for: device).display[keyPath: path] },
            set: { value in model.updatePreferences(for: device) { $0.display[keyPath: path] = value } }
        )
    }

    private var textColor: Binding<Color> {
        Binding(
            get: {
                let c = model.preferences(for: device).display.textColor
                return Color(red: Double(c.r) / 255, green: Double(c.g) / 255, blue: Double(c.b) / 255)
            },
            set: { color in
                guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
                let value = RGB24(r: UInt8((rgb.redComponent * 255).rounded()), g: UInt8((rgb.greenComponent * 255).rounded()),
                                     b: UInt8((rgb.blueComponent * 255).rounded()))
                model.updatePreferences(for: device) { $0.display.textColor = value }
            }
        )
    }

    private func percentSlider(_ value: Binding<Double>) -> some View {
        HStack(spacing: 8) {
            Slider(value: value, in: 0...1).frame(maxWidth: 220)
            Text("\(Int((value.wrappedValue * 100).rounded()))%").monospacedDigit()
                .foregroundStyle(Theme.textSecondary).frame(width: 40, alignment: .trailing)
        }
    }
}

/// The 63 × 5 matrix drawn as dots (brightness-scaled colours lifted so dim values stay visible).
struct LEDMatrixPreview: View {
    let pixels: [RGB24]

    var body: some View {
        Canvas { context, size in
            let columns = LEDMatrixRenderer.width, rows = LEDMatrixRenderer.height
            let cell = min(size.width / CGFloat(columns), size.height / CGFloat(rows))
            for y in 0..<rows {
                for x in 0..<columns {
                    let pixel = pixels[y * columns + x]
                    let lit = !pixel.isOff
                    let rect = CGRect(x: CGFloat(x) * cell + 1, y: CGFloat(y) * cell + 1, width: cell - 2, height: cell - 2)
                    let color = lit
                        ? Color(red: lift(pixel.r), green: lift(pixel.g), blue: lift(pixel.b))
                        : Color.white.opacity(0.06)
                    context.fill(Path(ellipseIn: rect), with: .color(color))
                }
            }
        }
        .frame(height: 50)
        .frame(maxWidth: 630)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.black))
        .accessibilityLabel(L("LED ekran önizlemesi"))
    }

    private func lift(_ channel: UInt8) -> Double { channel == 0 ? 0 : 0.25 + 0.75 * Double(channel) / 254 }
}
