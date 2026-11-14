import KeyMapperCore
import SwiftUI

/// macOS level remapping for keyboards without VIA/Vial firmware (Logitech, Apple, Razer, ...).
/// Each key is identified by its HID usage, stored in `LayoutKey.col`.
struct RemapEditor: View {
    @Environment(AppModel.self) private var model
    let device: KeyboardDevice
    @State private var selection: UInt16?
    @State private var actionTarget: ActionsView.EditTarget?

    private let keycodes = KeycodeSet.v6

    var body: some View {
        let remaps = Dictionary(model.currentRemaps(device).map { ($0.from, $0.to) }, uniquingKeysWith: { a, _ in a })
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Text(L("Bu klavye programlanabilir firmware sunmuyor; eşlemeler macOS tarafından yalnızca bu klavyeye uygulanır ve klavye her bağlandığında yeniden uygulanır."))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                presetMenu
                Button(L("Tümünü kaldır")) { model.setRemaps([], device: device, persist: true) }
                    .buttonStyle(SecondaryButtonStyle(height: 32))
                    .disabled(remaps.isEmpty)
            }

            KeyboardStage {
                KeyboardCanvas(
                    keys: ANSILayout.keys,
                    selected: selection.map { .matrix(row: 0, col: Int($0)) },
                    cap: { key in
                        let usage = UInt16(key.col)
                        if let app = model.selectedApp[device.id] {
                            return model.appCap(code: remaps[usage] ?? usage, app: app, keycodes: keycodes)
                        }
                        if let target = remaps[usage], var cap = model.actionCap(code: target) {
                            cap.isHighlighted = true
                            return cap
                        }
                        if let target = remaps[usage] {
                            var label = keycodes.label(for: target)
                            label.sub = model.actionNamesByUsage[target] ?? ("← " + keycodes.shortLabel(usage))
                            return KeyCapModel(label: label, kind: CapKind.of(target, keycodes: keycodes), isHighlighted: true,
                                               tooltip: "\(keycodes.title(for: usage)) → \(keycodes.title(for: target))")
                        }
                        return KeyCapModel(label: keycodes.label(for: usage), kind: CapKind.of(usage, keycodes: keycodes),
                                           tooltip: "\(keycodes.title(for: usage))\n\(keycodes.explanation(for: usage))")
                    },
                    onSelect: { selection = UInt16($0.col) },
                    maxUnit: 52
                )
                .frame(minHeight: 260)
            }

