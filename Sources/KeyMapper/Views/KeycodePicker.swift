import KeyMapperCore
import SwiftUI

enum PickerCategory: String, CaseIterable, Identifiable {
    case basic, letters, modifiers, navigation, numpad, media, mouse, layers, special, actions, international

    var id: String { rawValue }

    var title: String {
        switch self {
        case .basic: return L("Temel")
        case .letters: return L("Harfler")
        case .modifiers: return L("Değiştirici")
        case .navigation: return L("Gezinme / F")
        case .numpad: return L("Numpad")
        case .media: return L("Medya")
        case .mouse: return L("Fare")
        case .layers: return L("Katman")
        case .special: return L("Özel")
        case .actions: return L("Uygulama ve aksiyon")
        case .international: return L("Uluslararası")
        }
    }

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
    /// Longer description per keycode that replaces the generic explanation (e.g. what an action does).
    var details: [UInt16: String] = [:]
    /// Starts assigning a new action (open an app, URL, Shortcut, …) to the selected key.
    var onCreateAction: ((KeyAction.Kind) -> Void)?
    /// Makes the selected key type a letter (ğ, ş, ñ…); the "Harfler" category is hidden without it.
    var onLetter: ((String) -> Void)?
    /// Letter keys type nothing without Accessibility; the palette then offers the system prompt.
    var onGrantAccessibility: (() -> Void)?
    /// Letters already given a slot; removing one frees its slot.
    var assignedLetters: [LetterKey] = []
    var onRemoveLetter: ((LetterKey) -> Void)?
    let onPick: (UInt16) -> Void

