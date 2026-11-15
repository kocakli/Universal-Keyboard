import AppKit
import KeyMapperCore
import SwiftUI

/// Backlight / RGB controls for a VIA or Vial keyboard. Every change is shown on the keyboard right away;
/// "Save to keyboard" makes it survive unplugging.
struct LightingPanel: View {
    @Environment(AppModel.self) private var model
    let device: KeyboardDevice
    @State private var selected: LightingKind?
    @State private var loading = true

    private var capabilities: [LightingCapability] { model.lightingCapabilities(for: device) }
    private var capability: LightingCapability? {
        capabilities.first { $0.kind == selected } ?? capabilities.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("Işıklar")).font(.headline)
            if capabilities.count > 1 {
                Picker(L("Işık"), selection: Binding(get: { capability?.kind ?? .rgbMatrix }, set: { selected = $0 })) {
                    ForEach(capabilities, id: \.kind) { Text($0.kind.title).tag($0.kind) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            if loading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(L("Klavyeden okunuyor…")).foregroundStyle(Theme.textSecondary)
                }
            } else if let capability, let value = model.lightingValues[device.id]?[capability.kind] {
                controls(capability, value)
            } else {
                Text(L("Işık ayarları okunamadı.")).foregroundStyle(Theme.textSecondary)
            }
        }
        .font(.system(size: 13))
        .padding(16)
        .frame(width: 340)
        .task {
            await model.loadLighting(device)
            loading = false
        }
    }

    @ViewBuilder
    private func controls(_ capability: LightingCapability, _ value: LightingState) -> some View {
        let kind = capability.kind
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                Text(L("Efekt")).foregroundStyle(Theme.textSecondary)
                effectControl(capability, value)
            }
            GridRow {
                Text(L("Parlaklık")).foregroundStyle(Theme.textSecondary)
                slider(value.brightness, field: .brightness, kind: kind, value: value) { $0.brightness = $1 }
            }
            if kind.hasSpeed {
                GridRow {
                    Text(L("Hız")).foregroundStyle(Theme.textSecondary)
                    slider(value.speed, field: .speed, kind: kind, value: value) { $0.speed = $1 }
                }
            }
            if kind.hasColor {
                GridRow {
                    Text(L("Renk")).foregroundStyle(Theme.textSecondary)
                    ColorPicker(L("Renk"), selection: colorBinding(kind: kind, value: value), supportsOpacity: false)
                        .labelsHidden()
                }
            }
        }

        Text(L("Değişiklikler klavyede hemen görünür; çıkarıp takınca da kalması için klavyeye kaydedin."))
            .font(.system(size: 11))
            .foregroundStyle(Theme.textTertiary)
            .fixedSize(horizontal: false, vertical: true)

        HStack {
            Button(L("Geri al")) { Task { await model.revertLighting(kind, device: device) } }
                .buttonStyle(SecondaryButtonStyle(height: 28))
                .disabled(!model.hasUnsavedLighting(kind, device: device))
            Spacer()
            Button(L("Klavyeye kaydet")) { Task { await model.saveLighting(kind, device: device) } }
                .buttonStyle(PrimaryButtonStyle(height: 28))
                .disabled(!model.hasUnsavedLighting(kind, device: device))
        }
    }

    @ViewBuilder
    private func effectControl(_ capability: LightingCapability, _ value: LightingState) -> some View {
        let kind = capability.kind
        if capability.effects.isEmpty {
            // The firmware's effect list is unknown: step through numbers (QMK clamps out-of-range modes).
            Stepper(value: Binding(get: { value.effect }, set: { update(value, field: .effect, kind: kind) { $0.effect = $1 }(min(max($0, 0), 255)) }),
                    in: 0...255) {
                Text(value.effect == 0 ? L("Kapalı") : L("Efekt %@", "\(value.effect)")).monospacedDigit()
            }
        } else {
            Picker(L("Efekt"), selection: Binding(get: { value.effect }, set: { update(value, field: .effect, kind: kind) { $0.effect = $1 }($0) })) {
                ForEach(capability.effects, id: \.id) { Text(Self.effectTitle($0.name)).tag($0.id) }
                if !capability.effects.contains(where: { $0.id == value.effect }) {
                    Text(L("Efekt %@", "\(value.effect)")).tag(value.effect)
                }
            }
            .labelsHidden()
        }
    }

    private func slider(_ current: Int, field: LightingField, kind: LightingKind, value: LightingState,
                        apply: @escaping (inout LightingState, Int) -> Void) -> some View {
        HStack(spacing: 8) {
            Slider(value: Binding(get: { Double(current) }, set: { update(value, field: field, kind: kind, apply)(Int($0.rounded())) }),
                   in: 0...255)
            Text("\(current * 100 / 255)%").monospacedDigit().foregroundStyle(Theme.textSecondary).frame(width: 40, alignment: .trailing)
        }
    }

    /// Hue and saturation come from the picker; brightness stays on its own slider (QMK keeps them apart).
    private func colorBinding(kind: LightingKind, value: LightingState) -> Binding<Color> {
        Binding(
            get: {
                Color(hue: Double(value.hue) / 255, saturation: Double(value.saturation) / 255, brightness: 1)
            },
            set: { color in
                guard let rgb = NSColor(color).usingColorSpace(.deviceRGB) else { return }
                var updated = model.lightingValues[device.id]?[kind] ?? value
                updated.hue = Int((rgb.hueComponent * 255).rounded())
                updated.saturation = Int((rgb.saturationComponent * 255).rounded())
                model.setLighting(updated, field: .color, kind: kind, device: device)
            }
        )
    }

    private func update(_ value: LightingState, field: LightingField, kind: LightingKind,
                        _ apply: @escaping (inout LightingState, Int) -> Void) -> (Int) -> Void {
        { newValue in
            var updated = model.lightingValues[device.id]?[kind] ?? value
            apply(&updated, newValue)
            model.setLighting(updated, field: field, kind: kind, device: device)
        }
    }

    /// "07. RAINBOW_MOVING_CHEVRON" → "Rainbow Moving Chevron" (VIA definitions use QMK enum names).
    static func effectTitle(_ name: String) -> String {
        var text = name
        if let dot = text.firstIndex(of: "."), text[..<dot].allSatisfy(\.isNumber) {
            text = String(text[text.index(after: dot)...]).trimmingCharacters(in: .whitespaces)
        }
        guard text.contains("_") || text == text.uppercased() else { return text }
        return text.split(separator: "_").map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }.joined(separator: " ")
    }
}
