import AppKit
import KeyMapperCore

/// Action bindings: trigger keys (F13–F20) or shortcuts (⌥0 …) that open apps, run shortcuts or
/// send keystrokes, with per-app overrides (like Logitech Options+ app-specific settings).
extension AppModel {
    func setUpActions() {
        bindings = ActionStore.shared.load()
        hotKeys.onPress = { [weak self] id in
            MainActor.assumeIsolated { self?.fire(id) }
        }
        hotKeys.onRelease = { [weak self] _ in
            MainActor.assumeIsolated { self?.stopActionRepeat() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.accessibilityTrusted = ActionPerformer.isAccessibilityTrusted
                // Accessibility may have been granted in System Settings meanwhile.
                self?.refreshLetterTap()
            }
        }
        registerHotKeys()
        setUpLetters()
    }

    func registerHotKeys() {
        stopActionRepeat()
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

    /// Hot keys are off while a shortcut is being recorded, so an existing action doesn't fire instead.
    func pauseHotKeys() {
        stopActionRepeat()
        hotKeys.unregisterAll()
    }

    private func fire(_ id: UUID) {
        stopActionRepeat()
        guard let binding = bindings.first(where: { $0.id == id }) else { return }
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard let action = binding.action(frontmostBundleID: frontmost) else { return }
        if let combo = TriggerRules.sentTrigger(action, triggers: bindings.filter(\.isEnabled).map(\.trigger)) {
            errorMessage = L("%@: %@ bir aksiyonun tetiği olduğu için gönderilmedi.", binding.name, combo.display)
            return
        }
        do {
            try ActionPerformer.perform(action)
            if action.repeatsWhileHeld { startActionRepeat(action, trigger: binding.trigger) }
        } catch {
            errorMessage = "\(binding.name): \(error.localizedDescription)"
            accessibilityTrusted = ActionPerformer.isAccessibilityTrusted
        }
    }

    /// Hot keys fire once per press, so a held volume / brightness trigger is repeated here at the
    /// system key repeat rate until it is let go.
    private func startActionRepeat(_ action: KeyAction, trigger: KeyCombo) {
        // Also stop when the key or one of its modifiers is let go, or after a while, should a release be missed.
        let deadline = Date().addingTimeInterval(10)
        var modifiers: CGEventFlags = []
        if trigger.modifiers.contains(.command) { modifiers.insert(.maskCommand) }
        if trigger.modifiers.contains(.option) { modifiers.insert(.maskAlternate) }
        if trigger.modifiers.contains(.control) { modifiers.insert(.maskControl) }
        if trigger.modifiers.contains(.shift) { modifiers.insert(.maskShift) }
        let held = { CGEventSource.keyState(.hidSystemState, key: CGKeyCode(trigger.keyCode))
            && CGEventSource.flagsState(.hidSystemState).contains(modifiers) }
        actionRepeat = Timer.scheduledTimer(withTimeInterval: NSEvent.keyRepeatDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.actionRepeat = Timer.scheduledTimer(withTimeInterval: max(NSEvent.keyRepeatInterval, 0.03), repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        guard Date() < deadline, held() else {
                            self.stopActionRepeat()
                            return
                        }
                        try? ActionPerformer.perform(action)
                    }
                }
            }
        }
    }

    func stopActionRepeat() {
        actionRepeat?.invalidate()
        actionRepeat = nil
    }

    // MARK: Editing

    /// Adds an action on the next free F-key, or on `trigger` (a recorded shortcut such as ⌥0).
    @discardableResult
    func addBinding(trigger: KeyCombo? = nil) -> ActionBinding? {
        guard let trigger = trigger ?? ActionStore.nextFreeTrigger(in: bindings)?.combo else {
            errorMessage = L("Tüm tetik tuşları (F13–F20) kullanımda.")
            return nil
        }
        let binding = ActionBinding(name: L("Aksiyon %@", "\(bindings.count + 1)"), trigger: trigger)
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

    /// Trigger usage → what its action does, for hover help in the palette.
    var actionDetailsByUsage: [UInt16: String] {
        var details: [UInt16: String] = [:]
        for binding in bindings where binding.trigger.modifiers.isEmpty {
            guard let trigger = TriggerKey.forKeyCode(binding.trigger.keyCode) else { continue }
            var parts: [String] = []
            for rule in binding.appRules.prefix(2) { parts.append("\(rule.appName): \(rule.action.summary)") }
            if binding.appRules.count > 2 { parts.append(L("+%@ uygulama", "\(binding.appRules.count - 2)")) }
            if let action = binding.defaultAction {
                parts.append("\(binding.appRules.isEmpty ? L("Her yerde") : L("Diğerlerinde")): \(action.summary)")
            }
            details[trigger.usage] = parts.isEmpty ? L("Bu aksiyona henüz bir işlem atanmadı.") : parts.joined(separator: " · ")
        }
        return details
    }

    var needsAccessibility: Bool { bindings.contains { $0.isEnabled && $0.needsAccessibility } }

    func openActions() {
        showingActions = true
    }
}

