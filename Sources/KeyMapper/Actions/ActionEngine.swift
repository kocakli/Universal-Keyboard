import AppKit
import ApplicationServices
import Carbon.HIToolbox
import KeyMapperCore

/// Global hot keys via Carbon `RegisterEventHotKey`: no Accessibility or Input Monitoring
/// permission is needed, and the trigger key is consumed so the frontmost app never sees it.
final class HotKeyCenter {
    var onPress: ((UUID) -> Void)?

    private var references: [EventHotKeyRef] = []
    private var bindingIDs: [UInt32: UUID] = [:]
    private var handler: EventHandlerRef?
    private static let signature: OSType = 0x4B4D_4150 // "KMAP"

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard status == noErr else { return status }
            Unmanaged<HotKeyCenter>.fromOpaque(context).takeUnretainedValue().fire(hotKeyID.id)
            return noErr
        }, 1, &spec, context, &handler)
    }

    deinit {
        unregisterAll()
        if let handler { RemoveEventHandler(handler) }
    }

    /// Registers every enabled binding; returns the ids whose key combination was refused
    /// (usually because another app already owns it).
    @discardableResult
    func register(_ bindings: [ActionBinding]) -> [UUID] {
        unregisterAll()
        var refused: [UUID] = []
        for (index, binding) in bindings.enumerated() where binding.isEnabled {
            let id = EventHotKeyID(signature: Self.signature, id: UInt32(index + 1))
            var reference: EventHotKeyRef?
            let status = RegisterEventHotKey(UInt32(binding.trigger.keyCode), Self.carbonModifiers(binding.trigger.modifiers),
                                             id, GetEventDispatcherTarget(), OptionBits(kEventHotKeyExclusive), &reference)
            if status == noErr, let reference {
                references.append(reference)
                bindingIDs[id.id] = binding.id
            } else {
                refused.append(binding.id)
            }
        }
        return refused
    }

    func unregisterAll() {
        references.forEach { UnregisterEventHotKey($0) }
        references.removeAll()
        bindingIDs.removeAll()
    }

    private func fire(_ id: UInt32) {
        guard let bindingID = bindingIDs[id] else { return }
        onPress?(bindingID)
    }

    static func carbonModifiers(_ modifiers: KeyCombo.Modifiers) -> UInt32 {
        var flags: UInt32 = 0
        if modifiers.contains(.command) { flags |= UInt32(cmdKey) }
        if modifiers.contains(.option) { flags |= UInt32(optionKey) }
        if modifiers.contains(.control) { flags |= UInt32(controlKey) }
        if modifiers.contains(.shift) { flags |= UInt32(shiftKey) }
        return flags
    }
}

enum ActionError: LocalizedError {
    case appNotFound(String)
    case badURL(String)
    case needsAccessibility

    var errorDescription: String? {
        switch self {
        case let .appNotFound(name): return "\(name) bulunamadı."
        case let .badURL(text): return "Geçersiz adres: \(text)"
        case .needsAccessibility: return "Tuş göndermek için KeyMapper'a Erişilebilirlik izni verin (Sistem Ayarları › Gizlilik ve Güvenlik › Erişilebilirlik)."
        }
    }
}

/// Runs a `KeyAction`.
@MainActor
enum ActionPerformer {
    static var isAccessibilityTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that adds KeyMapper to the Accessibility list.
    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func perform(_ action: KeyAction) throws {
        switch action {
        case let .openApp(bundleID, name):
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { throw ActionError.appNotFound(name) }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        case let .openURL(text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let url: URL?
            if trimmed.hasPrefix("/") || trimmed.hasPrefix("~") {
                url = URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath)
            } else {
                url = URL(string: trimmed).flatMap { $0.scheme == nil ? URL(string: "https://" + trimmed) : $0 }
            }
            guard let url else { throw ActionError.badURL(text) }
            NSWorkspace.shared.open(url)
        case let .runShortcut(name):
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            process.arguments = ["run", name]
            try process.run()
        case let .keystroke(combo):
            guard isAccessibilityTrusted else { requestAccessibility(); throw ActionError.needsAccessibility }
            post(combo)
        case let .typeText(text):
            guard isAccessibilityTrusted else { requestAccessibility(); throw ActionError.needsAccessibility }
            type(text)
        }
    }

    private static func post(_ combo: KeyCombo) {
        let source = CGEventSource(stateID: .hidSystemState)
        var flags: CGEventFlags = []
        if combo.modifiers.contains(.command) { flags.insert(.maskCommand) }
        if combo.modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if combo.modifiers.contains(.control) { flags.insert(.maskControl) }
        if combo.modifiers.contains(.shift) { flags.insert(.maskShift) }
        for isDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(combo.keyCode), keyDown: isDown)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
    }

    private static func type(_ text: String) {
        let source = CGEventSource(stateID: .hidSystemState)
        let units = Array(text.utf16)
        var index = 0
        // CGEvent carries at most 20 UTF-16 units per event.
        while index < units.count {
            let chunk = Array(units[index..<min(index + 20, units.count)])
            for isDown in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: isDown)
                event?.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
                event?.post(tap: .cghidEventTap)
            }
            index += 20
        }
    }

    /// Names of the user's Shortcuts.app shortcuts.
    nonisolated static func shortcutNames() async -> [String] {
        await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            process.arguments = ["list"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            guard (try? process.run()) != nil else { return [] }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(decoding: data, as: UTF8.self)
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }.value
    }
}

/// Apps the user is likely to pick: running regular apps, sorted by name.
struct AppChoice: Identifiable, Hashable {
    let bundleID: String
    let name: String
    var id: String { bundleID }

    @MainActor
    static var running: [AppChoice] {
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> AppChoice? in
                guard let id = app.bundleIdentifier, id != Bundle.main.bundleIdentifier else { return nil }
                return AppChoice(bundleID: id, name: app.localizedName ?? id)
            }
        return Array(Set(apps)).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Lets the user pick any .app from /Applications.
    @MainActor
    static func choose() -> AppChoice? {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.title = "Uygulama seç"
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url, let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return nil }
        let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        return AppChoice(bundleID: id, name: name)
    }

    @MainActor
    static func icon(for bundleID: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
