import KeyMapperCore
import SwiftUI

/// The keyboard's own key table: works on any computer, written to the keyboard's flash memory.
struct KeysTab: View {
    @Environment(AppModel.self) private var model
    let device: KeyboardDevice
    @State private var selectedSlot: Int?
    @State private var category: Category = .key
    @State private var modifiers: UInt8 = 0

    enum Category: Hashable { case key, media, mouse }

    private var keys: [AMG65Key] { AMG65Layout.keys.filter { !$0.isKnob } }

    var body: some View {
        let prefs = model.preferences(for: device)
        let map = prefs.keyMap
        let selected = selectedSlot.flatMap { slot in keys.first { $0.slot == slot } }
        VStack(alignment: .leading, spacing: 14) {
            TabHeader(title: L("Klavyenin kendi tuş tablosu"),
                      detail: L("Klavyeye yazılır ve başka bir bilgisayarda da çalışır. Fn ve döner düğme değiştirilemez."))
            FlashWarning(text: L("Klavyenin kalıcı belleğine yazılır. İlk gönderim, klavyede daha önce kaydedilmiş atamaların hepsinin yerini alır."))
            AMG65KeyboardView(keys: keys, selected: selectedSlot) { key in
                AMG65CapModel(legend: key.name, sub: map[key.slot].map(KeyActionText.title),
                              isHighlighted: map[key.slot] != nil, isDimmed: !key.remappable)
            } onPick: { key in
                guard key.remappable else { return }
                select(key.slot, map: map)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.stage))
            HStack(alignment: .top, spacing: 12) {
                inspector(selected, map: map).frame(width: 250)
                picker(selected, map: map)
            }
            ApplyRow(pending: prefs.keyMapPending,
                     note: map.isEmpty ? L("Tüm tuşlar fabrika ayarında.") : L("%@ tuş değiştirildi.", "\(map.count)"),
                     disabled: model.isScreenBusy(device),
                     secondary: map.isEmpty ? nil : (L("Tümünü varsayılana döndür"), { model.updatePreferences(for: device) { $0.keyMap = [:] } })) {
                Task { await model.applyKeyMap(device) }
            }
        }
        .font(.system(size: 13))
    }

    // MARK: Inspector

    private func inspector(_ key: AMG65Key?, map: [Int: AMG65KeyAction]) -> some View {
        ScreenCard(title: L("Seçili tuş")) {
            if let key {
                let action = map[key.slot]
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(key.name).font(.system(size: 18, weight: .semibold))
                    Image(systemName: "arrow.right").font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                    Text(action.map(KeyActionText.title) ?? L("Varsayılan"))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(action == nil ? Theme.textSecondary : Theme.accent)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                Text(L("Varsayılan: %@", AMG65HIDKeys.name(key.code).map(AMG65Names.name) ?? key.name))
                    .font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                if action != nil {
                    Button(L("Varsayılana döndür")) { assign(nil, to: key) }
                        .buttonStyle(SecondaryButtonStyle(height: 24))
                }
            } else {
                Text(L("Değiştirmek için klavyede bir tuşa tıklayın."))
                    .foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
            let others = map.filter { $0.key != key?.slot }.sorted { $0.key < $1.key }
            if !others.isEmpty {
                Rectangle().fill(Theme.line).frame(height: 1)
                Eyebrow(text: L("Diğer atamalar"))
                ForEach(others, id: \.key) { slot, action in
                    Button { select(slot, map: map) } label: {
                        HStack {
                            Text(keys.first { $0.slot == slot }?.name ?? "\(slot)")
                            Spacer(minLength: 8)
                            Text(KeyActionText.title(action)).foregroundStyle(Theme.accent).lineLimit(1)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                }
            }
        }
    }

    // MARK: Picker

    private func picker(_ key: AMG65Key?, map: [Int: AMG65KeyAction]) -> some View {
        let current = key.flatMap { map[$0.slot] }
        return ScreenCard {
            HStack(spacing: 10) {
                Segmented(label: L("Tür"), selection: $category,
                          options: [(.key, L("Tuş")), (.media, L("Medya")), (.mouse, L("Fare"))], maxWidth: 240)
                Spacer()
                if category != .key {
                    TestedTag(tested: false)
                }
            }
            switch category {
            case .key:
                HStack(spacing: 6) {
                    Text(L("Değiştiriciler")).foregroundStyle(Theme.textSecondary).padding(.trailing, 4)
                    ForEach(AMG65Modifier.allCases, id: \.self) { modifier in
                        Button(modifier.symbol) { toggle(modifier, key: key, current: current) }
                            .buttonStyle(PillButtonStyle(isOn: modifiers & modifier.bit != 0, height: 26))
                            .help(modifier.name)
                    }
                }
                ForEach(AMG65HIDKeys.groups) { group in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(AMG65Names.name(group.name)).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.textTertiary)
                        WrapLayout(spacing: 4, lineSpacing: 4) {
                            ForEach(group.keys) { entry in
                                let action = AMG65KeyAction.key(modifiers: modifiers, code: entry.code)
                                Button(AMG65Names.name(entry.name)) { if let key { assign(action, to: key) } }
                                    .buttonStyle(PillButtonStyle(isOn: current == action, height: 24))
                            }
                        }
                    }
                }
            case .media:
                WrapLayout(spacing: 4, lineSpacing: 4) {
                    ForEach(AMG65MediaKeys.all) { entry in
                        Button(AMG65Names.name(entry.name)) { if let key { assign(.media(entry.usage), to: key) } }
                            .buttonStyle(PillButtonStyle(isOn: current == .media(entry.usage), height: 26))
                    }
                }
            case .mouse:
                WrapLayout(spacing: 4, lineSpacing: 4) {
                    ForEach(AMG65MouseActions.buttons) { button in
                        Button(AMG65Names.name(button.name)) { if let key { assign(.mouseButton(button.mask), to: key) } }
                            .buttonStyle(PillButtonStyle(isOn: current == .mouseButton(button.mask), height: 26))
                    }
                    ForEach([true, false], id: \.self) { up in
                        Button(KeyActionText.title(.wheel(up: up))) { if let key { assign(.wheel(up: up), to: key) } }
                            .buttonStyle(PillButtonStyle(isOn: current == .wheel(up: up), height: 26))
                    }
                }
            }
            if category != .key {
                Text(L("Medya ve fare atamaları AMG65 Studio'dan alındı ama bu klavyede henüz denenmedi."))
                    .font(.system(size: 11)).foregroundStyle(Theme.textTertiary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .disabled(key == nil)
        .opacity(key == nil ? 0.6 : 1)
    }

    // MARK: Changes

    private func select(_ slot: Int, map: [Int: AMG65KeyAction]) {
        selectedSlot = slot
        switch map[slot] {
        case let .key(mods, _)?:
            modifiers = mods
            category = .key
        case .media?: category = .media
        case .mouseButton?, .wheel?: category = .mouse
        case nil:
            modifiers = 0
        }
    }

    /// The factory action (plain key, no modifiers) is stored as "no remap".
    private func assign(_ action: AMG65KeyAction?, to key: AMG65Key) {
        let value = action == .key(modifiers: 0, code: key.code) ? nil : action
        model.updatePreferences(for: device) { $0.keyMap[key.slot] = value }
    }

    private func toggle(_ modifier: AMG65Modifier, key: AMG65Key?, current: AMG65KeyAction?) {
        modifiers ^= modifier.bit
        if let key, case let .key(_, code)? = current { assign(.key(modifiers: modifiers, code: code), to: key) }
    }
}

/// How an action reads in the UI.
enum KeyActionText {
    static func title(_ action: AMG65KeyAction) -> String {
        switch action {
        case let .key(mods, code):
            let symbols = AMG65Modifier.allCases.filter { mods & $0.bit != 0 }.map(\.symbol).joined()
            return symbols + (AMG65HIDKeys.name(code).map(AMG65Names.name) ?? String(format: "0x%02X", code))
        case let .media(usage):
            return AMG65MediaKeys.all.first { $0.usage == usage }.map { AMG65Names.name($0.name) } ?? String(format: "0x%04X", usage)
        case let .mouseButton(mask):
            return AMG65MouseActions.buttons.first { $0.mask == mask }.map { AMG65Names.name($0.name) } ?? String(format: "0x%02X", mask)
        case let .wheel(up):
            return up ? L("Tekerlek yukarı") : L("Tekerlek aşağı")
        }
    }
}

/// Translations for the English source names in `AMG65Layout`; names not listed (letters, F-keys, symbols…) stay as is.
enum AMG65Names {
    private static let keys: [String: String] = [
        "Letters": LK("Harfler"), "Numbers": LK("Rakamlar"), "Function": LK("İşlev tuşları"), "Editing": LK("Düzenleme"),
        "Navigation": LK("Gezinme"), "Symbols": LK("Simgeler"), "Modifiers": LK("Değiştirici tuşlar"), "Other": LK("Diğer"),
        "Space": LK("Boşluk"),
        "Left Ctrl": LK("Sol Ctrl"), "Left Shift": LK("Sol Shift"), "Left Alt/⌥": LK("Sol Alt/⌥"), "Left Win/⌘": LK("Sol Win/⌘"),
        "Right Ctrl": LK("Sağ Ctrl"), "Right Shift": LK("Sağ Shift"), "Right Alt/⌥": LK("Sağ Alt/⌥"), "Right Win/⌘": LK("Sağ Win/⌘"),
        "Play / Pause": LK("Oynat / Duraklat"), "Next track": LK("Sonraki parça"), "Previous track": LK("Önceki parça"),
        "Stop": LK("Durdur"), "Volume up": LK("Sesi aç"), "Volume down": LK("Sesi kıs"), "Mute": LK("Sessiz"),
        "Left click": LK("Sol tık"), "Right click": LK("Sağ tık"), "Middle click": LK("Orta tık"), "Back": LK("Geri"), "Forward": LK("İleri"),
    ]

    static func name(_ english: String) -> String { keys[english].map { L($0) } ?? english }
}