            if let app = model.selectedApp[device.id] {
                AppKeyPanel(device: device, app: app, layer: 0, slot: selection.map { .matrix(row: 0, col: Int($0)) },
                            code: selection.map { remaps[$0] ?? $0 }, keycodes: keycodes)
            } else {
            HStack(alignment: .top, spacing: 18) {
                Panel {
                    VStack(alignment: .leading, spacing: 12) {
                        Eyebrow(text: L("Seçili tuş"))
                        if let selection {
                            HStack(spacing: 10) {
                                miniCap(selection)
                                Image(systemName: "arrow.right").foregroundStyle(Theme.textTertiary)
                                if let target = remaps[selection] { miniCap(target, highlighted: true) } else {
                                    Text(L("eşlenmemiş")).font(.system(size: 13)).foregroundStyle(Theme.textTertiary)
                                }
                            }
                            Text(keycodes.title(for: selection)).font(.system(size: 15, weight: .semibold))
                            Text(keycodes.explanation(for: remaps[selection] ?? selection))
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            if remaps[selection] != nil {
                                Button(L("Eşlemeyi kaldır")) { model.setRemap(from: selection, to: nil, device: device) }
                                    .buttonStyle(SecondaryButtonStyle(height: 32))
                            }
                        } else {
                            Text(L("Klavyeden bir tuş seçin")).font(.system(size: 15, weight: .semibold))
                            Text(L("Sonra paletten ne yazması gerektiğini seçin.")).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(width: 300, height: 380, alignment: .top)

                Panel {
                    KeycodePicker(keycodes: keycodes, layerCount: 1, categories: PickerCategory.osRemap,
                                  filter: { (0x04...0xA4).contains($0) || (0xE0...0xE7).contains($0) },
                                  annotations: model.actionNamesByUsage, details: model.actionDetailsByUsage,
                                  onCreateAction: startAction) { code in
                        guard let selection else { return }
                        model.setRemap(from: selection, to: code, device: device)
                    }
                    // Stays hoverable without a selection so descriptions can be read first.
                    .opacity(selection == nil ? 0.6 : 1)
                }
                .frame(height: 380)
            }
            }
        }
        .sheet(item: $actionTarget) { target in
            ActionEditorSheet(target: target) { action in
                actionTarget = nil
                guard let selection else { return }
                Task { await model.assignKeyAction(action, device: device, layer: 0, slot: .matrix(row: 0, col: Int(selection))) }
            } cancel: {
                actionTarget = nil
            }
        }
    }

    private func startAction(_ kind: KeyAction.Kind) {
        guard let selection else {
            model.errorMessage = L("Klavyeden bir tuş seçin")
            return
        }
        let binding = model.binding(forUsage: model.currentRemaps(device).first { $0.from == selection }?.to ?? selection)
        actionTarget = .init(bindingID: binding?.id, app: nil, initial: nil, kind: kind, title: L("Tuşa aksiyon ata"))
    }

    private func miniCap(_ code: UInt16, highlighted: Bool = false) -> some View {
        Keycap(kind: CapKind.of(code, keycodes: keycodes), isHighlighted: highlighted, radius: 9, depth: 6) {
            KeyLegend(label: keycodes.label(for: code), unit: 50, kind: CapKind.of(code, keycodes: keycodes))
        }
        .frame(width: 50, height: 50)
    }

    private var presetMenu: some View {
        Menu {
            ForEach(AlphaLayout.all.dropFirst()) { layout in
                Button(L("Alfabe: %@", layout.name)) { model.mergeRemaps(AlphaLayout.remaps(to: layout), device: device) }
            }
            Divider()
            ForEach(HIDUtilRemapper.presets, id: \.name) { preset in
                Button(L(preset.name)) { model.mergeRemaps(preset.remaps, device: device) }
            }
        } label: {
            HStack(spacing: 6) {
                Text(L("Hazır eşlemeler"))
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.textSecondary)
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.line))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

/// A generic ANSI TKL layout; `col` carries the HID usage of each key.
enum ANSILayout {
    static let keys: [LayoutKey] = {
        var keys: [LayoutKey] = []
        var y = 0.0
        func row(_ items: [(UInt16, Double)], startX: Double = 0, gapsAfter: [Int: Double] = [:]) {
            var x = startX
            for (index, item) in items.enumerated() {
                if item.0 != 0 { keys.append(LayoutKey(row: 0, col: Int(item.0), x: x, y: y, w: item.1)) }
                x += item.1 + (gapsAfter[index] ?? 0)
            }
        }
        // F row
        row([(0x29, 1)] + (0x3A...0x45).map { ($0, 1.0) } + [(0x46, 1), (0x47, 1), (0x48, 1)],
            gapsAfter: [0: 1, 4: 0.5, 8: 0.5, 12: 0.25])
        y += 1.25
        // Number row + nav
        row([(0x35, 1)] + (0x1E...0x27).map { ($0, 1.0) } + [(0x2D, 1), (0x2E, 1), (0x2A, 2), (0x49, 1), (0x4A, 1), (0x4B, 1)],
            gapsAfter: [13: 0.25])
        y += 1
        row([(0x2B, 1.5), (0x14, 1), (0x1A, 1), (0x08, 1), (0x15, 1), (0x17, 1), (0x1C, 1), (0x18, 1), (0x0C, 1), (0x12, 1), (0x13, 1),
             (0x2F, 1), (0x30, 1), (0x31, 1.5), (0x4C, 1), (0x4D, 1), (0x4E, 1)], gapsAfter: [13: 0.25])
        y += 1
        row([(0x39, 1.75), (0x04, 1), (0x16, 1), (0x07, 1), (0x09, 1), (0x0A, 1), (0x0B, 1), (0x0D, 1), (0x0E, 1), (0x0F, 1),
             (0x33, 1), (0x34, 1), (0x28, 2.25)])
        y += 1
        row([(0xE1, 2.25), (0x1D, 1), (0x1B, 1), (0x06, 1), (0x19, 1), (0x05, 1), (0x11, 1), (0x10, 1), (0x36, 1), (0x37, 1),
             (0x38, 1), (0xE5, 2.75), (0, 1.25), (0x52, 1)])
        y += 1
        row([(0xE0, 1.25), (0xE2, 1.25), (0xE3, 1.25), (0x2C, 6.25), (0xE7, 1.25), (0xE6, 1.25), (0x65, 1.25), (0xE4, 1.25),
             (0x50, 1), (0x51, 1), (0x4F, 1)], gapsAfter: [7: 0.25])
        return keys
    }()
}
