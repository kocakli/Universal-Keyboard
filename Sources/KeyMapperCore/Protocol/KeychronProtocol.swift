import Foundation

/// Read-only parts of Keychron's raw HID extensions (Keychron Launcher protocol, 0xA0–0xA7).
/// Commands echo their id in byte 0. QMK boards (keychron/qmk_firmware) and ZMK based devices
/// (keychron/zmk "launcher", e.g. Ultra series and likely the Nape Pro) lay the replies out differently.
/// Writes (settings, DFU, factory test) are deliberately not implemented.
public struct KeychronStatus: Sendable, Equatable {
    public enum Family: String, Sendable { case qmk, zmk }

    public var family: Family
    /// Layer the device is typing on right now (highest active layer).
    public var activeLayer: Int?
    /// Base layer chosen by the Mac/Windows switch or key combo (QMK only).
    public var defaultLayer: Int?
    public var bluetooth = false
    public var wireless24G = false
    public var reportRateHz: Int?

    public init(family: Family, activeLayer: Int? = nil, defaultLayer: Int? = nil) {
        self.family = family
        self.activeLayer = activeLayer
        self.defaultLayer = defaultLayer
    }

    /// The layer a key has to be on to work without holding a layer key.
    public var baseLayer: Int? { defaultLayer ?? activeLayer }
}

public enum KeychronProtocol {
    static let protocolVersion: UInt8 = 0xA0
    static let firmwareVersion: UInt8 = 0xA1
    static let supportFeature: UInt8 = 0xA2
    static let layer: UInt8 = 0xA3
    static let misc: UInt8 = 0xA7
    static let miscReportRateGet: UInt8 = 0x0D

    /// Report ids Keychron firmware may push without being asked (layer changes, factory reset, report rate).
    public static func isUnsolicited(_ report: [UInt8]) -> Bool {
        guard let first = report.first else { return false }
        return first == layer || first == misc
    }

    public static func family(protocolReply r: [UInt8]) -> KeychronStatus.Family? {
        guard r.count > 1, r[0] == protocolVersion else { return nil }
        switch r[1] {
        case 2: return .qmk
        case 1: return .zmk
        default: return nil
        }
    }

    /// QMK: [A3, default, active]; ZMK: [A3, active].
    public static func layers(reply r: [UInt8], family: KeychronStatus.Family) -> (default: Int?, active: Int?) {
        guard r.count > 2, r[0] == layer else { return (nil, nil) }
        let valid = { (value: UInt8) -> Int? in Int(value) < VIAClient.maxLayers ? Int(value) : nil }
        switch family {
        case .qmk: return (valid(r[1]), valid(r[2]))
        case .zmk: return (nil, valid(r[1]))
        }
    }

    /// QMK: [A2, 0, featuresLow, featuresHigh]; ZMK: [A2, features].
    public static func features(reply r: [UInt8], family: KeychronStatus.Family) -> (bluetooth: Bool, wireless24G: Bool) {
        guard r.count > 3, r[0] == supportFeature else { return (false, false) }
        let bits = family == .qmk ? r[2] : r[1]
        return (bits & 0x02 != 0, bits & 0x04 != 0)
    }

    /// QMK: [A7, 0D, status, divisor]; divisor 0 = 8 kHz … 6 = 125 Hz.
    public static func reportRate(reply r: [UInt8]) -> Int? {
        guard r.count > 3, r[0] == misc, r[1] == miscReportRateGet, r[2] == 0 else { return nil }
        let rates = [8000, 4000, 2000, 1000, 500, 250, 125]
        return Int(r[3]) < rates.count ? rates[Int(r[3])] : nil
    }
}

extension VIAClient {
    /// Short, single-try request for Keychron extensions; nil when the device does not answer it.
    private func keychronRequest(_ request: [UInt8]) -> [UInt8]? {
        guard let reply = try? connection.exchange(request, timeout: 0.4, retries: 0, expecting: request[0]),
              reply[0] == request[0] else { return nil }
        return reply
    }

    /// Keychron firmware version string (raw HID 0xA1), e.g. "v1.2.1 2025-06-17-10:09:52".
    public func keychronFirmwareVersion() throws -> String? {
        guard let r = keychronRequest([KeychronProtocol.firmwareVersion]) else { return nil }
        let bytes = r.dropFirst().prefix { $0 != 0 }
        let text = String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty || !text.unicodeScalars.allSatisfy({ $0.isASCII && $0.value >= 0x20 }) ? nil : text
    }

    /// Reads family, layers, radios and report rate. Read only; nil for non-Keychron firmware.
    public func keychronStatus() -> KeychronStatus? {
        guard let reply = keychronRequest([KeychronProtocol.protocolVersion]),
              let family = KeychronProtocol.family(protocolReply: reply) else { return nil }
        var status = KeychronStatus(family: family)
        if let r = keychronRequest([KeychronProtocol.layer]) {
            (status.defaultLayer, status.activeLayer) = KeychronProtocol.layers(reply: r, family: family)
        }
        if let r = keychronRequest([KeychronProtocol.supportFeature]) {
            (status.bluetooth, status.wireless24G) = KeychronProtocol.features(reply: r, family: family)
        }
        // ZMK builds answer 0D with a different layout or not at all.
        if family == .qmk, let r = keychronRequest([KeychronProtocol.misc, KeychronProtocol.miscReportRateGet]) {
            status.reportRateHz = KeychronProtocol.reportRate(reply: r)
        }
        return status
    }
}
