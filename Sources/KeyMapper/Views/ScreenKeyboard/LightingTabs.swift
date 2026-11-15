import KeyMapperCore
import SwiftUI

// MARK: - Effects

/// The backlight's built-in effects (command 0x13 over the cable, the dongle's own packets over 2.4 GHz).
struct EffectsTab: View {
    @Environment(AppModel.self) private var model
    let device: KeyboardDevice
    let channel: ScreenKeyboardChannel

    var body: some View {
        let prefs = model.preferences(for: device)
        let lighting = prefs.lighting
        let effect = AMG65Protocol.effects.first { $0.id == lighting.mode } ?? AMG65Protocol.effects[0]
        VStack(alignment: .leading, spacing: 14) {
            TabHeader(title: L("Arka ışık efekti"),
                      detail: L("Klavye ışık ayarlarını geri okuyamaz; burada son gönderilen ayarlar görünür."))
            if prefs.lastBacklight == .keyColors {
                Label(L("Klavye şu an tuş renklerini gösteriyor; bir efekt gönderince efekte geçer."), systemImage: "info.circle")
                    .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 8)], spacing: 8) {
                ForEach(AMG65Protocol.effects) { item in
                    EffectTile(effect: item, color: lighting.colorful ? nil : lighting.color, isSelected: item.id == lighting.mode) {
                        model.updatePreferences(for: device) { $0.lighting.mode = item.id }
                    }
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.success)
                Text(L("İşaretli efektler bu klavyede denendi."))
            }
            .font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
            ScreenCard(title: effect.title) {
                if effect.usesColor {
                    SettingRow(label: L("Renk")) {
                        WrapLayout(spacing: 10, lineSpacing: 8) {
                            SwatchRow(color: Binding(
                                get: { lighting.color },
                                set: { value in model.updatePreferences(for: device) { $0.lighting.color = value; $0.lighting.colorful = false } }
                            ), isActive: !lighting.colorful, label: L("Renk"))
                            Toggle(L("Gökkuşağı"), isOn: binding(\.colorful)).toggleStyle(.checkbox)
                        }
                    }
                }
                SettingRow(label: L("Parlaklık")) { StepPicker(value: binding(\.brightness), range: 0...5, label: L("Parlaklık")) }
                if effect.usesSpeed {
                    SettingRow(label: L("Hız")) { StepPicker(value: binding(\.speed), range: 0...5, label: L("Hız")) }
                }
                if effect.usesDirection {
                    SettingRow(label: L("Yön")) {
                        Segmented(label: L("Yön"), selection: binding(\.direction),
                                  options: [(UInt8(0), L("Yön %@", "1")), (UInt8(1), L("Yön %@", "2"))], maxWidth: 200)
                    }
                }
            }
            ApplyRow(pending: prefs.appliedLighting != lighting || prefs.lastBacklight == .keyColors,
                     note: effect.confirmed ? L("Bu efekt bu klavyede denendi.") : L("Bu efekt bu klavyede henüz denenmedi."),
                     disabled: model.isScreenBusy(device)) {
                Task { await model.applyScreenLighting(device) }
            }
        }
        .font(.system(size: 13))
    }

    private func binding<T>(_ path: WritableKeyPath<AMG65Lighting, T>) -> Binding<T> {
        Binding(
            get: { model.preferences(for: device).lighting[keyPath: path] },
            set: { value in model.updatePreferences(for: device) { $0.lighting[keyPath: path] = value } }
        )
    }
}

