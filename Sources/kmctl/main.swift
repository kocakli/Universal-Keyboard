import Foundation
import KeyMapperCore

// kmctl: command line companion of KeyMapper.
//   kmctl list                     connected keyboards
//   kmctl dump <n> [layer]         print the keymap of keyboard n
//   kmctl export <n> <file>        save the keymap as .vil (Vial) or .json (VIA)
//   kmctl apply <n> <file>         write a .vil / VIA .json / profile onto keyboard n
//   kmctl remap <n> <preset|clear> macOS level remap (non-programmable keyboards)

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(1)
}

func devices() -> [KeyboardDevice] { HIDMonitor().snapshot() }

func device(at argument: String?) -> KeyboardDevice {
    let list = devices()
    guard let argument, let index = Int(argument), list.indices.contains(index) else {
        fail("Geçersiz klavye numarası. 'kmctl list' ile listeleyin.")
    }
    return list[index]
}

func runAsync(_ body: @escaping () async throws -> Void) -> Never {
    Task {
        do { try await body(); exit(0) } catch { fail("Hata: \(error.localizedDescription)") }
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
    if list.isEmpty { print("Bağlı klavye yok.") }
    for (index, device) in list.enumerated() {
        let line = String(format: "[%d] %@  %@  %@  %@  (%@)", index, device.displayName, device.deviceKey,
                          device.transportLabel, device.capability.title, device.brand.name)
        print(line)
    }

case "dump":
    let target = device(at: args.dropFirst().first)
    let onlyLayer = args.count > 2 ? Int(args[2]) : nil
    runAsync {
        let (session, state) = try await loadState(target)
        defer { session.close() }
        print("\(state.definition.name) — VIA protokol \(state.viaProtocol)\(state.vialProtocol.map { ", Vial protokol \($0)" } ?? ""), keycode \(state.keycodes.version.rawValue)")
        print("Matris \(state.definition.rows)x\(state.definition.cols), \(state.layerCount) katman, \(state.definition.keys.count) tuş, kaynak: \(state.definition.source.title)")
        for layer in 0..<state.layerCount where onlyLayer == nil || onlyLayer == layer {
            print("\n— Katman \(layer)")
            for (row, codes) in state.keymap.layers[layer].enumerated() {
                let names = codes.map { state.keycodes.name(for: $0).padding(toLength: 12, withPad: " ", startingAt: 0) }
                print(String(format: "%2d ", row) + names.joined(separator: " "))
            }
            if layer < state.keymap.encoders.count {
                for (index, encoder) in state.keymap.encoders[layer].enumerated() {
                    print("   encoder \(index): ↺ \(state.keycodes.name(for: encoder.ccw))  ↻ \(state.keycodes.name(for: encoder.cw))")
                }
            }
        }
    }

case "export":
    let target = device(at: args.dropFirst().first)
    guard args.count > 2 else { fail("Kullanım: kmctl export <n> <dosya.vil|dosya.json>") }
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
        print("Kaydedildi: \(url.path)")
    }

case "apply":
    let target = device(at: args.dropFirst().first)
    guard args.count > 2 else { fail("Kullanım: kmctl apply <n> <dosya>") }
    let url = URL(fileURLWithPath: args[2])
    runAsync {
        let (session, state) = try await loadState(target)
        defer { session.close() }
        let profile = try LayoutFiles.importProfile(from: url, deviceKey: target.deviceKey, cols: state.definition.cols)
        let resolved = profile.resolve(onto: state.keymap, keycodes: state.keycodes)
        if !resolved.unknown.isEmpty { print("Tanınmayan keycode'lar atlandı: \(Set(resolved.unknown).sorted().joined(separator: ", "))") }
        let count = try await session.write(resolved.keymap, over: state.keymap)
        print("\(count) tuş güncellendi.")
    }

case "remap":
    let target = device(at: args.dropFirst().first)
    guard args.count > 2 else {
        print("Hazır eşlemeler:")
        for (index, preset) in HIDUtilRemapper.presets.enumerated() { print("  \(index): \(preset.name)") }
        print("  clear: eşlemeleri kaldır")
        exit(0)
    }
    do {
        if args[2] == "clear" {
            try HIDUtilRemapper.clear(vendorID: target.vendorID, productID: target.productID)
            print("Eşlemeler kaldırıldı.")
        } else if let index = Int(args[2]), HIDUtilRemapper.presets.indices.contains(index) {
            let preset = HIDUtilRemapper.presets[index]
            try HIDUtilRemapper.apply(preset.remaps, vendorID: target.vendorID, productID: target.productID)
            print("Uygulandı: \(preset.name) (yeniden bağlanınca KeyMapper uygulaması tekrar uygular)")
        } else {
            fail("Bilinmeyen eşleme.")
        }
    } catch {
        fail(error.localizedDescription)
    }

default:
    print("""
    kmctl list                       bağlı klavyeler
    kmctl dump <n> [katman]          keymap'i yazdır
    kmctl export <n> <dosya>         .vil (Vial) veya .json (VIA) olarak kaydet
    kmctl apply <n> <dosya>          .vil / VIA .json / profil dosyasını klavyeye yaz
    kmctl remap <n> [hazır|clear]    macOS seviyesinde eşleme
    """)
}
