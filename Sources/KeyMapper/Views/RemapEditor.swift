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
        let layout = RemapLayout.for(device)
        // A layout with nothing selectable (a trackball over Bluetooth) shows no selection, even one left from another device.
        let selected: KeySlot? = layout.hasSelectableKeys ? selection.map { .matrix(row: 0, col: Int($0)) } : nil
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Text(layout.note ?? L("Bu klavye programlanabilir firmware sunmuyor; eşlemeler macOS tarafından yalnızca bu klavyeye uygulanır ve klavye her bağlandığında yeniden uygulanır."))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                if layout.hasSelectableKeys { presetMenu }
                Button(L("Tümünü kaldır")) { model.setRemaps([], device: device, persist: true) }
                    .buttonStyle(SecondaryButtonStyle(height: 32))
                    .disabled(remaps.isEmpty)
            }

            KeyboardStage {
                KeyboardCanvas(keys: layout.board, selected: selected,
                               cap: { cap(for: $0, in: layout, remaps: remaps) }, onSelect: { select($0, in: layout) },
                               maxUnit: 52, deviceBody: layout.deviceBody)
                    .frame(minHeight: layout.hasSelectableKeys ? 260 : 180)
                if !layout.offBoard.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("Klavyenin üstünde olmayan tuşlar")).font(.system(size: 12, weight: .semibold))
                        Text(L("Klavye bunları Fn ile ya da başka bir yolla gönderirse macOS onları da eşler."))
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                        KeyboardCanvas(keys: layout.offBoard, selected: selected,
                                       cap: { cap(for: $0, in: layout, remaps: remaps) }, onSelect: { select($0, in: layout) },
                                       maxUnit: 40)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if !layout.hasSelectableKeys {
                // Nothing to select, so no picker.
            } else if let app = model.selectedApp[device.id] {
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

    /// Fixed keys (the AMG65's Fn, a trackball's buttons) can't be selected: macOS can't remap them.
    private func select(_ key: LayoutKey, in layout: RemapLayout) {
        guard layout.fixed[key] == nil, key.col >= 0 else { return }
        selection = UInt16(key.col)
    }

    private func cap(for key: LayoutKey, in layout: RemapLayout, remaps: [UInt16: UInt16]) -> KeyCapModel {
        if let fixed = layout.fixed[key] {
            return KeyCapModel(label: fixed.label, kind: .empty, tooltip: fixed.tooltip)
        }
        let usage = UInt16(clamping: key.col)
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

/// What the remap editor draws for a keyboard. A plain HID keyboard reports which usages it can send, not where its
/// keys are, so a keyboard gets its real layout only when KeyMapper knows the model; the rest get a generic TKL.
struct RemapLayout {
    /// A key macOS can't remap: what its cap shows instead of a usage.
    struct Fixed {
        var label: KeyLabel
        var tooltip: String
    }

    /// Keys whose `col` is the HID usage they send, except those in `fixed`.
    var board: [LayoutKey]
    /// Usages with no key on the board that the keyboard may still send (e.g. through Fn).
    var offBoard: [LayoutKey] = []
    var fixed: [LayoutKey: Fixed] = [:]
    /// Shown instead of the firmware sentence and the key picker when no key can be selected.
    var note: String?
    /// A trackball's or mouse's body, drawn behind its buttons.
    var deviceBody: DeviceBody?

    var hasSelectableKeys: Bool { board.contains { fixed[$0] == nil } || !offBoard.isEmpty }

    @MainActor static func `for`(_ device: KeyboardDevice) -> RemapLayout {
        // By model, not by the vendor channel: the Bluetooth AMG65 has none, and the cable's appears after the keyboard.
        if device.screenKeyboard?.model == .leobogAMG65 || device.name.range(of: "AMG65", options: .caseInsensitive) != nil {
            let keys = AMG65Layout.remapKeys
            let fn = Fixed(label: KeyLabel(main: "Fn"),
                           tooltip: L("Fn'yi klavye kendisi işler; macOS onu görmediği için burada eşlenemez."))
            return RemapLayout(board: keys, offBoard: AMG65Layout.offBoardKeys,
                               fixed: Dictionary(uniqueKeysWithValues: keys.filter { $0.col < 0 }.map { ($0, fn) }))
        }
        if let pointing = pointingDevice(device) { return pointing }
        return RemapLayout(board: ANSILayout.keys)
    }

    /// A Keychron trackball or mouse (Nape Pro…) without its raw HID channel (Bluetooth): its own buttons, from the
    /// definition the cable editor cached. What each button sends is set in its firmware and isn't known here, so
    /// none can be selected.
    @MainActor private static func pointingDevice(_ device: KeyboardDevice) -> RemapLayout? {
        let key = device.vendorProductID
        if pointingCache[key] == nil {
            pointingCache[key] = .some(KeychronLauncher.cachedPointingDevice(vendorID: device.vendorID, productID: device.productID))
        }
        guard let definition = pointingCache[key] ?? nil else { return nil }
        let tooltip = L("Bu düğmenin ne gönderdiği cihazın firmware'inde ayarlanır; USB kablosuyla bağlayınca değiştirebilirsiniz.")
        let fixed = Dictionary(definition.keys.map { key -> (LayoutKey, Fixed) in
            guard let direction = key.encoderDirection else { return (key, Fixed(label: KeyLabel(main: key.name ?? ""), tooltip: tooltip)) }
            return (key, Fixed(label: KeyLabel(main: direction == 0 ? "↺" : "↻"), tooltip: tooltip))
        }, uniquingKeysWith: { a, _ in a })
        return RemapLayout(board: definition.keys, fixed: fixed,
                           note: L("%@ fare tipi bir cihaz; düğmelerinin ne gönderdiği firmware'inde ayarlanır ve kablosuz bağlantıda okunamaz. Düğmeleri değiştirmek için USB kablosuyla bağlayın.", definition.name),
                           deviceBody: definition.deviceBody)
    }

    /// Cached definitions per vendor/product id (`.some(nil)`: looked, not a pointing device or never opened by cable).
    @MainActor private static var pointingCache: [Int: KeyboardDefinition?] = [:]
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
