import AppKit
import KeyMapperCore

/// Letter keys: a key on a programmable keyboard sends a reserved code and KeyMapper types
/// the letter (ğ, ş, ñ…) the Mac's input source has no key for.
extension AppModel {
    func setUpLetters() {
        letterKeys = LetterKeyStore.shared.load()
        refreshLetterTap()
    }

    /// Starts the tap when letters exist and Accessibility is granted; stops it otherwise.
    func refreshLetterTap() {
        letterTap.update(letters: letterKeys, enabled: ActionPerformer.isAccessibilityTrusted)
    }

    /// Makes the key at `slot` type `text` (Shift or Caps Lock types its capital); returns the keycode written.
    @discardableResult
    func assignLetter(_ text: String, device: KeyboardDevice, layer: Int, slot: KeySlot) async -> UInt16? {
        guard let lower = LetterKey.sanitized(text) else {
            errorMessage = L("Bir harf yazın (en fazla 8 karakter).")
            return nil
        }
        guard device.capability != .osRemap, let keycodes = states[device.id]?.keycodes else {
            errorMessage = L("Harf tuşları yalnızca VIA ve Vial klavyelerde kullanılabilir.")
            return nil
        }
        guard let index = LetterKeys.slotIndex(for: lower, in: letterKeys) else {
            errorMessage = L("Tüm harf yerleri (%@) dolu.", "\(LetterKeys.slots.count)")
            return nil
        }
        guard let code = LetterKeys.code(for: LetterKeys.slots[index], keycodes: keycodes) else { return nil }
        let letter = LetterKey(slot: index, lower: lower)
        letterKeys.removeAll { $0.slot == index }
        letterKeys.append(letter)
        letterKeys.sort { $0.slot < $1.slot }
        do { try LetterKeyStore.shared.save(letterKeys) } catch { errorMessage = error.localizedDescription }
        await assign(code, device: device, layer: layer, slot: slot)
        // A failed write has already reported its error.
        guard states[device.id]?.keymap.keycode(layer: layer, slot: slot) == code else { return nil }
        accessibilityTrusted = ActionPerformer.isAccessibilityTrusted
        if !accessibilityTrusted { ActionPerformer.requestAccessibility() }
        refreshLetterTap()
        notice = L("Harf: %@ · Shift ile %@", letter.lower, letter.upper)
        return code
    }

    /// Frees a letter's slot. Keys still sending its code then type nothing until a letter is assigned again.
    func removeLetter(_ letter: LetterKey) {
        letterKeys.removeAll { $0.slot == letter.slot }
        do { try LetterKeyStore.shared.save(letterKeys) } catch { errorMessage = error.localizedDescription }
        refreshLetterTap()
        notice = L("Harf kaldırıldı: %@", letter.legend)
    }

    func letterKey(forCode code: UInt16, keycodes: KeycodeSet) -> LetterKey? {
        LetterKeys.letter(forCode: code, keycodes: keycodes, in: letterKeys)
    }

    /// Hover and inspector text for a key that types a letter.
    func letterDetail(_ letter: LetterKey) -> String {
        L("KeyMapper yazar: %@, Shift ya da Caps Lock ile %@. Erişilebilirlik izni gerekir.", letter.lower, letter.upper)
    }

    /// Keycap for a key that types a letter.
    func letterCap(code: UInt16, keycodes: KeycodeSet) -> KeyCapModel? {
        guard let letter = letterKey(forCode: code, keycodes: keycodes) else { return nil }
        return KeyCapModel(label: KeyLabel(main: letter.legend), kind: .alpha, subColor: Theme.accent,
                           tooltip: "\(L("Harf: %@", letter.legend))\n\(letterDetail(letter))")
    }
}