    @State private var category: PickerCategory = .basic
    @State private var search = ""
    /// Keycode under the pointer; its explanation is shown in the info strip right away.
    @State private var hovered: UInt16?
    @State private var customLetter = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(shownCategories) { item in
                            Button(item.title) { category = item; search = "" }
                                .buttonStyle(PillButtonStyle(isOn: category == item && search.isEmpty, style: .inverted))
                        }
                    }
                }
                SearchField(text: $search)
                    .frame(width: 200)
            }
            if category == .actions, search.isEmpty, let onCreateAction { actionCreator(onCreateAction) }
            if category == .letters, search.isEmpty, let onLetter {
                letterPalette(onLetter)
            } else {
                codeGrid
            }
            infoStrip
        }
    }

    private var shownCategories: [PickerCategory] {
        categories.filter { $0 != .letters || onLetter != nil }
    }

    private var codeGrid: some View {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 56, maximum: 84), spacing: 8)], spacing: 8) {
                    ForEach(codes, id: \.self) { code in
                        let kind = CapKind.of(code, keycodes: keycodes)
                        Button {
                            onPick(code)
                        } label: {
                            Keycap(kind: kind == .empty ? .modifier : kind, radius: 9, depth: 6) {
                                KeyLegend(label: label(for: code), unit: 50, kind: kind == .empty ? .modifier : kind,
                                          subColor: kind == .layer ? Theme.layerText : Theme.accent)
                            }
                            .frame(height: 50)
                        }
                        .buttonStyle(.plain)
                        .onHover { inside in
                            if inside { hovered = code } else if hovered == code { hovered = nil }
                        }
                        .help("\(title(for: code))\n\(explanation(for: code))")
                        .accessibilityLabel(L("Ata: %@", title(for: code)))
                        .accessibilityHint(explanation(for: code))
                    }
                }
                .padding(2)
            }
            .scrollIndicators(.automatic)
    }

    /// Letters KeyMapper types itself: Turkish first, then other languages, then any letter typed in.
    private func letterPalette(_ pick: @escaping (String) -> Void) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(L("Mac'in klavye düzeninde olmayan harfleri KeyMapper yazar; Shift ya da Caps Lock büyük harfi yazar."))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let onGrantAccessibility {
                    HStack(spacing: 10) {
                        Image(systemName: "hand.raised.fill").foregroundStyle(Theme.accent)
                        Text(L("Erişilebilirlik izni olmadan harf tuşları hiçbir şey yazmaz."))
                            .font(.system(size: 12))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Button(L("İzin ver"), action: onGrantAccessibility)
                            .buttonStyle(SecondaryButtonStyle(height: 28))
                    }
                }
                Text(L("Türkçe")).font(Theme.label).foregroundStyle(Theme.textSecondary)
                letterGrid(LetterKeys.turkish, pick: pick)
                Text(L("Diğer diller")).font(Theme.label).foregroundStyle(Theme.textSecondary)
                letterGrid(LetterKeys.other, pick: pick)
                HStack(spacing: 8) {
                    TextField(L("Başka bir harf"), text: $customLetter)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .padding(.horizontal, 12)
                        .frame(width: 160, height: 32)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.ground))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
                        .onSubmit { pickCustom(pick) }
                    Button(L("Ata")) { pickCustom(pick) }
                        .buttonStyle(SecondaryButtonStyle(height: 32))
                        .disabled(LetterKey.sanitized(customLetter) == nil)
                }
                if !assignedLetters.isEmpty, let onRemoveLetter {
                    Text(L("Kullanılan harf yerleri: %@ / %@", "\(assignedLetters.count)", "\(LetterKeys.slots.count)"))
                        .font(Theme.label)
                        .foregroundStyle(Theme.textSecondary)
                    FlowLayout(spacing: 6) {
                        ForEach(assignedLetters) { letter in
                            Button {
                                onRemoveLetter(letter)
                            } label: {
                                Label(letter.legend, systemImage: "xmark")
                            }
                            .buttonStyle(PillButtonStyle(isOn: false, height: 28))
                            .help(L("%@ harfini kaldırır; ona atanmış tuşlar artık hiçbir şey yazmaz.", letter.legend))
                            .accessibilityLabel(L("Harfi kaldır: %@", letter.legend))
                        }
                    }
                }
            }
            .padding(2)
        }
    }

    private func pickCustom(_ pick: (String) -> Void) {
        guard let letter = LetterKey.sanitized(customLetter) else { return }
        pick(letter)
        customLetter = ""
    }

    private func letterGrid(_ letters: [String], pick: @escaping (String) -> Void) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 56, maximum: 84), spacing: 8)], spacing: 8) {
            ForEach(letters, id: \.self) { lower in
                let upper = LetterKey.uppercase(lower)
                Button {
                    pick(lower)
                } label: {
                    Keycap(kind: .alpha, radius: 9, depth: 6) {
                        KeyLegend(label: KeyLabel(top: upper == lower ? nil : upper, main: lower), unit: 50, kind: .alpha,
                                  subColor: Theme.accent)
                    }
                    .frame(height: 50)
                }
                .buttonStyle(.plain)
                .help(L("%@ · Shift ile %@", lower, upper))
                .accessibilityLabel(L("Ata: %@", lower))
            }
        }
    }

    /// One button per action type; existing actions follow below as keycaps.
    private func actionCreator(_ create: @escaping (KeyAction.Kind) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Bu tuşa basınca")).font(Theme.label).foregroundStyle(Theme.textSecondary)
            FlowLayout(spacing: 6) {
                ForEach(KeyAction.Kind.allCases) { kind in
                    Button {
                        create(kind)
                    } label: {
                        Label(kind.title, systemImage: kind.symbol)
                    }
                    .buttonStyle(PillButtonStyle(isOn: kind == .openApp, height: 30))
                    .help(kind.explanation)
                }
            }
            if !codes.isEmpty {
                Text(L("Mevcut aksiyonlar")).font(Theme.label).foregroundStyle(Theme.textSecondary).padding(.top, 4)
            }
        }
    }

    /// Shows what the hovered keycode does, without waiting for the system tooltip.
    private var infoStrip: some View {
        HStack(spacing: 12) {
            if let code = hovered {
                let kind = CapKind.of(code, keycodes: keycodes)
                Keycap(kind: kind == .empty ? .modifier : kind, radius: 7, depth: 4) {
                    KeyLegend(label: label(for: code), unit: 36, kind: kind == .empty ? .modifier : kind,
                              subColor: kind == .layer ? Theme.layerText : Theme.accent)
                }
                .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title(for: code)).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(explanation(for: code))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Text(keycodes.name(for: code))
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            } else {
                Image(systemName: "info.circle").foregroundStyle(Theme.textTertiary)
                Text(L("Bir işlevin üzerine gelince ne yaptığı burada görünür."))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 52)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.ground))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
        .animation(.easeOut(duration: 0.12), value: hovered)
    }

    private func title(for code: UInt16) -> String {
        if let name = annotations[code] { return L("Aksiyon: %@", name) }
        return keycodes.title(for: code)
    }

    private func explanation(for code: UInt16) -> String {
        details[code] ?? keycodes.explanation(for: code)
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
                    || explanation(for: code).lowercased().contains(query)
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
        // Letters are not keycodes until one is assigned; they have their own palette.
        case .letters: return []
        case .modifiers: return group(.modifiers)
        case .navigation: return group(.navigation, .function)
        case .numpad: return group(.numpad)
        case .media: return group(.media)
        case .mouse: return group(.mouse)
        case .international: return group(.international)
        // Existing actions only; bare F13–F20 stay under navigation / function keys.
        case .actions: return TriggerKey.all.map(\.usage).filter { annotations[$0] != nil }
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
    var prompt = L("Ara: space, LT, mute…")

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
                    .accessibilityLabel(L("Aramayı temizle"))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.ground))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
    }
}
