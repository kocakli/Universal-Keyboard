import AppKit
import KeyMapperCore

/// What the app knows about a screen keyboard's vendor channel right now.
struct ScreenKeyboardStatus: Equatable {
    enum Link: Equatable {
        case idle
        case ready
        /// Another program (AMG65 Studio) holds the channel.
        case busy
        /// A transaction stopped half way; the keyboard must be reconnected.
        case needsReconnect
        case failed(String)
    }

    var link: Link = .idle
    /// What is being sent right now, for a progress line.
    var working: String?
    /// Why sending stopped, while `link` is `needsReconnect` (nil when no reason was recorded).
    var stop: ScreenKeyboardStop?
}

/// Settings the keyboard can't report back, remembered per keyboard model and ID (`deviceKey`).
struct ScreenKeyboardPreferences: Codable, Equatable {
    var lighting = AMG65Lighting()
    var appliedLighting: AMG65Lighting?
    var settings = AMG65DeviceSettings()
    var appliedSettings: AMG65DeviceSettings?
    /// Set the keyboard clock when it connects and every six hours.
    var autoClock = true
    var lastClockSync: Date?
    /// What the LED matrix shows while KeyMapper streams to it.
    var display = LEDDisplaySettings()
    /// Per-key colours (key slot → colour) and their brightness (1…5); unpainted keys stay dark.
    var keyColors: [Int: RGB24] = [:]
    var keyColorBrightness: UInt8 = 5
    var appliedKeyColors: [Int: RGB24]?
    var appliedKeyColorBrightness: UInt8?
    /// The keyboard's own key table (slot → action); a missing slot is the factory key.
    var keyMap: [Int: AMG65KeyAction] = [:]
    var appliedKeyMap: [Int: AMG65KeyAction]?
    /// Which backlight was sent last: an effect, or the per-key colours (which replace the effect).
    var lastBacklight: Backlight?

    enum Backlight: String, Codable { case effect, keyColors }

    var keyColorsPending: Bool { keyColors != appliedKeyColors || keyColorBrightness != appliedKeyColorBrightness }
    var keyMapPending: Bool { keyMap != (appliedKeyMap ?? [:]) }

    // Decoding stays tolerant of preferences saved by older versions.
    enum CodingKeys: String, CodingKey {
        case lighting, appliedLighting, settings, appliedSettings, autoClock, lastClockSync, display
        case keyColors, keyColorBrightness, appliedKeyColors, appliedKeyColorBrightness, keyMap, appliedKeyMap, lastBacklight
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lighting = try c.decodeIfPresent(AMG65Lighting.self, forKey: .lighting) ?? AMG65Lighting()
        appliedLighting = try c.decodeIfPresent(AMG65Lighting.self, forKey: .appliedLighting)
        settings = try c.decodeIfPresent(AMG65DeviceSettings.self, forKey: .settings) ?? AMG65DeviceSettings()
        appliedSettings = try c.decodeIfPresent(AMG65DeviceSettings.self, forKey: .appliedSettings)
        autoClock = try c.decodeIfPresent(Bool.self, forKey: .autoClock) ?? true
        lastClockSync = try c.decodeIfPresent(Date.self, forKey: .lastClockSync)
        display = try c.decodeIfPresent(LEDDisplaySettings.self, forKey: .display) ?? LEDDisplaySettings()
        keyColors = (try? c.decodeIfPresent([Int: RGB24].self, forKey: .keyColors)) ?? [:]
        keyColorBrightness = (try? c.decodeIfPresent(UInt8.self, forKey: .keyColorBrightness)) ?? 5
        appliedKeyColors = try? c.decodeIfPresent([Int: RGB24].self, forKey: .appliedKeyColors)
        appliedKeyColorBrightness = try? c.decodeIfPresent(UInt8.self, forKey: .appliedKeyColorBrightness)
        keyMap = (try? c.decodeIfPresent([Int: AMG65KeyAction].self, forKey: .keyMap)) ?? [:]
        appliedKeyMap = try? c.decodeIfPresent([Int: AMG65KeyAction].self, forKey: .appliedKeyMap)
        lastBacklight = try? c.decodeIfPresent(Backlight.self, forKey: .lastBacklight)
    }
}

extension AppModel {
    /// AMG65 Studio's bridge synced every six hours; the keyboard's own clock drifts little in that time.
    static let clockInterval: TimeInterval = 6 * 60 * 60

