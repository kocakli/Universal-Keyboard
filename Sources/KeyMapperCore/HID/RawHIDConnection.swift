import Foundation
import IOKit
import IOKit.hid

public enum HIDError: LocalizedError, Equatable {
    case deviceNotFound
    case openFailed(Int32)
    case writeFailed(Int32)
    case timeout
    case disconnected
    case unexpectedResponse(String)

    public var errorDescription: String? {
        switch self {
        case .deviceNotFound: return L("Cihaz bulunamadı (bağlantı kesilmiş olabilir).")
        case let .openFailed(code): return L("HID arayüzü açılamadı (0x%@).", "\(String(UInt32(bitPattern: code), radix: 16))")
        case let .writeFailed(code): return L("Klavyeye yazılamadı (0x%@).", "\(String(UInt32(bitPattern: code), radix: 16))")
        case .timeout: return L("Klavye yanıt vermedi (zaman aşımı).")
        case .disconnected: return L("Klavyenin bağlantısı kesildi.")
        case let .unexpectedResponse(detail): return L("Beklenmeyen yanıt: %@", "\(detail)")
        }
    }
}

/// Request/response channel over a QMK raw HID interface (32 byte reports, no report ID).
public final class RawHIDConnection: @unchecked Sendable {
    public static let reportSize = 32

    private let device: IOHIDDevice
    private let inputQueue = DispatchQueue(label: "keymapper.rawhid.input")
    private let reportBuffer: UnsafeMutablePointer<UInt8>
    private let responseSignal = DispatchSemaphore(value: 0)
    private let cancelSignal = DispatchSemaphore(value: 0)
    private let requestLock = NSLock()
    private let stateLock = NSLock()
    private var awaiting = false
    private var expectedEcho: UInt8?
    private var response: [UInt8] = []
    private var unsolicited: (@Sendable ([UInt8]) -> Void)?
    private var closed = false
    private var removed = false

    public init(registryID: UInt64) throws {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IORegistryEntryIDMatching(registryID))
        guard service != IO_OBJECT_NULL else { throw HIDError.deviceNotFound }
        defer { IOObjectRelease(service) }
        guard let device = IOHIDDeviceCreate(kCFAllocatorDefault, service) else { throw HIDError.deviceNotFound }
        self.device = device

        let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else { throw HIDError.openFailed(result) }

        reportBuffer = .allocate(capacity: 64)
        reportBuffer.initialize(repeating: 0, count: 64)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, reportBuffer, 64, { context, _, _, _, _, report, length in
            guard let context else { return }
            let connection = Unmanaged<RawHIDConnection>.fromOpaque(context).takeUnretainedValue()
            connection.received(Array(UnsafeBufferPointer(start: report, count: length)))
        }, context)
        IOHIDDeviceRegisterRemovalCallback(device, { context, _, _ in
            guard let context else { return }
            Unmanaged<RawHIDConnection>.fromOpaque(context).takeUnretainedValue().markRemoved()
        }, context)
        IOHIDDeviceSetDispatchQueue(device, inputQueue)
        IOHIDDeviceSetCancelHandler(device) { [cancelSignal] in cancelSignal.signal() }
        IOHIDDeviceActivate(device)
    }

    deinit {
        close()
        reportBuffer.deallocate()
    }

    /// True once the connection was closed or the keyboard went away.
    public var isClosed: Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return closed || removed
    }

    public func close() {
        stateLock.lock()
        let wasClosed = closed
        closed = true
        stateLock.unlock()
        guard !wasClosed else { return }
        IOHIDDeviceCancel(device)
        _ = cancelSignal.wait(timeout: .now() + 1)
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        responseSignal.signal()
    }

    /// Called on the HID queue for input reports nobody was waiting for (e.g. Keychron layer pushes).
    public func setUnsolicitedHandler(_ handler: (@Sendable ([UInt8]) -> Void)?) {
        stateLock.lock(); unsolicited = handler; stateLock.unlock()
    }

    /// Sends one 32 byte report and waits for the reply. With `expecting`, only a report whose
    /// first byte echoes that id (or 0xFF, "unhandled") counts; anything else is passed on as unsolicited.
    public func exchange(_ request: [UInt8], timeout: TimeInterval = 1.0, retries: Int = 2, expecting: UInt8? = nil) throws -> [UInt8] {
        requestLock.lock(); defer { requestLock.unlock() }
        var attempt = 0
        while true {
            do {
                return try exchangeOnce(request, timeout: timeout, expecting: expecting)
            } catch HIDError.timeout where attempt < retries {
                attempt += 1
            }
        }
    }

    private func exchangeOnce(_ request: [UInt8], timeout: TimeInterval, expecting: UInt8?) throws -> [UInt8] {
        if isClosed { throw HIDError.disconnected }
        var report = [UInt8](repeating: 0, count: Self.reportSize)
        for (index, byte) in request.prefix(Self.reportSize).enumerated() { report[index] = byte }

        // Drop any stale report before sending.
        while responseSignal.wait(timeout: .now()) == .success {}
        stateLock.lock(); awaiting = true; expectedEcho = expecting; response = []; stateLock.unlock()

        let result = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0, report, report.count)
        guard result == kIOReturnSuccess else {
            stateLock.lock(); awaiting = false; stateLock.unlock()
            if isClosed { throw HIDError.disconnected }
            throw HIDError.writeFailed(result)
        }
        if responseSignal.wait(timeout: .now() + timeout) == .timedOut {
            stateLock.lock(); awaiting = false; stateLock.unlock()
            throw HIDError.timeout
        }
        stateLock.lock(); defer { stateLock.unlock() }
        if (closed || removed) && response.isEmpty { throw HIDError.disconnected }
        var padded = response
        if padded.count < Self.reportSize { padded += [UInt8](repeating: 0, count: Self.reportSize - padded.count) }
        return padded
    }

    private func received(_ report: [UInt8]) {
        stateLock.lock()
        let isReply = awaiting && (expectedEcho.map { report.first == $0 || report.first == 0xFF } ?? true)
        guard isReply else {
            let handler = unsolicited
            stateLock.unlock()
            handler?(report)
            return
        }
        awaiting = false
        response = report
        stateLock.unlock()
        responseSignal.signal()
    }

    private func markRemoved() {
        stateLock.lock(); removed = true; stateLock.unlock()
        responseSignal.signal()
    }
}