// MARK: - App tabs per device (Logi Options+ style)

extension AppModel {
    /// Sets the action for one app (or the default when `app` is nil); nil action removes it.
    func setAction(_ action: KeyAction?, bindingID: UUID?, app: AppChoice?) {
        guard let bindingID, var binding = bindings.first(where: { $0.id == bindingID }) else { return }
        if let app {
            if let index = binding.appRules.firstIndex(where: { $0.bundleID == app.bundleID }) {
                if let action { binding.appRules[index].action = action } else { binding.appRules.remove(at: index) }
            } else if let action {
                binding.appRules.append(AppRule(bundleID: app.bundleID, appName: app.name, action: action))
            }
        } else {
            binding.defaultAction = action
        }
        update(binding)
    }

    /// The binding fired by a trigger usage (KC_F16 …), if any.
    func binding(forUsage usage: UInt16) -> ActionBinding? {
        guard let trigger = TriggerKey.forUsage(usage) else { return nil }
        return bindings.first { $0.trigger == trigger.combo }
    }

    /// Trigger keys the device currently sends (firmware keymap or macOS remap targets).
    func triggerUsages(on device: KeyboardDevice) -> Set<UInt16> {
        var codes: [UInt16] = []
        if device.capability == .osRemap {
            codes = currentRemaps(device).map(\.to)
        } else if let keymap = states[device.id]?.keymap {
            codes = keymap.layers.flatMap { $0.flatMap { $0 } } + keymap.encoders.flatMap { $0.flatMap { [$0.ccw, $0.cw] } }
        }
        return Set(codes.filter { TriggerKey.forUsage($0) != nil })
    }

    /// Apps shown as tabs for a device: apps with rules on its smart keys plus tabs the user added.
    func appTabs(for device: KeyboardDevice) -> [AppChoice] {
        let usages = triggerUsages(on: device)
        var seen = Set<String>()
        var tabs: [AppChoice] = []
        for usage in usages.sorted() {
            for rule in binding(forUsage: usage)?.appRules ?? [] where seen.insert(rule.bundleID).inserted {
                tabs.append(AppChoice(bundleID: rule.bundleID, name: rule.appName))
            }
        }
        for app in extraAppTabs[device.deviceKey] ?? [] where seen.insert(app.bundleID).inserted {
            tabs.append(app)
        }
        return tabs
    }

    func addAppTab(_ app: AppChoice, device: KeyboardDevice) {
        var list = extraAppTabs[device.deviceKey] ?? []
        if !list.contains(app) { list.append(app) }
        extraAppTabs[device.deviceKey] = list
        saveExtraAppTabs()
        selectedApp[device.id] = app
    }

    func removeAppTab(_ app: AppChoice, device: KeyboardDevice) {
        extraAppTabs[device.deviceKey]?.removeAll { $0 == app }
        saveExtraAppTabs()
        for usage in triggerUsages(on: device) {
            if let binding = binding(forUsage: usage) { setAction(nil, bindingID: binding.id, app: app) }
        }
        if selectedApp[device.id] == app { selectedApp[device.id] = nil }
    }

    /// Turns a key into a smart key: it sends a free trigger key and a binding reproduces its
    /// old behaviour everywhere, so per-app actions can be added on top.
    @discardableResult
    func makeSmartKey(device: KeyboardDevice, layer: Int, slot: KeySlot) async -> ActionBinding? {
        let keycodes = states[device.id]?.keycodes ?? .v6
        let current: UInt16
        switch (device.capability, slot) {
        case let (.osRemap, .matrix(_, col)):
            let usage = UInt16(col)
            current = currentRemaps(device).first { $0.from == usage }?.to ?? usage
        default:
            guard let code = states[device.id]?.keymap.keycode(layer: layer, slot: slot) else { return nil }
            current = code
        }
        if let existing = binding(forUsage: current) { return existing }
        if let reason = SmartKeys.refusal(for: current, keycodes: keycodes) {
            errorMessage = reason
            return nil
        }
        guard let trigger = TriggerKey.forUsage(current) ?? ActionStore.nextFreeTrigger(in: bindings) else {
            errorMessage = L("Tüm tetik tuşları (F13–F20) kullanımda; Aksiyonlar sayfasından birini silin.")
            return nil
        }
        let label = keycodes.shortLabel(current)
        let binding = ActionBinding(name: label.isEmpty ? trigger.name : label, trigger: trigger.combo,
                                    // A bare trigger key has nothing to reproduce (and re-sending it would loop).
                                    defaultAction: TriggerKey.forUsage(current) == nil ? SmartKeys.emulation(of: current, keycodes: keycodes) : nil)
        bindings.append(binding)
        update(binding)
        if TriggerKey.forUsage(current) == nil {
            switch (device.capability, slot) {
            case let (.osRemap, .matrix(_, col)):
                setRemap(from: UInt16(col), to: trigger.usage, device: device)
            default:
                await assign(trigger.usage, device: device, layer: layer, slot: slot)
            }
        }
        return binding
    }

