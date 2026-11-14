import KeyMapperCore
import SwiftUI

/// macOS level remapping for keyboards without VIA/Vial firmware (Logitech, Apple, Razer, ...).
/// Each key is identified by its HID usage, stored in `LayoutKey.col`.
struct RemapEditor: View {
    @Environment(AppModel.self) private var model
    let device: KeyboardDevice
    @State private var selection: UInt16?

    private let keycodes = KeycodeSet.v6

    var body: some View {
        let remaps = Dictionary(model.currentRemaps(device).map { ($0.from, $0.to) }, uniquingKeysWith: { a, _ in a })
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Text("Bu klavye programlanabilir firmware sunmuyor; eşlemeler macOS tarafından (hidutil) yalnızca bu klavyeye uygulanır. KeyMapper klavye her bağlandığında eşlemeleri yeniden uygular.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Menu("Hazır eşlemeler") {
                    ForEach(AlphaLayout.all.dropFirst()) { layout in
                        Button("Alfabe: \(layout.name)") { model.mergeRemaps(AlphaLayout.remaps(to: layout), device: device) }
                    }
                    Divider()
                    ForEach(HIDUtilRemapper.presets, id: \.name) { preset in
                        Button(preset.name) { model.mergeRemaps(preset.remaps, device: device) }
                    }
                }
                .fixedSize()
                Button("Tümünü kaldır", role: .destructive) { model.setRemaps([], device: device, persist: true) }
                    .disabled(remaps.isEmpty)
            }

            KeyboardCanvas(
                keys: ANSILayout.keys,
                selected: selection.map { .matrix(row: 0, col: Int($0)) },
                cap: { key in
                    let usage = UInt16(key.col)
                    if let target = remaps[usage] {
                        var label = keycodes.label(for: target)
                        label.sub = "← " + keycodes.shortLabel(usage)
                        return KeyCapModel(label: label, style: .modified, tooltip: "\(keycodes.title(for: usage)) → \(keycodes.title(for: target))")
                    }
                    return KeyCapModel(label: keycodes.label(for: usage), tooltip: keycodes.title(for: usage))
                },
                onSelect: { selection = UInt16($0.col) }
            )
            .frame(minHeight: 200)

            HStack {
                if let selection {
                    Text("\(keycodes.title(for: selection))").font(.callout.weight(.semibold))
                    if let target = remaps[selection] {
                        Text("→ \(keycodes.title(for: target))").font(.callout)
                        Button("Eşlemeyi kaldır") { model.setRemap(from: selection, to: nil, device: device) }
                    } else {
                        Text("eşlenmemiş").font(.callout).foregroundStyle(.secondary)
                    }
                } else {
                    Text("Bir tuş seçin, ardından aşağıdan ne yazması gerektiğini seçin.").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
            }

            KeycodePicker(keycodes: keycodes, layerCount: 1, categories: PickerCategory.osRemap,
                          filter: { (0x04...0xA4).contains($0) || (0xE0...0xE7).contains($0) }) { code in
                guard let selection else { return }
                model.setRemap(from: selection, to: code, device: device)
            }
            .disabled(selection == nil)
            .opacity(selection == nil ? 0.5 : 1)
        }
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