private struct EffectTile: View {
    let effect: AMG65Effect
    /// nil = rainbow.
    let color: RGB24?
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        Button(action: select) {
            VStack(alignment: .leading, spacing: 8) {
                // On a dark strip, like the LEDs themselves, so white and dim dots show in light mode too.
                HStack(spacing: 3) {
                    ForEach(0..<8, id: \.self) { index in
                        Capsule().fill(dot(index)).frame(height: 5)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.black.opacity(0.88)))
                HStack(spacing: 4) {
                    Text(effect.title).font(.system(size: 12, weight: isSelected ? .semibold : .regular)).lineLimit(1)
                    Spacer(minLength: 0)
                    if effect.confirmed {
                        Image(systemName: "checkmark.seal.fill").font(.system(size: 10)).foregroundStyle(Theme.success)
                            .accessibilityLabel(L("Denendi"))
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(isSelected ? Theme.accentTint : Theme.control))
            .overlay(shape.strokeBorder(isSelected ? Theme.accent : Theme.line, lineWidth: isSelected ? 1.5 : 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// A small, fixed pattern per effect so the tiles are told apart at a glance (not a simulation).
    private func dot(_ index: Int) -> Color {
        if effect.id == 20 { return Color.white.opacity(0.12) }
        let level = effect.id == 1 ? 1 : 0.3 + 0.7 * Double((index * 5 + Int(effect.id) * 3) % 8) / 7
        guard let color else { return Color(hue: Double(index) / 8, saturation: 0.75, brightness: 0.95).opacity(level) }
        return Color(color).opacity(level)
    }
}

// MARK: - Per-key colours

/// Paint keys one by one; sending switches the backlight from its effect to these colours.
struct KeyColorsTab: View {
    @Environment(AppModel.self) private var model
    let device: KeyboardDevice
    @State private var brush = RGB24(r: 10, g: 132, b: 255)
    @State private var erasing = false

    var body: some View {
        let prefs = model.preferences(for: device)
        let colors = prefs.keyColors
        VStack(alignment: .leading, spacing: 14) {
            TabHeader(title: L("Tuş renkleri"),
                      detail: L("Tuşlara tek tek renk verin; tıklayın ya da sürükleyerek boyayın. Boyanmamış tuşlar kapalı kalır."))
            WrapLayout(spacing: 10, lineSpacing: 8) {
                SwatchRow(color: Binding(get: { brush }, set: { brush = $0; erasing = false }), isActive: !erasing, label: L("Fırça rengi"))
                Button { erasing.toggle() } label: { Label(L("Silgi"), systemImage: "eraser") }
                    .buttonStyle(PillButtonStyle(isOn: erasing, height: 26))
                Button(L("Hepsini boya")) {
                    model.updatePreferences(for: device) { prefs in
                        for key in AMG65Layout.litKeys { prefs.keyColors[key.slot] = brush }
                    }
                }
                .buttonStyle(SecondaryButtonStyle(height: 26))
                Button(L("Temizle")) { model.updatePreferences(for: device) { $0.keyColors = [:] } }
                    .buttonStyle(SecondaryButtonStyle(height: 26))
                    .disabled(colors.isEmpty)
            }
            AMG65KeyboardView(keys: AMG65Layout.litKeys, paintsOnDrag: true) { key in
                AMG65CapModel(legend: key.name, fill: colors[key.slot].map { Color($0) })
            } onPick: { key in
                let value: RGB24? = erasing ? nil : brush
                guard colors[key.slot] != value else { return }
                model.updatePreferences(for: device) { $0.keyColors[key.slot] = value }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.stage))
            SettingRow(label: L("Parlaklık")) {
                StepPicker(value: Binding(
                    get: { prefs.keyColorBrightness },
                    set: { value in model.updatePreferences(for: device) { $0.keyColorBrightness = value } }
                ), range: 1...5, label: L("Parlaklık"))
            }
            // Nothing painted and nothing sent yet: sending would only turn every key off.
            let untouched = colors.isEmpty && prefs.appliedKeyColors == nil
            ApplyRow(pending: !untouched && (prefs.keyColorsPending || prefs.lastBacklight != .keyColors),
                     note: L("Klavye renkleri geri okuyamaz; burada son gönderilenler görünür. Bu klavyede henüz denenmedi."),
                     disabled: untouched || model.isScreenBusy(device)) {
                Task { await model.applyKeyColors(device) }
            }
        }
        .font(.system(size: 13))
    }
}
