import Foundation
import KeyMapperCore

// kmctl: command line companion of KeyMapper.
//   kmctl list                     connected keyboards
//   kmctl dump <n> [layer]         print the keymap of keyboard n
//   kmctl export <n> <file>        save the keymap as .vil (Vial) or .json (VIA)
//   kmctl apply <n> <file>         write a .vil / VIA .json / profile onto keyboard n
//   kmctl remap <n> <preset|clear> macOS level remap (non-programmable keyboards)
//   kmctl screen <n> [sync-time]   keyboards with a display (LEOBOG AMG65): status, clock
//   kmctl screen <n> frame-recovery  check that a cut-off LED frame is closed and sending goes on

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(1)
}

func devices() -> [KeyboardDevice] { HIDMonitor().snapshot() }

func device(at argument: String?) -> KeyboardDevice {
    let list = devices()
    guard let argument, let index = Int(argument), list.indices.contains(index) else {
        fail(L("Geçersiz klavye numarası. 'kmctl list' ile listeleyin."))
    }
    return list[index]
}

func runAsync(_ body: @escaping () async throws -> Void) -> Never {
    Task {
        do { try await body(); exit(0) } catch { fail(L("Hata: %@", error.localizedDescription)) }
    }
    RunLoop.main.run()
    exit(0)
}

func loadState(_ device: KeyboardDevice) async throws -> (KeyboardSession, KeyboardState) {
    let session = try KeyboardSession(device: device)
    return (session, try await session.load())
}

let args = Array(CommandLine.arguments.dropFirst())

