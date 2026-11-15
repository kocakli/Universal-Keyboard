import AppKit
import KeyMapperCore
import KeyMapperUsage
import Observation
import OSLog
import ServiceManagement

/// App state shared by the menu bar popover and the editor window.
@MainActor
@Observable
final class AppModel {
    enum LoadPhase: Equatable {
        case idle, loading, loaded
        case failed(String)
    }

    struct UnlockFlow: Identifiable {
        let id = UUID()
        let deviceID: String
        var keys: [MatrixPosition]
        var counter: Int?
        var running = false
        var pending: (layer: Int, slot: KeySlot, code: UInt16)?
    }

    var devices: [KeyboardDevice] = []
    var selectedDeviceID: String?
    var profiles: [LayoutProfile] = []
    var assignments: [String: UUID] = [:]
    var states: [String: KeyboardState] = [:]
    var phases: [String: LoadPhase] = [:]
    /// Active macOS remaps per deviceKey.
    var remaps: [String: [KeyRemap]] = [:]
    var activity: [String: String] = [:]
    var errorMessage: String?
    var notice: String?
    var unlock: UnlockFlow?
    var launchAtLogin = SMAppService.mainApp.status == .enabled
    /// Language the UI is shown in, and the user's explicit choice (nil = follow macOS).
    var language: AppLanguage = L10n.current
    var languageOverride: AppLanguage? = L10n.override

    // Actions (trigger keys → open app / shortcut / keystroke, per app)
    var bindings: [ActionBinding] = []
    var actionsEnabled = UserDefaults.standard.object(forKey: "actionsEnabled") as? Bool ?? true
    var refusedBindings: Set<UUID> = []
    var showingActions = false
    /// App tab selected in a device's editor (nil = all apps), keyed by device id.
    var selectedApp: [String: AppChoice] = [:]
    /// Firmware version / update info per device id (Keychron only for now).
    var firmware: [String: FirmwareStatus] = [:]
    /// Battery charge per device id, when the device reports one.
    var batteries: [String: BatteryStatus] = [:]
    /// Lighting values per device id and system, as last read or changed (RAM on the keyboard until saved).
    var lightingValues: [String: [LightingKind: LightingState]] = [:]
    /// Values last read from or saved to the keyboard, for "Undo" and the unsaved marker.
    var savedLighting: [String: [LightingKind: LightingState]] = [:]
    @ObservationIgnored var lightingSends: [String: Task<Void, Never>] = [:]
    /// Screen keyboards (LEOBOG AMG65…): connection state per device id, saved settings per deviceKey.
    var screenStatus: [String: ScreenKeyboardStatus] = [:]
    var screenPreferences: [String: ScreenKeyboardPreferences] = [:]
    @ObservationIgnored var screenSessions: [String: ScreenKeyboardSession] = [:]
    /// The vendor channel last seen per device id, to notice a replug (new registry id) or a channel appearing late.
    @ObservationIgnored var screenChannels: [String: ScreenKeyboardChannel] = [:]
    @ObservationIgnored var screenObservers: [NSObjectProtocol] = []
    @ObservationIgnored var screenTimer: Timer?
    @ObservationIgnored var ledStreams: [String: Task<Void, Never>] = [:]
    /// Devices whose LED stream must resend its frame even if unchanged (an upload ended the live frames).
    @ObservationIgnored var ledResend: Set<String> = []
    /// AI tool quotas (opt-in per provider) and the refresh state.
    var usage: [ProviderUsage] = []
    var usageProviders: [String] = AppModel.loadUsageProviders()
    var usageRefreshing = false
    /// Providers switched on but not read yet (shown as "reading", not as missing data).
    var usageAwaiting: Set<String> = []
    @ObservationIgnored var usageQueued = false
    @ObservationIgnored let usageStore = UsageStore(cacheURL: UsageStore.defaultCacheURL)
    @ObservationIgnored var usageTimer: Timer?
    @ObservationIgnored var usageLastRequest: Date?
    /// Uploads to a screen keyboard's flash memory (LCD image, LED animation), per device id.
    var screenUploads: [String: ScreenUploadState] = [:]
    /// AI tool activity (opt-in): the latest snapshot and each tool's hook state.
    var activityEnabled = UserDefaults.standard.bool(forKey: AppModel.activityEnabledKey)
    var activityRows: [ActivityRow] = []
    var hookStates: [ActivityProvider: HookState] = [:]
    @ObservationIgnored var activityTask: Task<Void, Never>?
    /// Extra app tabs the user added per deviceKey (before any rule exists).
    var extraAppTabs: [String: [AppChoice]] = AppModel.loadExtraAppTabs()
    var accessibilityTrusted = ActionPerformer.isAccessibilityTrusted
    @ObservationIgnored let hotKeys = HotKeyCenter()