    func setUpScreenKeyboards() {
        let center = NSWorkspace.shared.notificationCenter
        // After sleep the clock may be stale; after a time-zone change it is wrong.
        screenObservers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncScreenClocks(force: true) }
        })
        screenObservers.append(NotificationCenter.default.addObserver(forName: .NSSystemTimeZoneDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncScreenClocks(force: true) }
        })
        screenTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncScreenClocks(force: false) }
        }
        AppDelegate.isUploading = { [weak self] in self?.isUploadingToScreen ?? false }
        AppDelegate.willTerminate = { [weak self] in self?.finishScreenSessions() }
    }

    /// Follows the vendor channels, not the devices: a replug gives the channel a new registry id (which lifts a stop),
    /// and the channel's interface often appears after the keyboard's, when the device is no longer new.
    func screenKeyboardsChanged(_ list: [KeyboardDevice]) {
        let present = Dictionary(uniqueKeysWithValues: list.compactMap { device in device.screenKeyboard.map { (device.id, $0) } })
        let (gone, appeared) = ScreenKeyboardChannel.changes(from: screenChannels, to: present)
        screenChannels = present
        for id in gone {
            ledStreams[id]?.cancel()
            ledStreams[id] = nil
            screenSessions[id]?.close()
            screenSessions[id] = nil
            screenStatus[id] = nil
        }
        for device in list where appeared.contains(device.id) {
            Task {
                if preferences(for: device).autoClock { await syncClock(device) }
                updateLEDStream(device)
            }
        }
    }

    // MARK: Preferences

    func preferences(for device: KeyboardDevice) -> ScreenKeyboardPreferences {
        if let cached = screenPreferences[device.deviceKey] { return cached }
        let stored = UserDefaults.standard.data(forKey: Self.preferencesKey(device))
            .flatMap { try? JSONDecoder().decode(ScreenKeyboardPreferences.self, from: $0) } ?? ScreenKeyboardPreferences()
        return stored
    }

    func updatePreferences(for device: KeyboardDevice, _ change: (inout ScreenKeyboardPreferences) -> Void) {
        var value = preferences(for: device)
        change(&value)
        screenPreferences[device.deviceKey] = value
        if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: Self.preferencesKey(device)) }
    }

    private static func preferencesKey(_ device: KeyboardDevice) -> String { "screenKeyboard.\(device.deviceKey)" }

    // MARK: Channel

    /// Opens the vendor channel on first use. Another program holding it is reported, not treated as an error.
    func screenSession(for device: KeyboardDevice) -> ScreenKeyboardSession? {
        if let session = screenSessions[device.id], !session.isClosed { return session }
        guard let channel = device.screenKeyboard else { return nil }
        do {
            let session = try ScreenKeyboardSession(channel: channel)
            screenSessions[device.id] = session
            screenStatus[device.id, default: .init()].link = .ready
            return session
        } catch {
            record(error, device: device)
            return nil
        }
    }

    /// Sends one job; the label shows while it runs. Returns false when nothing (or not all of it) was sent.
    @discardableResult
    func send(_ label: String, to device: KeyboardDevice, _ work: @escaping (AMG65Link) throws -> Void) async -> Bool {
        guard let session = screenSession(for: device) else { return false }
        screenStatus[device.id, default: .init()].working = label
        defer { screenStatus[device.id]?.working = nil }
        do {
            try await session.perform(work)
            screenStatus[device.id, default: .init()].link = .ready
            return true
        } catch {
            record(error, device: device)
            return false
        }
    }

    func record(_ error: Error, device: KeyboardDevice) {
        let link: ScreenKeyboardStatus.Link
        switch error as? ScreenKeyboardError {
        case .busy: link = .busy
        case .needsReconnect, .rejected, .noAcknowledgement, .checksumMismatch: link = .needsReconnect
        default: link = .failed(error.localizedDescription)
        }
        screenStatus[device.id, default: .init()].link = link
        // Looked up by the keyboard, not read off the error: after a restart the error is a bare `needsReconnect`.
        screenStatus[device.id]?.stop = link == .needsReconnect
            ? device.screenKeyboard.flatMap { AMG65Link.lastStop(for: $0.registryID) } : nil
        if link != .busy {
            // A stopped transaction leaves the channel unusable; drop it so a replug starts clean.
            screenSessions[device.id]?.close()
            screenSessions[device.id] = nil
        }
    }

    /// Tries the channel again (e.g. after AMG65 Studio was quit).
    func retryScreenKeyboard(_ device: KeyboardDevice) async {
        screenStatus[device.id] = nil
        if preferences(for: device).autoClock { await syncClock(device) } else { _ = screenSession(for: device) }
        updateLEDStream(device)
    }

    // MARK: LED matrix

    /// Starts or stops streaming to the LED matrix to match the setting.
    func updateLEDStream(_ device: KeyboardDevice) {
        let enabled = preferences(for: device).display.enabled && device.screenKeyboard?.supportsLEDMatrix == true
        if enabled {
            guard ledStreams[device.id] == nil, let session = screenSession(for: device) else { return }
            ledStreams[device.id] = Task { [weak self] in await self?.streamLED(device, session: session) }
        } else if let task = ledStreams[device.id] {
            task.cancel()
            ledStreams[device.id] = nil
            if let session = screenSessions[device.id] {
                Task { try? await session.perform { try $0.endFrames() } }
            }
        }
    }

    /// AMG65 Studio's cadence: a scene every 0.5 s, sent only when it changed (the link paces frames to 4/s).
    private func streamLED(_ device: KeyboardDevice, session: ScreenKeyboardSession) async {
        let started = Date()
        var step = 0
        var last: [RGB24]?
        while !Task.isCancelled, !session.isClosed {
            guard preferences(for: device).display.enabled else { break }
            let pixels = ledScene(for: device, seconds: Date().timeIntervalSince(started), step: step)
            if pixels != last || ledResend.remove(device.id) != nil {
                do {
                    try await session.perform { try $0.showFrame(pixels) }
                    last = pixels
                } catch ScreenKeyboardError.frameBusy {
                    // The matrix dropped this frame; give it a moment, then carry on.
                    try? await Task.sleep(for: .seconds(1))
                } catch {
                    record(error, device: device)
                    break
                }
            }
            step += 1
            try? await Task.sleep(for: .milliseconds(500))
        }
        // Frees the slot for a restart, unless a newer stream (to the session a replug opened) already took it.
        if ledStreams[device.id]?.isCancelled == false, screenSessions[device.id].map({ $0 === session }) ?? true {
            ledStreams[device.id] = nil
        }
    }

    /// The LED matrix frame for this moment; the stream and every preview use this one function.
    func ledScene(for device: KeyboardDevice, seconds: Double, step: Int, now: Date = Date()) -> [RGB24] {
        LEDScene.frame(settings: preferences(for: device).display, quotas: ledQuotas, activities: ledActivities,
                       seconds: seconds, animationStep: step, now: now.timeIntervalSince1970).pixels
    }

    /// True while something is being sent, or while sending is stopped until the cable is replugged (a send would
    /// only fail); write buttons are disabled then, the rest of the section stays usable.
    func isScreenBusy(_ device: KeyboardDevice) -> Bool {
        screenStatus[device.id]?.working != nil || screenUploads[device.id]?.isRunning == true
            || screenStatus[device.id]?.link == .needsReconnect
    }

    /// On quit: lets each keyboard's transaction in progress finish (a process that exits half way through one leaves
    /// the keyboard waiting for the rest), then closes the channels. Closing sends one more transaction when live
    /// frames are running: end and apply, which hand the LED matrix back to the keyboard's own animation.
    func finishScreenSessions() {
        for task in ledStreams.values { task.cancel() }
        ledStreams = [:]
        for session in screenSessions.values { session.finish(timeout: 3) }
        screenSessions = [:]
    }

    /// Writing a file to a keyboard's memory; quitting is refused until it ends.
    var isUploadingToScreen: Bool { screenUploads.values.contains { $0.isRunning } }

    // MARK: Clock

    func syncScreenClocks(force: Bool) {
        for device in devices where device.screenKeyboard?.supportsClock == true {
            let prefs = preferences(for: device)
            guard prefs.autoClock else { continue }
            // Don't fight another program for the channel every minute.
            if !force, screenStatus[device.id]?.link == .busy { continue }
            // An upload holds the channel for minutes; the clock waits for the next check.
            if screenUploads[device.id]?.isRunning == true { continue }
            let due = prefs.lastClockSync.map { Date().timeIntervalSince($0) >= Self.clockInterval } ?? true
            if force || due { Task { await syncClock(device) } }
        }
    }

    func syncClock(_ device: KeyboardDevice) async {
        guard device.screenKeyboard?.supportsClock == true else { return }
        let now = Date()
        let ok = await send(L("Saat eşitleniyor…"), to: device) { link in
            try link.run(AMG65Protocol.timeSync(now))
        }
        if ok { updatePreferences(for: device) { $0.lastClockSync = now } }
    }

    // MARK: Lighting and settings

    func applyScreenLighting(_ device: KeyboardDevice) async {
        guard let channel = device.screenKeyboard else { return }
        let lighting = preferences(for: device).lighting
        let ok = await send(L("Işık gönderiliyor…"), to: device) { link in
            if channel.link == .wired {
                try link.run(AMG65Protocol.lighting(lighting))
            } else {
                try link.runDongle(AMG65DongleProtocol.lighting(lighting))
            }
        }
        if ok {
            updatePreferences(for: device) {
                $0.appliedLighting = lighting
                $0.lastBacklight = .effect
            }
            notice = L("Işık ayarları klavyeye gönderildi.")
        }
    }

    func applyScreenSettings(_ device: KeyboardDevice) async {
        guard device.screenKeyboard?.link == .wired else { return }
        let settings = preferences(for: device).settings
        let ok = await send(L("Ayarlar gönderiliyor…"), to: device) { link in
            try link.run(AMG65Protocol.settings(settings))
        }
        if ok {
            updatePreferences(for: device) { $0.appliedSettings = settings }
            notice = L("Klavye ayarları gönderildi.")
        }
    }
}
