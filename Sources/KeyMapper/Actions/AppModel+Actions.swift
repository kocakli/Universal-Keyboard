import AppKit
import KeyMapperCore

/// Action bindings: trigger keys (F13–F20) that open apps, run shortcuts or send
/// keystrokes, with per-app overrides (like Logitech Options+ app-specific settings).
extension AppModel {
    func setUpActions() {
        bindings = ActionStore.shared.load()
        hotKeys.onPress = { [weak self] id in
            MainActor.assumeIsolated { self?.fire(id) }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.accessibilityTrusted = ActionPerformer.isAccessibilityTrusted }
        }
        registerHotKeys()
    }

    func registerHotKeys() {
        if actionsEnabled {
            refusedBindings = Set(hotKeys.register(bindings))
        } else {
            hotKeys.unregisterAll()
            refusedBindings = []
        }
    }

    func setActionsEnabled(_ enabled: Bool) {
        actionsEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "actionsEnabled")
        registerHotKeys()
    }

    private func fire(_ id: UUID) {
        guard let binding = bindings.first(where: { $0.id == id }) else { return }
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard let action = binding.action(frontmostBundleID: frontmost) else { return }
        do {
            try ActionPerformer.perform(action)
        } catch {
            errorMessage = "\(binding.name): \(error.localizedDescription)"
            accessibilityTrusted = ActionPerformer.isAccessibilityTrusted
        }
    }

    // MARK: Editing

    @discardableResult
    func addBinding() -> ActionBinding? {
        guard let trigger = ActionStore.nextFreeTrigger(in: bindings) else {
            errorMessage = "Tüm tetik tuşları (F13–F20) kullanımda."
            return nil
        }
        let binding = ActionBinding(name: "Aksiyon \(bindings.count + 1)", trigger: trigger.combo)
        bindings.append(binding)
        persistBindings()
        return binding
    }

    func update(_ binding: ActionBinding) {
        guard let index = bindings.firstIndex(where: { $0.id == binding.id }) else { return }
        bindings[index] = binding
        persistBindings()
    }

    func delete(_ binding: ActionBinding) {
        bindings.removeAll { $0.id == binding.id }
        persistBindings()
    }

    private func persistBindings() {
        do { try ActionStore.shared.save(bindings) } catch { errorMessage = error.localizedDescription }
        registerHotKeys()
        accessibilityTrusted = ActionPerformer.isAccessibilityTrusted
    }

    /// Trigger usage (KC_F13 …) → binding name, to label keys that fire an action.
    var actionNamesByUsage: [UInt16: String] {
        var names: [UInt16: String] = [:]
        for binding in bindings where binding.trigger.modifiers.isEmpty {
            if let trigger = TriggerKey.forKeyCode(binding.trigger.keyCode) { names[trigger.usage] = binding.name }
        }
        return names
    }

    var needsAccessibility: Bool { bindings.contains { $0.isEnabled && $0.needsAccessibility } }

    func openActions() {
        showingActions = true
    }
}
