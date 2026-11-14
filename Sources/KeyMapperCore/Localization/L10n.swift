import Foundation

/// Languages KeyMapper ships. Turkish is the source language of every string.
public enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case turkish = "tr"
    case english = "en"
    case spanish = "es"
    case japanese = "ja"
    case chinese = "zh-Hans"

    public var id: String { rawValue }

    /// The language's name in itself, for the language picker.
    public var nativeName: String {
        switch self {
        case .turkish: return "Türkçe"
        case .english: return "English"
        case .spanish: return "Español"
        case .japanese: return "日本語"
        case .chinese: return "简体中文"
        }
    }

    public var locale: Locale { Locale(identifier: rawValue) }

    /// Language tag vendors use for release notes (Keychron Launcher).
    public var releaseNotesTag: String {
        switch self {
        case .turkish: return "tr-TR"
        case .english: return "en-US"
        case .spanish: return "es-ES"
        case .japanese: return "ja-JP"
        case .chinese: return "zh-CN"
        }
    }

    /// First supported language in the user's preference list; English when none matches.
    public static func preferred(from languages: [String] = Locale.preferredLanguages) -> AppLanguage {
        for tag in languages {
            let code = tag.lowercased()
            if code.hasPrefix("zh") { return .chinese }
            if let match = allCases.first(where: { code == $0.rawValue || code.hasPrefix($0.rawValue + "-") }) { return match }
        }
        return .english
    }
}

/// Lightweight localization: translations live in Swift dictionaries keyed by the Turkish source
/// string, so they work the same in the app bundle, `swift run` and the `kmctl` command line tool.
public enum L10n {
    public static let appIdentifier = "dev.keymapper.KeyMapper"
    static let storageKey = "appLanguage"

    /// Language used by `L(...)`. Tests may set it directly; the app uses `setOverride`.
    public static var current: AppLanguage = resolve()

    /// The language the user picked in KeyMapper (nil = follow macOS).
    public static var override: AppLanguage? {
        defaults.string(forKey: storageKey).flatMap(AppLanguage.init(rawValue:))
    }

    public static func setOverride(_ language: AppLanguage?) {
        if let language { defaults.set(language.rawValue, forKey: storageKey) } else { defaults.removeObject(forKey: storageKey) }
        current = resolve()
    }

    static func resolve() -> AppLanguage {
        if let forced = ProcessInfo.processInfo.environment["KEYMAPPER_LANG"].flatMap(AppLanguage.init(rawValue:)) { return forced }
        return override ?? AppLanguage.preferred()
    }

    /// The app reads its own defaults; kmctl and `swift run` read the app's domain.
    static var defaults: UserDefaults {
        if Bundle.main.bundleIdentifier == appIdentifier { return .standard }
        return UserDefaults(suiteName: appIdentifier) ?? .standard
    }

    static func table(for language: AppLanguage) -> [String: String]? {
        switch language {
        case .turkish: return nil
        case .english: return en
        case .spanish: return es
        case .japanese: return ja
        case .chinese: return zhHans
        }
    }

    /// Translation of `key`, falling back to English and then to the Turkish source.
    public static func string(_ key: String, language: AppLanguage = current) -> String {
        guard language != .turkish else { return key }
        return table(for: language)?[key] ?? en[key] ?? key
    }
}

/// Translates a Turkish source string into the current language.
public func L(_ key: String) -> String { L10n.string(key) }

/// Translates a format string (placeholders are `%@`), then fills in the arguments.
public func L(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: L10n.string(key), locale: L10n.current.locale, arguments: arguments)
}

/// Marks a string stored in a static table for translation; call `L(...)` where it is shown.
@inline(__always) public func LK(_ key: String) -> String { key }
