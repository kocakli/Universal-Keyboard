import Foundation

public enum RemapError: LocalizedError {
    case hidutilFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .hidutilFailed(output): return L("hidutil başarısız oldu: %@", output)
        }
    }
}

/// Per-device key remapping done by macOS (`hidutil`, UserKeyMapping).
///
/// Works for any keyboard (Logitech, Razer, Apple, ...) without firmware support.
/// macOS forgets these mappings when the keyboard reconnects, so the app re-applies them.
public enum HIDUtilRemapper {
    static let keyboardPage: UInt64 = 0x7_0000_0000
    static let hidutil = URL(fileURLWithPath: "/usr/bin/hidutil")

    public static func apply(_ remaps: [KeyRemap], vendorID: Int, productID: Int) throws {
        let mappings = remaps.map {
            "{\"HIDKeyboardModifierMappingSrc\":\(keyboardPage | UInt64($0.from)),\"HIDKeyboardModifierMappingDst\":\(keyboardPage | UInt64($0.to))}"
        }
        let value = "{\"UserKeyMapping\":[\(mappings.joined(separator: ","))]}"
        try run(["property", "--matching", matching(vendorID, productID), "--set", value])
    }

    public static func clear(vendorID: Int, productID: Int) throws {
        try apply([], vendorID: vendorID, productID: productID)
    }

    /// Mappings currently active for the keyboard.
    public static func current(vendorID: Int, productID: Int) -> [KeyRemap] {
        guard let output = try? run(["property", "--matching", matching(vendorID, productID), "--get", "UserKeyMapping"]) else { return [] }
        return parse(output)
    }

    static func parse(_ output: String) -> [KeyRemap] {
        // Output is a property-list style dump; pull out Src/Dst pairs in order.
        var sources: [UInt64] = []
        var destinations: [UInt64] = []
        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let equals = trimmed.firstIndex(of: "=") else { continue }
            let key = trimmed[..<equals].trimmingCharacters(in: .whitespaces)
            let rawValue = trimmed[trimmed.index(after: equals)...].trimmingCharacters(in: CharacterSet(charactersIn: " ;"))
            guard let number = UInt64(rawValue) ?? UInt64(rawValue.replacingOccurrences(of: "0x", with: ""), radix: 16) else { continue }
            if key == "HIDKeyboardModifierMappingSrc" { sources.append(number) }
            if key == "HIDKeyboardModifierMappingDst" { destinations.append(number) }
        }
        // hidutil prints one block per matching service; keep each pair once.
        var seen = Set<KeyRemap>()
        return zip(sources, destinations).compactMap { src, dst in
            guard src & keyboardPage == keyboardPage, dst & keyboardPage == keyboardPage else { return nil }
            let remap = KeyRemap(from: UInt16(src & 0xFFFF), to: UInt16(dst & 0xFFFF))
            return seen.insert(remap).inserted ? remap : nil
        }
    }

    private static func matching(_ vendorID: Int, _ productID: Int) -> String {
        "{\"VendorID\":\(vendorID),\"ProductID\":\(productID)}"
    }

    @discardableResult
    private static func run(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = hidutil
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else { throw RemapError.hidutilFailed(output.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return output
    }

    /// Ready made remaps that are popular on macOS.
    public static let presets: [(name: String, remaps: [KeyRemap])] = [
        (LK("Caps Lock → Escape"), [KeyRemap(from: 0x39, to: 0x29)]),
        (LK("Caps Lock → Control"), [KeyRemap(from: 0x39, to: 0xE0)]),
        (LK("Windows klavye: Alt ⇄ Win (Mac düzeni)"), [
            KeyRemap(from: 0xE2, to: 0xE3), KeyRemap(from: 0xE3, to: 0xE2),
            KeyRemap(from: 0xE6, to: 0xE7), KeyRemap(from: 0xE7, to: 0xE6),
        ]),
        (LK("ISO § / ` düzelt (§ ⇄ `)"), [KeyRemap(from: 0x64, to: 0x35), KeyRemap(from: 0x35, to: 0x64)]),
    ]
}
