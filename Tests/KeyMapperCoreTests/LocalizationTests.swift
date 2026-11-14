import Foundation
import Testing
@testable import KeyMapperCore

/// Every string marked with L("…") / LK("…") in the sources must be translated into every
/// language, with the same placeholders.
@Suite struct LocalizationTests {
    static let sourceKeys: [String: String] = {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let sources = root.appendingPathComponent("Sources")
        let pattern = try! NSRegularExpression(pattern: #"(?<![A-Za-z0-9_.])LK?\("((?:[^"\\]|\\.)*)""#)
        var keys: [String: String] = [:]
        let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" && !$0.path.contains("/Localization/") } ?? []
        for file in files {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let range = Range(match.range(at: 1), in: text) else { continue }
                keys[unescape(String(text[range]))] = file.lastPathComponent
            }
        }
        return keys
    }()

    static func unescape(_ literal: String) -> String {
        var out = ""
        var iterator = literal.makeIterator()
        while let ch = iterator.next() {
            guard ch == "\\", let next = iterator.next() else { out.append(ch); continue }
            switch next {
            case "n": out.append("\n")
            case "t": out.append("\t")
            default: out.append(next)
            }
        }
        return out
    }

    static func specifiers(_ text: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: #"%(?:\d+\$)?[-+ 0#]*\d*(?:\.\d+)?(?:ll|l|h)?[@dDiuUxXoOfeEgGcCsSp%]"#)
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap { Range($0.range, in: text).map { String(text[$0]) } }
            .map { $0.replacingOccurrences(of: #"%\d+\$"#, with: "%", options: .regularExpression) }
            .sorted()
    }

    @Test func sourcesUseTranslatableStrings() {
        #expect(Self.sourceKeys.count > 400)
    }

    @Test(arguments: AppLanguage.allCases.filter { $0 != .turkish })
    func everyKeyIsTranslated(language: AppLanguage) throws {
        let table = try #require(L10n.table(for: language))
        var missing: [String] = []
        var mismatched: [String] = []
        for key in Self.sourceKeys.keys.sorted() {
            guard let value = table[key], !value.trimmingCharacters(in: .whitespaces).isEmpty else {
                missing.append(key)
                continue
            }
            if Self.specifiers(key) != Self.specifiers(value) { mismatched.append("\(key) → \(value)") }
        }
        #expect(missing.isEmpty, "\(language.rawValue) missing \(missing.count): \(missing.prefix(10))")
        #expect(mismatched.isEmpty, "\(language.rawValue) placeholders: \(mismatched.prefix(10))")
    }

    @Test func preferredLanguageMatching() {
        #expect(AppLanguage.preferred(from: ["tr-TR"]) == .turkish)
        #expect(AppLanguage.preferred(from: ["en-GB"]) == .english)
        #expect(AppLanguage.preferred(from: ["es-MX"]) == .spanish)
        #expect(AppLanguage.preferred(from: ["ja-JP"]) == .japanese)
        #expect(AppLanguage.preferred(from: ["zh-Hant-TW"]) == .chinese)
        #expect(AppLanguage.preferred(from: ["de-DE", "ja"]) == .japanese)
        #expect(AppLanguage.preferred(from: ["de-DE"]) == .english)
    }

    @Test func turkishIsTheSourceAndUnknownKeysFallBack() {
        #expect(L10n.string("Kaydet", language: .turkish) == "Kaydet")
        #expect(L10n.string("bu anahtar yok", language: .japanese) == "bu anahtar yok")
    }

    @Test func positionalPlaceholdersFormat() {
        #expect(String(format: "%2$@ – %1$@", "a", "b") == "b – a")
    }
}