    @ObservationIgnored private(set) var sessions: [String: KeyboardSession] = [:]
    @ObservationIgnored private var loadTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var knownDeviceIDs: Set<String> = []
    @ObservationIgnored private let monitor = HIDMonitor()
    @ObservationIgnored private let store = ProfileStore.shared
    @ObservationIgnored private let bluetoothBattery = BluetoothBatteryMonitor()
    @ObservationIgnored private var bluetoothLevels: [String: [Int]] = [:]
    @ObservationIgnored private var batteryTimer: Timer?

    init() {
        reloadProfiles()
        monitor.onChange = { [weak self] devices in
            MainActor.assumeIsolated { self?.devicesChanged(devices) }
        }
        bluetoothBattery.onChange = { [weak self] levels in
            MainActor.assumeIsolated {
                self?.bluetoothLevels = levels
                self?.refreshBatteries()
            }
        }
        monitor.start()
        setUpUsage()
        setUpScreenKeyboards()
        setUpActivity()
        devicesChanged(monitor.snapshot())
        setUpActions()
        // Battery levels change slowly; IORegistry has no change notification for them.
        batteryTimer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.bluetoothBattery.refresh()
                self?.refreshBatteries()
            }
        }
    }

    // MARK: Devices

    var selectedDevice: KeyboardDevice? { devices.first { $0.id == selectedDeviceID } }

    private func devicesChanged(_ list: [KeyboardDevice]) {
        let ids = Set(list.map(\.id))
        for device in list {
            // The raw HID interface may appear after the keyboard interface; restart the session then.
            if let session = sessions[device.id], session.device.rawHIDRegistryID != device.rawHIDRegistryID {
                dropSession(device.id)
            }
        }
        for id in sessions.keys where !ids.contains(id) { dropSession(id) }
        for id in phases.keys where !ids.contains(id) { phases[id] = nil; states[id] = nil }

        let added = list.filter { !knownDeviceIDs.contains($0.id) }
        knownDeviceIDs = ids
        devices = list
        if selectedDeviceID.map({ !ids.contains($0) }) ?? true { selectedDeviceID = list.first?.id }
        for device in added {
            autoApply(device)
            Task { await refreshFirmware(device) }
        }
        bluetoothBattery.watch(names: Set(list.filter(\.isBluetoothLE).map(\.name).filter { !$0.isEmpty }))
        screenKeyboardsChanged(list)
        refreshBatteries()
    }

    /// IORegistry first (Apple and Bluetooth Classic), then the GATT Battery Service for Bluetooth LE keyboards.
    func refreshBatteries() {
        let entries = BatteryReader.registryEntries()
        var result: [String: BatteryStatus] = [:]
        for device in devices {
            if let status = BatteryReader.status(for: device, in: entries) {
                result[device.id] = status
            } else if device.isBluetoothLE, let levels = bluetoothLevels[device.name.lowercased()], !levels.isEmpty {
                result[device.id] = BatteryStatus(levels: levels)
            }
        }
        guard result != batteries else { return }
        batteries = result
        for device in devices {
            let levels = result[device.id]?.levels.map(String.init).joined(separator: ",") ?? "-"
            Self.batteryLog.info("battery \(device.deviceKey, privacy: .public) \(device.transportLabel, privacy: .public): \(levels, privacy: .public)")
        }
    }

    private static let batteryLog = Logger(subsystem: "dev.keymapper.KeyMapper", category: "battery")

    private func dropSession(_ id: String) {
        sessions[id]?.close()
        sessions[id] = nil
        loadTasks[id]?.cancel()
        loadTasks[id] = nil
        states[id] = nil
        phases[id] = nil
        lightingValues[id] = nil
        savedLighting[id] = nil
    }

    /// macOS forgets hidutil mappings on reconnect, so re-apply the assigned remap profile.
    private func autoApply(_ device: KeyboardDevice) {
        guard let profile = assignedProfile(for: device), profile.kind == .osRemap else { return }
        let remaps = profile.remaps ?? []
        self.remaps[device.deviceKey] = remaps
        Task.detached { try? HIDUtilRemapper.apply(remaps, vendorID: device.vendorID, productID: device.productID) }
    }

    func phase(for device: KeyboardDevice) -> LoadPhase { phases[device.id] ?? .idle }

    /// Loads definition + keymap of a programmable keyboard (once).
    func ensureLoaded(_ device: KeyboardDevice, force: Bool = false) async {
        if device.capability == .osRemap {
            if remaps[device.deviceKey] == nil { reloadRemaps(device) }
            return
        }
        if force { dropSession(device.id) }
        if let task = loadTasks[device.id] { await task.value; return }
        if case .loaded = phase(for: device) { return }

        let task = Task { [weak self] in
            guard let self else { return }
            self.phases[device.id] = .loading
            do {
                let session = try KeyboardSession(device: device)
                self.sessions[device.id] = session
                let state = try await session.load()
                guard !Task.isCancelled else { return }
                self.states[device.id] = state
                self.phases[device.id] = .loaded
                if let family = state.keychron?.family {
                    let deviceID = device.id
                    session.observeKeychronLayers(family: family) { [weak self] base, active in
                        Task { @MainActor in self?.keychronLayersChanged(deviceID: deviceID, base: base, active: active) }
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                self.sessions[device.id]?.close()
                self.sessions[device.id] = nil
                self.phases[device.id] = .failed(error.localizedDescription)
            }
            self.loadTasks[device.id] = nil
        }
        loadTasks[device.id] = task
        await task.value
    }

    // MARK: Editing

    func assign(_ code: UInt16, device: KeyboardDevice, layer: Int, slot: KeySlot) async {
        guard let state = states[device.id], let session = sessions[device.id], !session.isClosed else {
            reconnectAfterLostSession(device)
            return
        }
        // Vial firmware ignores QK_BOOT assignments while locked.
        if device.isVial, code == state.keycodes.parse("QK_BOOT") {
            if let status = try? await session.vialUnlockStatus(), !status.unlocked {
                unlock = UnlockFlow(deviceID: device.id, keys: status.keys, pending: (layer, slot, code))
                return
            }
        }
        do {
            try await session.setKeycode(code, layer: layer, slot: slot)
            states[device.id]?.keymap.set(code, layer: layer, slot: slot)
        } catch {
            fail(error, device: device)
        }
    }

    func runUnlock() async {
        guard var flow = unlock, !flow.running, let session = sessions[flow.deviceID] else { return }
        flow.running = true
        unlock = flow
        do {
            try await session.vialUnlockStart()
            while let current = unlock, current.id == flow.id {
                let poll = try await session.vialUnlockPoll()
                unlock?.counter = poll.counter
                if poll.unlocked {
                    unlock = nil
                    notice = L("Vial kilidi açıldı.")
                    if let pending = flow.pending, let device = devices.first(where: { $0.id == flow.deviceID }) {
                        await assign(pending.code, device: device, layer: pending.layer, slot: pending.slot)
                    }
                    return
                }
                try await Task.sleep(for: .milliseconds(100))
            }
        } catch {
            unlock = nil
            errorMessage = error.localizedDescription
        }
    }

    /// Keychron firmware pushed a layer change (Fn held, Mac/Windows switch moved).
    private func keychronLayersChanged(deviceID: String, base: Int?, active: Int?) {
        guard states[deviceID]?.keychron != nil else { return }
        if let base { states[deviceID]?.keychron?.defaultLayer = base }
        states[deviceID]?.keychron?.activeLayer = active
    }

    // MARK: Alphabet layouts

    /// Undo data for the last alphabet conversion of each keyboard.
    struct AlphaUndo {
        let layer: Int
        let codes: [[UInt16]]
        let layoutID: String
    }
    var alphaUndo: [String: AlphaUndo] = [:]

    /// Layout id per "deviceKey#layer", persisted so a converted layer is not converted again later.
    private var alphaLayoutIDs = UserDefaults.standard.dictionary(forKey: "alphaLayouts") as? [String: String] ?? [:]

    /// The alphabet layout a layer is in, as last converted by KeyMapper (QWERTY until then).
    func alphaLayout(device: KeyboardDevice, layer: Int) -> AlphaLayout {
        let id = alphaLayoutIDs["\(device.deviceKey)#\(layer)"]
        return AlphaLayout.all.first { $0.id == id } ?? .qwerty
    }

    func setAlphaLayout(_ layout: AlphaLayout, device: KeyboardDevice, layer: Int) {
        alphaLayoutIDs["\(device.deviceKey)#\(layer)"] = layout == .qwerty ? nil : layout.id
        UserDefaults.standard.set(alphaLayoutIDs, forKey: "alphaLayouts")
    }

    /// Converts the alphabet keys of a layer from its current layout to `target`. The current layout is
    /// remembered afterwards, so pressing the button again cannot convert an already converted layer twice.
    func convertAlpha(device: KeyboardDevice, layer: Int, to target: AlphaLayout) async {
        guard let state = states[device.id], layer < state.keymap.layers.count else { return }
        let source = alphaLayout(device: device, layer: layer)
        guard source != target else { return }
        let previous = state.keymap.layers[layer]
        var updated = state.keymap
        updated.layers[layer] = AlphaLayout.convert(layer: previous, from: source, to: target, keycodes: state.keycodes)
        guard await write(updated, to: device, message: "\(source.name) → \(target.name)") else { return }
        setAlphaLayout(target, device: device, layer: layer)
        alphaUndo[device.id] = AlphaUndo(layer: layer, codes: previous, layoutID: source.id)
    }

    /// Puts back the layer as it was before the last alphabet conversion.
    func undoAlpha(device: KeyboardDevice) async {
        guard let undo = alphaUndo[device.id], let state = states[device.id], undo.layer < state.keymap.layers.count else { return }
        var updated = state.keymap
        updated.layers[undo.layer] = undo.codes
        guard await write(updated, to: device, message: L("Alfabe dönüşümü geri alındı")) else { return }
        if let layout = AlphaLayout.all.first(where: { $0.id == undo.layoutID }) { setAlphaLayout(layout, device: device, layer: undo.layer) }
        alphaUndo[device.id] = nil
    }

    @discardableResult
    private func write(_ keymap: Keymap, to device: KeyboardDevice, message: String) async -> Bool {
        guard let state = states[device.id], let session = sessions[device.id], !session.isClosed else {
            reconnectAfterLostSession(device)
            return false
        }
        activity[device.id] = L("%@: yazılıyor…", "\(message)")
        defer { activity[device.id] = nil }
        do {
            let deviceID = device.id
            let count = try await session.write(keymap, over: state.keymap) { [weak self] done, total in
                Task { @MainActor in self?.activity[deviceID] = "\(message): \(done)/\(total)" }
            }
            states[device.id]?.keymap = keymap
            notice = count == 0 ? L("%@: değişiklik yok.", "\(message)") : L("%@: %@ tuş güncellendi.", "\(message)", "\(count)")
            return true
        } catch {
            fail(error, device: device)
            await ensureLoaded(device, force: true)
            return false
        }
    }

    /// The keyboard went away (e.g. Bluetooth sleep): say so and read it again.
    private func reconnectAfterLostSession(_ device: KeyboardDevice) {
        errorMessage = L("Klavyeye ulaşılamadı; değişiklik yazılmadı. Klavye yeniden okunuyor; Bluetooth klavyeyi bir tuşa basarak uyandırıp tekrar deneyin.")
        Task { await ensureLoaded(device, force: true) }
    }

    private func fail(_ error: Error, device: KeyboardDevice) {
        errorMessage = "\(device.displayName): \(error.localizedDescription)"
        if (error as? HIDError) == .disconnected { dropSession(device.id) }
    }

    // MARK: Profiles

    func reloadProfiles() {
        profiles = store.all()
        assignments = store.assignments()
    }

    func profiles(for device: KeyboardDevice) -> [LayoutProfile] {
        profiles.filter { $0.deviceKey == device.deviceKey && $0.kind == expectedKind(device) }
    }

    func expectedKind(_ device: KeyboardDevice) -> LayoutProfile.Kind {
        device.capability == .osRemap ? .osRemap : .firmware
    }

    func assignedProfile(for device: KeyboardDevice) -> LayoutProfile? {
        guard let id = assignments[device.deviceKey] else { return nil }
        return profiles.first { $0.id == id }
    }

    func apply(_ profile: LayoutProfile, to device: KeyboardDevice) async {
        switch profile.kind {
        case .osRemap:
            setRemaps(profile.remaps ?? [], device: device, persist: false)
            store.assign(profile, to: device.deviceKey)
            reloadProfiles()
            notice = "\(profile.name) → \(device.displayName)"
        case .firmware:
            await ensureLoaded(device)
            guard let state = states[device.id] else { return }
            let resolved = profile.resolve(onto: state.keymap, keycodes: state.keycodes)
            await write(resolved.keymap, to: device, message: profile.name)
            if !resolved.unknown.isEmpty {
                errorMessage = L("Tanınmayan keycode'lar atlandı: ") + Set(resolved.unknown).sorted().prefix(12).joined(separator: ", ")
            }
            store.assign(profile, to: device.deviceKey)
            reloadProfiles()
        }
    }

    func saveCurrentLayout(of device: KeyboardDevice, name: String) {
        let profile: LayoutProfile
        if device.capability == .osRemap {
            profile = LayoutProfile(name: name, deviceKey: device.deviceKey, kind: .osRemap, remaps: remaps[device.deviceKey] ?? [])
        } else {
            guard let state = states[device.id] else { return }
            profile = .snapshot(name: name, deviceKey: device.deviceKey, keymap: state.keymap, keycodes: state.keycodes)
        }
        do {
            try store.save(profile)
            store.assign(profile, to: device.deviceKey)
            reloadProfiles()
            notice = L("Profil kaydedildi: %@", "\(name)")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ profile: LayoutProfile) {
        store.delete(profile)
        reloadProfiles()
    }

    func importLayoutFile(for device: KeyboardDevice) {
        guard let url = Panels.open(title: L("Layout dosyası seç (.vil, VIA .json, KeyMapper profili)"), extensions: ["vil", "json"]) else { return }
        do {
            var profile = try LayoutFiles.importProfile(from: url, deviceKey: device.deviceKey, cols: states[device.id]?.definition.cols)
            if profile.kind != expectedKind(device) {
                errorMessage = L("Bu dosya %@ için uygun değil.", "\(device.displayName)")
                return
            }
            profile.name = uniqueName(profile.name, device: device)
            try store.save(profile)
            reloadProfiles()
            notice = L("İçe aktarıldı: %@. Uygulamak için Profil menüsünden seçin.", "\(profile.name)")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func export(_ device: KeyboardDevice, format: ExportFormat) {
        guard let state = states[device.id] else { return }
        let base = state.definition.name.replacingOccurrences(of: "/", with: "-")
        guard let url = Panels.save(title: L("Dışa aktar"), name: "\(base).\(format.fileExtension)") else { return }
        do {
            let data: Data
            switch format {
            case .vial:
                data = try LayoutFiles.vilData(keymap: state.keymap, keycodes: state.keycodes, uid: state.vialUID,
                                               viaProtocol: state.viaProtocol, vialProtocol: state.vialProtocol)
            case .via:
                data = try LayoutFiles.viaData(keymap: state.keymap, keycodes: state.keycodes,
                                               name: state.definition.name, vendorProductID: device.vendorProductID)
            case .profile:
                data = try LayoutFiles.profileData(.snapshot(name: base, deviceKey: device.deviceKey, keymap: state.keymap, keycodes: state.keycodes))
            }
            try data.write(to: url, options: .atomic)
            notice = L("Kaydedildi: %@", url.lastPathComponent)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    enum ExportFormat {
        case vial, via, profile
        var fileExtension: String { self == .vial ? "vil" : "json" }
    }

    func importDefinition(for device: KeyboardDevice) {
        guard let url = Panels.open(title: L("VIA tanım dosyası seç (.json)"), extensions: ["json"]) else { return }
        do {
            try DefinitionStore.shared.importUserDefinition(from: url, vendorID: device.vendorID, productID: device.productID)
            Task { await ensureLoaded(device, force: true) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func uniqueName(_ name: String, device: KeyboardDevice) -> String {
        let existing = Set(profiles(for: device).map(\.name))
        guard existing.contains(name) else { return name }
        var index = 2
        while existing.contains("\(name) \(index)") { index += 1 }
        return "\(name) \(index)"
    }

    // MARK: macOS remaps

    func currentRemaps(_ device: KeyboardDevice) -> [KeyRemap] { remaps[device.deviceKey] ?? [] }

    func reloadRemaps(_ device: KeyboardDevice) {
        if let profile = assignedProfile(for: device), profile.kind == .osRemap {
            remaps[device.deviceKey] = profile.remaps ?? []
        } else {
            let key = device.deviceKey
            let vendorID = device.vendorID, productID = device.productID
            Task.detached {
                let current = HIDUtilRemapper.current(vendorID: vendorID, productID: productID)
                await MainActor.run { [weak self] in self?.remaps[key] = current }
            }
        }
    }

    /// Changes one key (nil = remove the remap) and stores it in the assigned macOS profile.
    func setRemap(from: UInt16, to: UInt16?, device: KeyboardDevice) {
        var list = currentRemaps(device).filter { $0.from != from }
        if let to, to != from { list.append(KeyRemap(from: from, to: to)) }
        setRemaps(list, device: device, persist: true)
    }

    func mergeRemaps(_ extra: [KeyRemap], device: KeyboardDevice) {
        let froms = Set(extra.map(\.from))
        setRemaps(currentRemaps(device).filter { !froms.contains($0.from) } + extra, device: device, persist: true)
    }

    func setRemaps(_ list: [KeyRemap], device: KeyboardDevice, persist: Bool) {
        let sorted = list.sorted { $0.from < $1.from }
        do {
            try HIDUtilRemapper.apply(sorted, vendorID: device.vendorID, productID: device.productID)
            remaps[device.deviceKey] = sorted
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        guard persist else { return }
        var profile = assignedProfile(for: device).flatMap { $0.kind == .osRemap ? $0 : nil }
            ?? LayoutProfile(name: L("Varsayılan"), deviceKey: device.deviceKey, kind: .osRemap)
        profile.remaps = sorted
        try? store.save(profile)
        store.assign(profile, to: device.deviceKey)
        reloadProfiles()
    }

    // MARK: Misc

    func setLanguage(_ choice: AppLanguage?) {
        L10n.setOverride(choice)
        languageOverride = choice
        language = L10n.current
        notice = nil
        errorMessage = nil
        // Release notes come in the selected language.
        for device in devices { Task { await refreshFirmware(device) } }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            errorMessage = L("Girişte başlatma ayarlanamadı: %@ (uygulamanın .app olarak kurulu olması gerekir)", "\(error.localizedDescription)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
