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
    case actions = "Aksiyon"
    case international = "Uluslararası"

    var id: String { rawValue }

    /// Categories that make sense for macOS level (HID keyboard page) remapping.
    static let osRemap: [PickerCategory] = [.basic, .modifiers, .navigation, .numpad, .actions, .international]
}

/// Palette of assignable keycodes drawn as mini keycaps, with category pills and search.
struct KeycodePicker: View {
    let keycodes: KeycodeSet
    let layerCount: Int
    let categories: [PickerCategory]
    /// Restricts the choice (macOS remap only supports keyboard page usages).
    var filter: (UInt16) -> Bool = { _ in true }
    /// Extra caption per keycode (e.g. the action bound to F16).
    var annotations: [UInt16: String] = [:]
    let onPick: (UInt16) -> Void

    @State private var category: PickerCategory = .basic
    @State private var search = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(categories) { item in
                            Button(item.rawValue) { category = item; search = "" }
                                .buttonStyle(PillButtonStyle(isOn: category == item && search.isEmpty, style: .inverted))
                        }
                    }
                }
                SearchField(text: $search)
                    .frame(width: 200)
            }
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 56, maximum: 84), spacing: 8)], spacing: 8) {
                    ForEach(codes, id: \.self) { code in
                        let kind = CapKind.of(code, keycodes: keycodes)
                        Button {
                            onPick(code)
                        } label: {
                            Keycap(kind: kind == .empty ? .modifier : kind, radius: 9, depth: 6) {
                                KeyLegend(label: label(for: code), unit: 50, kind: kind == .empty ? .modifier : kind,
                                          subColor: kind == .layer ? Theme.cobaltText : Theme.signal)
                            }
                            .frame(height: 50)
                        }
                        .buttonStyle(.plain)
                        .help(annotations[code].map { "Aksiyon: \($0)\n\(keycodes.name(for: code))" } ?? "\(keycodes.title(for: code))\n\(keycodes.name(for: code))")
                        .accessibilityLabel("Ata: \(keycodes.name(for: code))")
                    }
                }
                .padding(2)
            }
            .scrollIndicators(.automatic)
        }
    }

    private func label(for code: UInt16) -> KeyLabel {
        var label = keycodes.label(for: code).withPlaceholder(code: code)
        if let name = annotations[code] { label.sub = name }
        return label
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
                    || (annotations[code]?.lowercased().contains(query) ?? false)
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
        case .actions: return TriggerKey.all.map(\.usage)
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

extension KeyLabel {
    /// KC_NO has an empty legend; show a symbol in pickers so the key is recognisable.
    func withPlaceholder(code: UInt16) -> KeyLabel {
        main.isEmpty ? KeyLabel(top: top, main: code == 0 ? "∅" : "?", sub: sub) : self
    }
}

struct SearchField: View {
    @Binding var text: String
    var prompt = "Ara: space, LT, mute…"

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Theme.text)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textTertiary) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Aramayı temizle")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.ground))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
    }
}
