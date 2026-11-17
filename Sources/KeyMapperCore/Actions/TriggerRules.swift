import Foundation

/// What can start an action: a reserved F-key a keyboard sends (F13–F20), or a shortcut such as
/// ⌥0 pressed on any keyboard. KeyMapper takes the key combination for itself, so the frontmost
/// app no longer sees it.
public enum TriggerRules {
    /// Why `combo` can't start an action, or nil when it can. `others` are the other actions' triggers,
    /// `sent` the key combinations actions send (see `sentTrigger`).
    public static func refusal(for combo: KeyCombo, others: [KeyCombo], sent: [KeyCombo] = []) -> String? {
        if others.contains(where: { $0.hasSameKeys(as: combo) }) {
            return L("%@ başka bir aksiyonun tetiği.", combo.display)
        }
        if sent.contains(where: { $0.hasSameKeys(as: combo) }) {
            return L("%@ bir aksiyonun gönderdiği kısayol; tetik yapılamaz.", combo.display)
        }
        if combo.isReservedKey { return nil }
        if combo.modifiers.isDisjoint(with: [.command, .option, .control]) {
            return L("Kısayolda ⌘, ⌥ ya da ⌃ olmalı; yoksa o tuş artık yazmazdı.")
        }
        if isLetterSlot(combo) {
            return L("%@ harf tuşlarına ayrılmış.", combo.display)
        }
        return nil
    }

    /// The trigger a keystroke action would send, if any. KeyMapper's own key events reach its hot keys,
    /// so sending a trigger would start that action again (with itself, endlessly).
    public static func sentTrigger(_ action: KeyAction, triggers: [KeyCombo]) -> KeyCombo? {
        guard case let .keystroke(combo) = action, triggers.contains(where: { $0.hasSameKeys(as: combo) }) else { return nil }
        return combo
    }

    /// Letter keys use ⌃⌥⌘ / ⌃⌥ + F-keys (Shift only picks the capital), so those stay theirs.
    static func isLetterSlot(_ combo: KeyCombo) -> Bool {
        var part: LetterKeyFilter.Modifiers = []
        if combo.modifiers.contains(.control) { part.insert(.control) }
        if combo.modifiers.contains(.option) { part.insert(.option) }
        if combo.modifiers.contains(.command) { part.insert(.command) }
        return LetterKeys.slots.contains { $0.keyCode == combo.keyCode && $0.modifiers == part }
    }
}

extension ActionBinding {
    /// Key combinations this action sends (default action and app rules).
    public var sentKeystrokes: [KeyCombo] {
        ([defaultAction].compactMap { $0 } + appRules.map(\.action)).compactMap { action in
            if case let .keystroke(combo) = action { return combo }
            return nil
        }
    }
}

extension KeyCombo {
    /// One of the reserved F-keys (F13–F20) with no modifiers: what keyboards send for actions.
    public var isReservedKey: Bool { modifiers.isEmpty && TriggerKey.forKeyCode(keyCode) != nil }

    /// Same key and modifiers; the recorded legend may differ (it follows the input source).
    public func hasSameKeys(as other: KeyCombo) -> Bool {
        keyCode == other.keyCode && modifiers == other.modifiers
    }
}
