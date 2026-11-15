import Foundation
import IOKit
import IOUSBHost

// LEOBOG AMG65 upload channel for LCD images and LED-matrix animations.
// Ported from AMG65 Studio (github.com/kocakli/amg65-studio), which builds on aumbro/leobog_amg65_rgb (MIT).
// Studio wrote the blocks with libusb; this uses Apple's IOUSBHost framework instead.

/// Writes 4096 byte upload blocks to an AMG65 (USB interface 3 of 0C45:800A, OUT endpoint 0x06).
///
/// The interface is found by the USB location of the vendor HID interface, so the blocks always reach the same
/// physical keyboard as the HID packets that announce them. The acknowledgement of each block arrives on the HID
/// interface (`AMG65Link.upload`).
public final class AMG65BulkChannel: @unchecked Sendable {
    public static let vendorID = 0x0C45
    public static let productID = 0x800A
    public static let interfaceNumber = 3
    public static let endpointAddress = 0x06
    /// Studio's libusb timeout for one block.
    public static let writeTimeout: TimeInterval = 2

    private let interface: IOUSBHostInterface
    private let pipe: IOUSBHostPipe

    /// Opens interface 3 of the AMG65 whose USB `locationID` is `locationID` (the vendor HID interface's
    /// `LocationID`). Throws `HIDError.deviceNotFound` when there is no such interface and `HIDError.openFailed`
    /// when it or its endpoint can't be opened; nothing is sent to the keyboard in either case.
    public init(locationID: UInt32) throws {
        guard let service = Self.service(locationID: locationID) else { throw HIDError.deviceNotFound }
        defer { IOObjectRelease(service) }
        // Completions are delivered on this queue while the caller waits on its own.
        let queue = DispatchQueue(label: "keymapper.amg65.bulk")
        let interface: IOUSBHostInterface
        do {
            interface = try IOUSBHostInterface(__ioService: service, options: [], queue: queue, interestHandler: nil)
        } catch {
            throw HIDError.openFailed(Self.code(of: error))
        }
        do {
            pipe = try interface.copyPipe(withAddress: Self.endpointAddress)
        } catch {
            interface.destroy()
            throw HIDError.openFailed(Self.code(of: error))
        }
        self.interface = interface
    }

    deinit { close() }

    /// Releases the interface. Calling it again has no effect.
    public func close() {
        interface.destroy()
    }

    /// Writes one block and waits until it was transferred, at most `timeout`. The request is queued without a
    /// kernel timeout (interrupt endpoints don't take one); a request still pending after `timeout` is aborted.
    /// Throws `HIDError.timeout` or `HIDError.writeFailed`, also when fewer bytes than the block were transferred.
    public func write(_ block: [UInt8], timeout: TimeInterval = AMG65BulkChannel.writeTimeout) throws {
        let data = NSMutableData(bytes: block, length: block.count)
        let outcome = Outcome()
        // The buffer stays alive until the request completed or was aborted.
        try withExtendedLifetime(data) {
            do {
                try pipe.enqueueIORequest(with: data, completionTimeout: 0) { status, transferred in
                    outcome.finish(status: status, transferred: transferred)
                }
            } catch {
                throw HIDError.writeFailed(Self.code(of: error))
            }
            guard outcome.wait(timeout: timeout) else {
                try? pipe.__abort(with: .synchronous)
                _ = outcome.wait(timeout: 1)
                throw HIDError.timeout
            }
        }
        let (status, transferred) = outcome.result
        guard status == kIOReturnSuccess else { throw HIDError.writeFailed(status) }
        guard transferred == block.count else { throw HIDError.writeFailed(Self.underrun) }
    }

    // MARK: Lookup

    /// The first IOUSBHostInterface that `matches` the location. Only registry properties are read.
    static func service(locationID: UInt32) -> io_service_t? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOUSBHostInterface"), &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }
        while true {
            let service = IOIteratorNext(iterator)
            guard service != IO_OBJECT_NULL else { return nil }
            var properties: [String: Any] = [:]
            for key in ["idVendor", "idProduct", "bInterfaceNumber", "locationID"] {
                if let value = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() {
                    properties[key] = value
                }
            }
            if matches(properties, locationID: locationID) { return service }
            IOObjectRelease(service)
        }
    }

    /// Interface 3 of an AMG65 (0C45:800A) at `locationID`.
    static func matches(_ properties: [String: Any], locationID: UInt32) -> Bool {
        func number(_ key: String) -> Int64? { (properties[key] as? NSNumber)?.int64Value }
        return number("idVendor") == Int64(vendorID) && number("idProduct") == Int64(productID)
            && number("bInterfaceNumber") == Int64(interfaceNumber)
            && number("locationID").map { UInt32(truncatingIfNeeded: $0) } == locationID
    }

    // MARK: Helpers

    /// kIOReturnUnderrun (iokit_common_err(0x2e8)).
    static let underrun = Int32(bitPattern: 0xE000_02E8)

    /// IOUSBHost reports IOReturn codes as NSError codes.
    private static func code(of error: Error) -> Int32 {
        Int32(truncatingIfNeeded: (error as NSError).code)
    }

    private final class Outcome: @unchecked Sendable {
        private let lock = NSLock()
        private let done = DispatchSemaphore(value: 0)
        private var status: IOReturn = kIOReturnSuccess
        private var transferred = 0

        func finish(status: IOReturn, transferred: Int) {
            lock.lock()
            self.status = status
            self.transferred = transferred
            lock.unlock()
            done.signal()
        }

        func wait(timeout: TimeInterval) -> Bool { done.wait(timeout: .now() + timeout) == .success }

        var result: (IOReturn, Int) {
            lock.lock(); defer { lock.unlock() }
            return (status, transferred)
        }
    }
}
