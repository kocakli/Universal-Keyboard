import Foundation
import KeyMapperCore

/// Backlight / RGB control for VIA and Vial keyboards. Changes go to the keyboard's RAM right away
/// (the keyboard shows them, but forgets them when unplugged); `saveLighting` writes them to EEPROM.
extension AppModel {
    func lightingCapabilities(for device: KeyboardDevice) -> [LightingCapability] {
        states[device.id]?.lighting ?? []
    }

    /// Reads the current values of every lighting system the keyboard has.
    func loadLighting(_ device: KeyboardDevice) async {
        guard let state = states[device.id], let session = sessions[device.id], !session.isClosed, !state.lighting.isEmpty else { return }
        let capabilities = state.lighting
        let viaProtocol = state.viaProtocol, maxBrightness = state.vialRGBMaxBrightness
        do {
            let values = try await session.perform { client -> [LightingKind: LightingState] in
                var result: [LightingKind: LightingState] = [:]
                for capability in capabilities {
                    result[capability.kind] = try client.lightingState(capability, viaProtocol: viaProtocol, vialRGBMax: maxBrightness)
                }
                return result
            }
            lightingValues[device.id] = values
            savedLighting[device.id] = values
        } catch {
            errorMessage = L("Işık ayarları okunamadı: %@", error.localizedDescription)
        }
    }

    /// Shows the change on the keyboard; slider drags are coalesced so the link isn't flooded.
    func setLighting(_ value: LightingState, field: LightingField, kind: LightingKind, device: KeyboardDevice) {
        lightingValues[device.id, default: [:]][kind] = value
        let key = "\(device.id)#\(kind.rawValue)#\(field)"
        lightingSends[key]?.cancel()
        lightingSends[key] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(60))
            guard !Task.isCancelled, let self else { return }
            await self.sendLighting(field: field, kind: kind, device: device)
        }
    }

    private func sendLighting(field: LightingField, kind: LightingKind, device: KeyboardDevice) async {
        guard let state = states[device.id], let session = sessions[device.id], !session.isClosed,
              let latest = lightingValues[device.id]?[kind] else { return }
        let viaProtocol = state.viaProtocol, maxBrightness = state.vialRGBMaxBrightness
        do {
            try await session.perform { client in
                try client.setLighting(kind, field, latest, viaProtocol: viaProtocol, vialRGBMax: maxBrightness)
            }
        } catch {
            errorMessage = L("Işık ayarı gönderilemedi: %@", error.localizedDescription)
        }
    }

    func hasUnsavedLighting(_ kind: LightingKind, device: KeyboardDevice) -> Bool {
        guard let current = lightingValues[device.id]?[kind] else { return false }
        return current != savedLighting[device.id]?[kind]
    }

    /// Writes the current values to the keyboard's EEPROM so they survive unplugging.
    func saveLighting(_ kind: LightingKind, device: KeyboardDevice) async {
        guard let state = states[device.id], let session = sessions[device.id], !session.isClosed else { return }
        let viaProtocol = state.viaProtocol
        do {
            try await session.perform { client in try client.saveLighting(kind, viaProtocol: viaProtocol) }
            savedLighting[device.id, default: [:]][kind] = lightingValues[device.id]?[kind]
            notice = L("Işık ayarları klavyeye kaydedildi.")
        } catch {
            errorMessage = L("Işık ayarları kaydedilemedi: %@", error.localizedDescription)
        }
    }

    /// Puts back the values last read from or saved to the keyboard.
    func revertLighting(_ kind: LightingKind, device: KeyboardDevice) async {
        guard let saved = savedLighting[device.id]?[kind], let state = states[device.id],
              let session = sessions[device.id], !session.isClosed else { return }
        lightingValues[device.id, default: [:]][kind] = saved
        let viaProtocol = state.viaProtocol, maxBrightness = state.vialRGBMaxBrightness
        do {
            try await session.perform { client in
                for field in LightingField.allCases {
                    try client.setLighting(kind, field, saved, viaProtocol: viaProtocol, vialRGBMax: maxBrightness)
                    if kind == .vialRGB { break } // one packet carries every VialRGB value
                }
            }
        } catch {
            errorMessage = L("Işık ayarı gönderilemedi: %@", error.localizedDescription)
        }
    }
}
