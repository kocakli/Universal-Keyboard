import KeyMapperCore
import SwiftUI

enum PickerCategory: String, CaseIterable, Identifiable {
    case basic = "Temel"
    case modifiers = "Değiştirici"
    case navigation = "Gezinme / F"
    case numpad = "Numpad"
    case media = "Medya"
    case mouse = "Fare"
    case layers = "Katman"
    case special = "Özel"
    case international = "Uluslararası"

    var id: String { rawValue }

    /// Categories that make sense for macOS level (HID keyboard page) remapping.
    static let osRemap: [PickerCategory] = [.basic, .modifiers, .navigation, .numpad, .international]
}

/// Grid of assignable keycodes with search.
struct KeycodePicker: View {
    let keycodes: KeycodeSet
    let layerCount: Int
    let categories: [PickerCategory]
    /// Restricts the choice (macOS remap only supports keyboard page usages).
    var filter: (UInt16) -> Bool = { _ in true }
    let onPick: (UInt16) -> Void

    @State private var category: PickerCategory = .basic
    @State private var search = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("Kategori", selection: $category) {
                    ForEach(categories) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                TextField("Ara (ör. space, LT, mute)", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
            }
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 58, maximum: 90), spacing: 6)], spacing: 6) {
                    ForEach(codes, id: \.self) { code in
                        let label = keycodes.label(for: code)
                        Button {
                            onPick(code)
                        } label: {
                            VStack(spacing: 0) {
                                if let top = label.top { Text(top).font(.caption2).foregroundStyle(.secondary) }
                                Text(label.main.isEmpty ? "∅" : label.main).font(.callout.weight(.medium)).lineLimit(1).minimumScaleFactor(0.6)
                                if let sub = label.sub { Text(sub).font(.caption2).foregroundStyle(Color.accentColor) }
                            }
                            .frame(maxWidth: .infinity, minHeight: 38)
                        }
                        .buttonStyle(.bordered)
                        .help("\(keycodes.title(for: code))\n\(keycodes.name(for: code))")
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var codes: [UInt16] {
        let all: [UInt16]
        if search.trimmingCharacters(in: .whitespaces).isEmpty {
            all = codes(for: category)
        } else {
            let query = search.lowercased()
            var seen = Set<UInt16>()
            all = categories.flatMap(codes(for:)).filter { code in
                guard seen.insert(code).inserted else { return false }
                let label = keycodes.label(for: code)
                return keycodes.name(for: code).lowercased().contains(query)
                    || keycodes.title(for: code).lowercased().contains(query)
                    || label.main.lowercased().contains(query)
            }
        }
        return all.filter(filter)
    }

    private func codes(for category: PickerCategory) -> [UInt16] {
        func group(_ groups: KeycodeGroup...) -> [UInt16] {
            keycodes.entries.filter { groups.contains($0.group) }.map(\.code)
        }
        switch category {
        case .basic: return group(.basic)
        case .modifiers: return group(.modifiers)
        case .navigation: return group(.navigation, .function)
        case .numpad: return group(.numpad)
        case .media: return group(.media)
        case .mouse: return group(.mouse)
        case .international: return group(.international)
        case .layers:
            var list: [UInt16] = []
            for function in [LayerFunction.MO, .TG, .TO, .TT, .OSL, .DF] {
                for layer in 0..<max(layerCount, 1) {
                    if let code = keycodes.encode(.layer(function, layer)) { list.append(code) }
                }
            }
            return list
        case .special:
            var list = group(.quantum, .lighting)
            list += keycodes.customKeycodes.indices.compactMap { keycodes.encode(.custom($0)) }
            list += (0..<16).compactMap { keycodes.encode(.macro($0)) }
            return list
        }
    }
}