    /// Legend of a key while an app tab is selected.
    func appCap(code: UInt16, app: AppChoice, keycodes: KeycodeSet) -> KeyCapModel {
        if var cap = letterCap(code: code, keycodes: keycodes) {
            cap.kind = .transparent
            return cap
        }
        guard let binding = binding(forUsage: code) else {
            return KeyCapModel(label: keycodes.label(for: code), kind: .transparent, tooltip: L("Bu uygulamada değişmez"))
        }
        if let rule = binding.appRules.first(where: { $0.bundleID == app.bundleID }) {
            return KeyCapModel(label: KeyLabel(main: rule.action.capTitle, sub: app.name), kind: .alpha, subColor: Theme.accent,
                               isHighlighted: true, icon: Self.appIcon(for: rule.action), tooltip: "\(app.name): \(rule.action.summary)")
        }
        let fallback = binding.defaultAction?.capTitle ?? "—"
        return KeyCapModel(label: KeyLabel(main: fallback, sub: L("varsayılan")), kind: .modifier, subColor: Theme.textTertiary,
                           tooltip: L("Varsayılan: %@", "\(binding.defaultAction?.summary ?? L("hiçbir şey"))"))
    }

    static func loadExtraAppTabs() -> [String: [AppChoice]] {
        guard let raw = UserDefaults.standard.dictionary(forKey: "appTabs") as? [String: [[String]]] else { return [:] }
        return raw.mapValues { $0.compactMap { $0.count == 2 ? AppChoice(bundleID: $0[0], name: $0[1]) : nil } }
    }

    private func saveExtraAppTabs() {
        UserDefaults.standard.set(extraAppTabs.mapValues { $0.map { [$0.bundleID, $0.name] } }, forKey: "appTabs")
    }
}

// MARK: - Actions assigned straight to a key

extension AppModel {
    /// What the key sends now: the firmware keycode, or the macOS remap target.
    func currentCode(device: KeyboardDevice, layer: Int, slot: KeySlot) -> UInt16? {
        switch (device.capability, slot) {
        case let (.osRemap, .matrix(_, col)):
            let usage = UInt16(col)
            return currentRemaps(device).first { $0.from == usage }?.to ?? usage
        default:
            return states[device.id]?.keymap.keycode(layer: layer, slot: slot)
        }
    }

    /// Makes a key run `action` (open an app, a URL, a Shortcut, …) everywhere.
    /// A key that already fires an action gets its action replaced; otherwise a free trigger key
    /// is bound to the action and written to the key (firmware keymap or macOS remap).
    func assignKeyAction(_ action: KeyAction?, device: KeyboardDevice, layer: Int, slot: KeySlot) async {
        if let code = currentCode(device: device, layer: layer, slot: slot), var existing = binding(forUsage: code) {
            existing.defaultAction = action
            if let action { existing.name = action.capTitle }
            update(existing)
            return
        }
        guard let action else { return }
        guard let trigger = ActionStore.nextFreeTrigger(in: bindings) else {
            errorMessage = L("Tüm tetik tuşları (F13–F20) kullanımda; Aksiyonlar sayfasından birini silin.")
            return
        }
        let binding = ActionBinding(name: action.capTitle, trigger: trigger.combo, defaultAction: action)
        bindings.append(binding)
        update(binding)
        switch (device.capability, slot) {
        case let (.osRemap, .matrix(_, col)):
            setRemap(from: UInt16(col), to: trigger.usage, device: device)
        default:
            await assign(trigger.usage, device: device, layer: layer, slot: slot)
        }
        notice = L("Aksiyon: %@", action.summary)
    }

    /// Keycap for a key that fires an action, shown in the "all apps" view.
    func actionCap(code: UInt16) -> KeyCapModel? {
        guard let binding = binding(forUsage: code) else { return nil }
        let action = binding.defaultAction
        let extra = binding.appRules.isEmpty ? nil : L("+%@ uygulama", "\(binding.appRules.count)")
        return KeyCapModel(label: KeyLabel(main: action?.capTitle ?? binding.name, sub: extra), kind: .alpha,
                           subColor: Theme.accent, icon: action.flatMap(Self.appIcon(for:)),
                           tooltip: actionDetailsByUsage[code] ?? "")
    }

    static func appIcon(for action: KeyAction) -> NSImage? {
        if case let .openApp(bundleID, _) = action { return AppChoice.icon(for: bundleID) }
        return nil
    }
}
