import Foundation
import IOKit
import IOKit.hid

/// Watches the IORegistry for keyboards and QMK raw HID interfaces.
///
/// The manager is never opened, so enumeration does not need the
/// Input Monitoring permission. Callbacks are delivered on the main run loop.
public final class HIDMonitor {
    public var onChange: (([KeyboardDevice]) -> Void)?

    private let manager: IOHIDManager
    private var interfaces: [UInt64: HIDInterfaceInfo] = [:]
    private var started = false

    public init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [[String: Any]] = [
            [kIOHIDDeviceUsagePageKey: 0x01, kIOHIDDeviceUsageKey: 0x06],
            [kIOHIDDeviceUsagePageKey: 0xFF60, kIOHIDDeviceUsageKey: 0x61],
            // Screen keyboards' vendor channels (LEOBOG AMG65 by cable).
            [kIOHIDDeviceUsagePageKey: 0xFF68, kIOHIDDeviceUsageKey: 0x61],
        ]
        IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)
    }

    deinit { stop() }

    public func start() {
        guard !started else { return }
        started = true
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            guard let context else { return }
            Unmanaged<HIDMonitor>.fromOpaque(context).takeUnretainedValue().added(device)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            guard let context else { return }
            Unmanaged<HIDMonitor>.fromOpaque(context).takeUnretainedValue().removed(device)
        }, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    }

    public func stop() {
        guard started else { return }
        started = false
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    }

    /// Synchronous snapshot, useful for the CLI (no run loop needed).
    public func snapshot() -> [KeyboardDevice] {
        if let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> {
            for device in set {
                if let info = HIDMonitor.info(for: device) { interfaces[info.registryID] = info }
            }
        }
        return devices
    }

    public var devices: [KeyboardDevice] { HIDMonitor.group(Array(interfaces.values)) }

    private func added(_ device: IOHIDDevice) {
        guard let info = HIDMonitor.info(for: device) else { return }
        interfaces[info.registryID] = info
        onChange?(devices)
    }

    private func removed(_ device: IOHIDDevice) {
        let service = IOHIDDeviceGetService(device)
        var entryID: UInt64 = 0
        if service != IO_OBJECT_NULL, IORegistryEntryGetRegistryEntryID(service, &entryID) == KERN_SUCCESS {
            interfaces.removeValue(forKey: entryID)
        } else {
            // Service already gone: drop interfaces that no longer exist in the registry.
            interfaces = interfaces.filter { HIDMonitor.serviceExists($0.key) }
        }
        onChange?(devices)
    }

    // MARK: - Helpers

    static func serviceExists(_ registryID: UInt64) -> Bool {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IORegistryEntryIDMatching(registryID))
        guard service != IO_OBJECT_NULL else { return false }
        IOObjectRelease(service)
        return true
    }

    static func info(for device: IOHIDDevice) -> HIDInterfaceInfo? {
        let service = IOHIDDeviceGetService(device)
        var entryID: UInt64 = 0
        guard service != IO_OBJECT_NULL, IORegistryEntryGetRegistryEntryID(service, &entryID) == KERN_SUCCESS else { return nil }

        func int(_ key: String) -> Int { (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue ?? 0 }
        func string(_ key: String) -> String { (IOHIDDeviceGetProperty(device, key as CFString) as? String) ?? "" }

        var pairs: [HIDInterfaceInfo.UsagePair] = []
        if let raw = IOHIDDeviceGetProperty(device, kIOHIDDeviceUsagePairsKey as CFString) as? [[String: Any]] {
            for pair in raw {
                let page = (pair[kIOHIDDeviceUsagePageKey] as? NSNumber)?.intValue ?? 0
                let usage = (pair[kIOHIDDeviceUsageKey] as? NSNumber)?.intValue ?? 0
                pairs.append(.init(page: page, usage: usage))
            }
        }
        if pairs.isEmpty {
            pairs.append(.init(page: int(kIOHIDPrimaryUsagePageKey), usage: int(kIOHIDPrimaryUsageKey)))
        }
        let builtIn = (IOHIDDeviceGetProperty(device, kIOHIDBuiltInKey as CFString) as? NSNumber)?.boolValue ?? false

        return HIDInterfaceInfo(
            registryID: entryID,
            vendorID: int(kIOHIDVendorIDKey),
            productID: int(kIOHIDProductIDKey),
            usagePairs: pairs,
            product: string(kIOHIDProductKey),
            manufacturer: string(kIOHIDManufacturerKey),
            serial: string(kIOHIDSerialNumberKey),
            transport: string(kIOHIDTransportKey),
            locationID: int(kIOHIDLocationIDKey),
            builtIn: builtIn,
            versionNumber: int(kIOHIDVersionNumberKey)
        )
    }

    /// Apple ships no QMK firmware: a 0xFF60 interface under Apple's vendor ID belongs to a clone that borrows
    /// the ID for a Mac layout (e.g. the LEOBOG AMG65 2.4 GHz dongle, 05AC:024F), which speaks its own
    /// checksummed protocol. Sending it VIA commands would be guesswork, so it is not treated as VIA.
    static func spoofsAppleID(_ info: HIDInterfaceInfo) -> Bool {
        info.vendorID == 0x05AC || info.vendorID == 0x004C
    }

    /// Groups interfaces that belong to the same physical keyboard.
    static func group(_ interfaces: [HIDInterfaceInfo]) -> [KeyboardDevice] {
        // Built-in keyboards (and anonymous VID/PID 0 devices) cannot be targeted reliably.
        let candidates = interfaces.filter { !$0.builtIn && !($0.vendorID == 0 && $0.productID == 0) }
        let grouped = Dictionary(grouping: candidates) { info in
            String(format: "%04X:%04X:%08X", info.vendorID, info.productID, info.locationID)
        }
        return grouped.compactMap { key, members -> KeyboardDevice? in
            // A group needs at least one keyboard or raw HID interface.
            guard members.contains(where: { $0.isKeyboard || $0.isRawHID }) else { return nil }
            let sorted = members.sorted { $0.registryID < $1.registryID }
            let primary = sorted.first { $0.isKeyboard } ?? sorted[0]
            let raw = sorted.first { $0.isRawHID && !spoofsAppleID($0) }
            let serial = sorted.map(\.serial).first { !$0.isEmpty } ?? ""
            var device = KeyboardDevice(
                id: key,
                vendorID: primary.vendorID,
                productID: primary.productID,
                name: primary.product.isEmpty ? (raw?.product ?? "") : primary.product,
                manufacturer: sorted.map(\.manufacturer).first { !$0.isEmpty } ?? "",
                serial: serial,
                transport: primary.transport,
                rawHIDRegistryID: raw?.registryID,
                interfaceRegistryIDs: sorted.map(\.registryID)
            )
            device.versionNumber = primary.versionNumber
            device.screenKeyboard = sorted.lazy.compactMap(ScreenKeyboardCatalog.channel(for:)).first
            return device
        }
        .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }
}