switch args.first {
case "list", nil:
    let list = devices()
    if list.isEmpty { print(L("Bağlı klavye yok.")) }
    let batteries = BatteryReader.registryEntries()
    for (index, device) in list.enumerated() {
        var line = String(format: "[%d] %@  %@  %@  %@  (%@)", index, device.displayName, device.deviceKey,
                          device.transportLabel, device.capability.title, device.brand.name)
        // Bluetooth LE levels need CoreBluetooth and a permission prompt; only the app reads those.
        if let battery = BatteryReader.status(for: device, in: batteries) {
            let percent = (Double(battery.level) / 100).formatted(.percent.precision(.fractionLength(0)).locale(L10n.current.locale))
            line += "  " + L("pil %@", percent)
        }
        if let screen = device.screenKeyboard {
            line += "  " + L("ekranlı: %@", "\(screen.model.name), \(screen.link == .wired ? L("kablo") : L("alıcı"))")
        }
        print(line)
    }

case "screen":
    // kmctl screen <n>            read-only status of the vendor channel
    // kmctl screen <n> sync-time  set the keyboard clock from the Mac (writes to the keyboard)
    // kmctl screen <n> frame-recovery  live LED frames (RAM only): cut one short, close it, send a whole one
    let target = device(at: args.dropFirst().first)
    guard let channel = target.screenKeyboard else { fail(L("Bu klavye ekranlı klavye olarak tanınmadı.")) }
    print(L("%@ — %@", channel.model.name, channel.link == .wired ? L("USB kablosu") : L("2.4 GHz alıcı")))
    let action = args.count > 2 ? args[2] : "status"
    runAsync {
        let session: ScreenKeyboardSession
        do {
            session = try ScreenKeyboardSession(channel: channel)
        } catch {
            print(L("Kanal: %@", error.localizedDescription))
            return
        }
        defer { session.close() }
        switch action {
        case "status":
            print(L("Kanal: boşta, KeyMapper kullanabilir."))
        case "sync-time":
            guard channel.supportsClock else { fail(ScreenKeyboardError.needsCable.localizedDescription) }
            try await session.perform { link in try link.run(AMG65Protocol.timeSync(Date())) }
            print(L("Klavye saati Mac ile eşitlendi."))
        case "frame-recovery":
            // A frame cut off before, inside and after its data, as a lost reply leaves it.
            guard channel.supportsLEDMatrix else { fail(ScreenKeyboardError.needsCable.localizedDescription) }
            try await session.perform { link in
                for cut in [0, 5, 15] {
                    let packets = try link.checkFrameRecovery(dataPackets: cut)
                    print(L("Yarım kare (%@/15 veri paketi): %@ end paketiyle kapandı, ardından tam kare onaylandı.", "\(cut)", "\(packets)"))
                }
                try link.endFrames()
            }
            print(L("LED ekran klavyenin kendi animasyonuna döndü."))
        default:
            fail(L("Kullanım: kmctl screen <n> [status|sync-time|frame-recovery]"))
        }
    }

case "dump":
    let target = device(at: args.dropFirst().first)
    let onlyLayer = args.count > 2 ? Int(args[2]) : nil
    runAsync {
        let (session, state) = try await loadState(target)
        defer { session.close() }
        print(L("%@ — VIA protokol %@%@, keycode %@", "\(state.definition.name)", "\(state.viaProtocol)", "\(state.vialProtocol.map { L(", Vial protokol %@", "\($0)") } ?? "")", "\(state.keycodes.version.rawValue)"))
        print(L("Matris %@x%@, %@ katman, %@ tuş, kaynak: %@", "\(state.definition.rows)", "\(state.definition.cols)", "\(state.layerCount)", "\(state.definition.keys.count)", "\(state.definition.source.title)"))
        if let firmware = state.firmwareVersion ?? target.firmwareVersion { print(L("Firmware: %@", firmware)) }
        if let keychron = state.keychron {
            let active = keychron.activeLayer.map(String.init) ?? "?"
            let base = keychron.defaultLayer.map(String.init) ?? "-"
            print("Keychron: \(keychron.family.rawValue.uppercased()) · " + L("etkin katman %@, temel katman %@", active, base)
                  + (keychron.reportRateHz.map { " · \($0) Hz" } ?? ""))
        }
        // Read only: current lighting values, no set or save.
        for capability in state.lighting {
            let viaProtocol = state.viaProtocol, maxBrightness = state.vialRGBMaxBrightness
            let current = try? await session.perform { client in
                try client.lightingState(capability, viaProtocol: viaProtocol, vialRGBMax: maxBrightness)
            }
            let values = current.map { s in
                let effect = capability.effects.first { $0.id == s.effect }?.name ?? "\(s.effect)"
                return L("parlaklık %@, efekt %@, hız %@, renk %@/%@", "\(s.brightness)", effect, "\(s.speed)", "\(s.hue)", "\(s.saturation)")
            } ?? L("okunamadı")
            print(L("Işık: %@ (%@ efekt) — %@", capability.kind.title, "\(capability.effects.count)", values))
        }
        for layer in 0..<state.layerCount where onlyLayer == nil || onlyLayer == layer {
            print(L("\n— Katman %@", "\(layer)"))
            for (row, codes) in state.keymap.layers[layer].enumerated() {
                let names = codes.map { state.keycodes.name(for: $0).padding(toLength: 12, withPad: " ", startingAt: 0) }
                print(String(format: "%2d ", row) + names.joined(separator: " "))
            }
            if layer < state.keymap.encoders.count {
                for (index, encoder) in state.keymap.encoders[layer].enumerated() {
                    print(L("   encoder %@: ↺ %@  ↻ %@", "\(index)", "\(state.keycodes.name(for: encoder.ccw))", "\(state.keycodes.name(for: encoder.cw))"))
                }
            }
        }
    }

case "export":
    let target = device(at: args.dropFirst().first)
    guard args.count > 2 else { fail(L("Kullanım: kmctl export <n> <dosya.vil|dosya.json>")) }
    let url = URL(fileURLWithPath: args[2])
    runAsync {
        let (session, state) = try await loadState(target)
        defer { session.close() }
        let data = url.pathExtension.lowercased() == "vil"
            ? try LayoutFiles.vilData(keymap: state.keymap, keycodes: state.keycodes, uid: state.vialUID,
                                      viaProtocol: state.viaProtocol, vialProtocol: state.vialProtocol)
            : try LayoutFiles.viaData(keymap: state.keymap, keycodes: state.keycodes, name: state.definition.name,
                                      vendorProductID: target.vendorProductID)
        try data.write(to: url)
        print(L("Kaydedildi: %@", url.path))
    }

case "apply":
    let target = device(at: args.dropFirst().first)
    guard args.count > 2 else { fail(L("Kullanım: kmctl apply <n> <dosya>")) }
    let url = URL(fileURLWithPath: args[2])
    runAsync {
        let (session, state) = try await loadState(target)
        defer { session.close() }
        let profile = try LayoutFiles.importProfile(from: url, deviceKey: target.deviceKey, cols: state.definition.cols)
        let resolved = profile.resolve(onto: state.keymap, keycodes: state.keycodes)
        if !resolved.unknown.isEmpty { print(L("Tanınmayan keycode'lar atlandı: %@", "\(Set(resolved.unknown).sorted().joined(separator: ", "))")) }
        let count = try await session.write(resolved.keymap, over: state.keymap)
        print(L("%@ tuş güncellendi.", "\(count)"))
    }

case "firmware":
    let target = device(at: args.dropFirst().first)
    runAsync {
        var current = target.firmwareVersion
        if target.capability != .osRemap, let (session, state) = try? await loadState(target) {
            current = state.firmwareVersion ?? current
            session.close()
        }
        print(L("Yüklü: %@", "\(current ?? L("bilinmiyor"))"))
        guard target.vendorID == KeychronLauncher.vendorID else {
            print(L("Bu üretici için çevrimiçi güncelleme kaynağı yok."))
            return
        }
        guard let product = await KeychronLauncher.product(vendorProductID: target.vendorProductID), let latest = product.latest else {
            print(L("Keychron sunucusunda bilgi bulunamadı."))
            return
        }
        let status = FirmwareStatus(current: current, latest: latest, updatePage: KeychronLauncher.site)
        print(L("En yeni: %@ (%@) — %@", "\(latest.version)", "\(latest.date ?? "?")", "\(status.isUpdateAvailable ? L("GÜNCELLEME VAR") : L("güncel"))"))
        if let notes = latest.notes { print(notes) }
    }

case "remap":
    let target = device(at: args.dropFirst().first)
    guard args.count > 2 else {
        print(L("Hazır eşlemeler:"))
        for (index, preset) in HIDUtilRemapper.presets.enumerated() { print("  \(index): \(L(preset.name))") }
        print(L("  clear: eşlemeleri kaldır"))
        exit(0)
    }
    do {
        if args[2] == "clear" {
            try HIDUtilRemapper.clear(vendorID: target.vendorID, productID: target.productID)
            print(L("Eşlemeler kaldırıldı."))
        } else if let index = Int(args[2]), HIDUtilRemapper.presets.indices.contains(index) {
            let preset = HIDUtilRemapper.presets[index]
            try HIDUtilRemapper.apply(preset.remaps, vendorID: target.vendorID, productID: target.productID)
            print(L("Uygulandı: %@ (yeniden bağlanınca KeyMapper uygulaması tekrar uygular)", "\(L(preset.name))"))
        } else {
            fail(L("Bilinmeyen eşleme."))
        }
    } catch {
        fail(error.localizedDescription)
    }

default:
    let commands: [(String, String)] = [
        ("kmctl list", L("bağlı klavyeler")),
        ("kmctl dump <n> [layer]", L("keymap'i yazdır")),
        ("kmctl export <n> <file>", L(".vil (Vial) veya .json (VIA) olarak kaydet")),
        ("kmctl apply <n> <file>", L(".vil / VIA .json / profil dosyasını klavyeye yaz")),
        ("kmctl remap <n> [preset|clear]", L("macOS seviyesinde eşleme")),
        ("kmctl firmware <n>", L("firmware sürümü ve güncelleme kontrolü")),
        ("kmctl screen <n> [sync-time|frame-recovery]", L("ekranlı klavye: durum, saat eşitleme, LED kare kurtarma denemesi")),
    ]
    for (command, help) in commands { print(command.padding(toLength: 33, withPad: " ", startingAt: 0) + help) }
}
