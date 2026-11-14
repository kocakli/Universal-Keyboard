import Foundation

/// A key combination as macOS sees it (virtual key code + modifiers).
public struct KeyCombo: Codable, Hashable, Sendable {
    public struct Modifiers: OptionSet, Codable, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let command = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let control = Modifiers(rawValue: 1 << 2)
        public static let shift = Modifiers(rawValue: 1 << 3)

        public var symbols: String {
            var out = ""
            if contains(.control) { out += "⌃" }
            if contains(.option) { out += "⌥" }
            if contains(.shift) { out += "⇧" }
            if contains(.command) { out += "⌘" }
            return out
        }
    }

    /// macOS virtual key code (kVK_*).
    public var keyCode: UInt16
    public var modifiers: Modifiers
    /// Legend of the key itself, captured when the combo was recorded (e.g. "T", "F13", "←").
    public var key: String

    public init(keyCode: UInt16, modifiers: Modifiers = [], key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }

    public var display: String { modifiers.symbols + key }
}

/// What a trigger key does.
public enum KeyAction: Codable, Hashable, Sendable {
    /// Launch or bring an app to the front.
    case openApp(bundleID: String, name: String)
    /// Open a web address, file or folder (`https://…`, `file://…`, `zoommtg://…`).
    case openURL(String)
    /// Run a Shortcuts.app shortcut by name.
    case runShortcut(String)
    /// Send a key combination to the frontmost app (needs Accessibility).
    case keystroke(KeyCombo)
    /// Type a piece of text (needs Accessibility).
    case typeText(String)

    public var kind: Kind {
        switch self {
        case .openApp: return .openApp
        case .openURL: return .openURL
        case .runShortcut: return .runShortcut
        case .keystroke: return .keystroke
        case .typeText: return .typeText
        }
    }

    public enum Kind: String, CaseIterable, Codable, Sendable, Identifiable {
        case openApp, openURL, runShortcut, keystroke, typeText

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .openApp: return "Uygulama aç"
            case .openURL: return "Adres / dosya aç"
            case .runShortcut: return "Kestirme çalıştır"
            case .keystroke: return "Tuş kombinasyonu gönder"
            case .typeText: return "Metin yaz"
            }
        }

        public var symbol: String {
            switch self {
            case .openApp: return "app.badge"
            case .openURL: return "link"
            case .runShortcut: return "square.stack.3d.up"
            case .keystroke: return "command"
            case .typeText: return "text.cursor"
            }
        }

        /// Synthetic keyboard events need the Accessibility permission.
        public var needsAccessibility: Bool { self == .keystroke || self == .typeText }
    }

    public var summary: String {
        switch self {
        case let .openApp(_, name): return "\(name) aç"
        case let .openURL(url): return url
        case let .runShortcut(name): return "Kestirme: \(name)"
        case let .keystroke(combo): return combo.display
        case let .typeText(text): return "“\(text.count > 24 ? String(text.prefix(24)) + "…" : text)”"
        }
    }

    public var needsAccessibility: Bool { kind.needsAccessibility }
}

/// An action that overrides the default one while a given app is frontmost.
public struct AppRule: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var bundleID: String
    public var appName: String
    public var action: KeyAction

    public init(id: UUID = UUID(), bundleID: String, appName: String, action: KeyAction) {
        self.id = id
        self.bundleID = bundleID
        self.appName = appName
        self.action = action
    }
}

/// One trigger key and what it does, globally and per app.
public struct ActionBinding: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var trigger: KeyCombo
    public var isEnabled: Bool
    /// Used when no app rule matches; nil = do nothing outside the listed apps.
    public var defaultAction: KeyAction?
    public var appRules: [AppRule]

    public init(id: UUID = UUID(), name: String, trigger: KeyCombo, isEnabled: Bool = true,
                defaultAction: KeyAction? = nil, appRules: [AppRule] = []) {
        self.id = id
        self.name = name
        self.trigger = trigger
        self.isEnabled = isEnabled
        self.defaultAction = defaultAction
        self.appRules = appRules
    }

    /// The action to run when the trigger fires while `frontmostBundleID` is in front.
    public func action(frontmostBundleID: String?) -> KeyAction? {
        if let frontmostBundleID, let rule = appRules.first(where: { $0.bundleID == frontmostBundleID }) {
            return rule.action
        }
        return defaultAction
    }

    public var needsAccessibility: Bool {
        (defaultAction?.needsAccessibility ?? false) || appRules.contains { $0.action.needsAccessibility }
    }
}

/// Keys reserved as action triggers. Keyboards send them (firmware keycode or macOS remap);
/// KeyMapper catches them as global hot keys, so no other app sees them.
public struct TriggerKey: Hashable, Sendable, Identifiable {
    public let name: String
    /// macOS virtual key code (kVK_F13 …).
    public let keyCode: UInt16
    /// HID usage / QMK basic keycode (KC_F13 = 0x68 …).
    public let usage: UInt16

    public var id: UInt16 { keyCode }
    public var combo: KeyCombo { KeyCombo(keyCode: keyCode, key: name) }

    /// F16–F20 have no default macOS meaning; F13 is next (PC keyboards' Print Screen sends it);
    /// F14/F15 come last because macOS uses them for display brightness. F21–F24 have no
    /// macOS virtual key codes, so apps never see them.
    public static let all: [TriggerKey] = [
        TriggerKey(name: "F16", keyCode: 0x6A, usage: 0x6B),
        TriggerKey(name: "F17", keyCode: 0x40, usage: 0x6C),
        TriggerKey(name: "F18", keyCode: 0x4F, usage: 0x6D),
        TriggerKey(name: "F19", keyCode: 0x50, usage: 0x6E),
        TriggerKey(name: "F20", keyCode: 0x5A, usage: 0x6F),
        TriggerKey(name: "F13", keyCode: 0x69, usage: 0x68),
        TriggerKey(name: "F14", keyCode: 0x6B, usage: 0x69),
        TriggerKey(name: "F15", keyCode: 0x71, usage: 0x6A),
    ]

    public static func forUsage(_ usage: UInt16) -> TriggerKey? { all.first { $0.usage == usage } }
    public static func forKeyCode(_ keyCode: UInt16) -> TriggerKey? { all.first { $0.keyCode == keyCode } }
}
