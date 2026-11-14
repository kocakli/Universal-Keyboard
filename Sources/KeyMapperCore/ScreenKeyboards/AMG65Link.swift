import Darwin
import Foundation

public enum ScreenKeyboardError: LocalizedError, Equatable {
    /// Another program (e.g. AMG65 Studio's bridge) holds the keyboard's vendor channel.
    case busy
    /// An earlier transaction stopped half way; nothing is sent until the keyboard is reconnected.
    case needsReconnect
    /// The keyboard answered a packet with a failure status.
    case rejected(step: String, status: UInt8)
    /// No (or a wrong) acknowledgement for a packet.
    case noAcknowledgement(step: String)
    /// The end reply's checksum differs from the data that was sent.
    case checksumMismatch
    /// The feature needs the USB cable (the receiver doesn't carry it).
    case needsCable
    /// The matrix was busy and dropped a live frame (RAM only); the next frame may be sent after a pause.
    case frameBusy

    public var errorDescription: String? {
        switch self {
        case .busy:
            return L("Klavyeyi şu an başka bir uygulama kullanıyor (ör. AMG65 Studio). O uygulamayı kapatıp tekrar deneyin.")
        case .needsReconnect:
            return L("Önceki işlem yarıda kaldığı için klavyeye gönderim durduruldu. Kabloyu çıkarıp yeniden takın.")
        case let .rejected(step, status):
            return L("Klavye \"%@\" paketini reddetti (durum 0x%@); gönderim durduruldu. Kabloyu çıkarıp yeniden takın.",
                     step, String(format: "%02X", status))
        case let .noAcknowledgement(step):
            return L("Klavye \"%@\" paketini onaylamadı; gönderim durduruldu. Kabloyu çıkarıp yeniden takın.", step)
        case .checksumMismatch:
            return L("Klavyenin sağlama toplamı gönderilen veriyle eşleşmedi; gönderim durduruldu. Kabloyu çıkarıp yeniden takın.")
        case .needsCable:
            return L("Bu özellik için klavyeyi USB kablosuyla bağlayın.")
        case .frameBusy:
            return L("LED ekran meşguldü; kare atlandı.")
        }
    }
}

/// Serialised transactions with a LEOBOG AMG65 over its vendor HID interface.
///
/// Safety rules (from AMG65 Studio, verified on the keyboard):
/// - every packet must be acknowledged; a failure status, a missing or wrong acknowledgement or a checksum
///   mismatch stops all sending until the keyboard is reconnected (a new IORegistry id), and the stop survives
///   an app restart;
/// - no packet is ever retried, because a repeated packet would corrupt the transaction;
/// - the per-user lock `/private/tmp/amg65-hid-<uid>.lock` is held while connected, the same lock AMG65 Studio
///   takes, so two programs never interleave packets.
public final class AMG65Link: @unchecked Sendable {
    public let channel: ScreenKeyboardChannel
    private let connection: AMG65Transport
    private let openBulkChannel: (UInt32) throws -> AMG65BlockWriter
    /// The shared lock's file descriptor; -1 for the test transport.
    private let lock: Int32
    private var liveFramesActive = false
    private var lastFrame = Date.distantPast

    public init(channel: ScreenKeyboardChannel) throws {
        guard !Self.isBlocked(channel.registryID) else { throw ScreenKeyboardError.needsReconnect }
        let fd = open("/private/tmp/amg65-hid-\(getuid()).lock", O_RDWR | O_CREAT | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw ScreenKeyboardError.busy }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(fd)
            throw ScreenKeyboardError.busy
        }
        do {
            connection = try RawHIDConnection(registryID: channel.registryID, reportSize: channel.reportSize)
        } catch {
            Darwin.close(fd)
            throw error
        }
        self.channel = channel
        self.lock = fd
        self.openBulkChannel = { try AMG65BulkChannel(locationID: $0) }
    }

    /// A link over another transport (tests). It takes no lock and opens no device.
    init(channel: ScreenKeyboardChannel, transport: AMG65Transport, openBulkChannel: @escaping (UInt32) throws -> AMG65BlockWriter) {
        self.channel = channel
        self.connection = transport
        self.openBulkChannel = openBulkChannel
        self.lock = -1
    }

    deinit { close() }

    private var closed = false

    public func close() {
        guard !closed else { return }
        closed = true
        if liveFramesActive { try? run(AMG65Protocol.stopLiveFrames) }
        connection.close()
        if lock >= 0 { Darwin.close(lock) }
    }

    public var isClosed: Bool { closed || connection.isClosed }

    // MARK: Cable

    /// Runs one transaction. Live frames are ended first when something else is sent.
    public func run(_ steps: [AMG65Protocol.Step]) throws {
        guard channel.link == .wired else { throw ScreenKeyboardError.needsCable }
        guard !Self.isBlocked(channel.registryID) else { throw ScreenKeyboardError.needsReconnect }
        let isFrame = steps.contains { $0.kind == .command && $0.bytes[1] == 0x35 }
        let isStop = steps == AMG65Protocol.stopLiveFrames
        if liveFramesActive && !isFrame && !isStop {
            try transact(AMG65Protocol.stopLiveFrames, liveFrame: false)
            liveFramesActive = false
        }
        do {
            try transact(steps, liveFrame: isFrame)
        } catch ScreenKeyboardError.frameBusy {
            liveFramesActive = true
            throw ScreenKeyboardError.frameBusy
        }
        if isFrame { liveFramesActive = true }
        if isStop { liveFramesActive = false }
    }

    /// Sends one live LED-matrix frame, paced to what the keyboard acknowledges reliably.
    public func showFrame(_ pixels: [RGB24]) throws {
        let wait = AMG65Protocol.minimumFrameInterval - Date().timeIntervalSince(lastFrame)
        if wait > 0 { Thread.sleep(forTimeInterval: wait) }
        try run(AMG65Protocol.liveFrame(pixels))
        lastFrame = Date()
    }

    /// Hands the LED matrix back to the keyboard's own animation.
    public func endFrames() throws {
        guard liveFramesActive else { return }
        try run(AMG65Protocol.stopLiveFrames)
    }

    /// `liveFrame`: a busy status (0xFF) on the frame's end packet drops that frame without stopping the
    /// link. AMG65 Studio treated it as fatal and needed a replug every ~15 minutes; live frames only touch RAM.
    private func transact(_ steps: [AMG65Protocol.Step], liveFrame: Bool) throws {
        let checksum = AMG65Protocol.checksum(steps)
        let hasCountedData = steps.contains { $0.kind == .data }
        for step in steps {
            let reply: [UInt8]
            do {
                // A flush may be answered with 00 00 00 FF, so it doesn't filter on the 04 prefix.
                reply = try connection.exchange(step.bytes, timeout: 1.0, retries: 0,
                                                expecting: step.kind == .flush ? nil : 0x04)
            } catch {
                throw fail(.noAcknowledgement(step: step.label))
            }
            let expected = step.expectedOpcode
            let envelope = reply.count >= 4 && reply[0] == 0x04 && reply[1] == expected && reply[2] == 0
            if envelope && reply[3] == 0xFF && liveFrame && step.kind == .command && step.bytes[1] == 0x02 {
                throw ScreenKeyboardError.frameBusy
            }
            if envelope && reply[3] != 1 { throw fail(.rejected(step: step.label, status: reply[3])) }
            let acknowledged = envelope || (step.kind == .flush && reply.starts(with: [0, 0, 0, 0xFF]))
            guard acknowledged else { throw fail(.noAcknowledgement(step: step.label)) }
            if hasCountedData && step.bytes[1] == 0x02 && step.kind == .command {
                let echoed = reply.count >= 6 ? UInt16(reply[4]) | UInt16(reply[5]) << 8 : nil
                guard echoed == checksum else { throw fail(.checksumMismatch) }
            }
            Thread.sleep(forTimeInterval: 0.010)
        }
    }

    // MARK: Uploads (LCD images, LED-matrix animations)

    /// Uploads `blocks` 4096 byte blocks announced by `header` (`AMG65Protocol.lcdUploadHeader` or
    /// `stripUploadHeader`), as AMG65 Studio does: begin and header, then each block on the bulk channel
    /// (`AMG65BulkChannel`), acknowledged with `04 41 00 01` on the HID interface within 3 s, then end (and apply
    /// when `applyAfter`). Live frames are ended first. `progress` (0…1) is called on the calling thread after each
    /// acknowledged block.
    ///
    /// Invalid sizes and a bulk channel that can't be opened throw before anything is sent, without blocking the
    /// keyboard. Once begin was sent, a missing or wrong acknowledgement (or a failed block write) stops all sending
    /// until the keyboard is reconnected, like `run`; nothing more is sent after such a failure.
    public func upload(_ bytes: [UInt8], blocks: Int, header: [UInt8], applyAfter: Bool,
                       progress: @escaping @Sendable (Double) -> Void) throws {
        let blockSize = AMG65Protocol.uploadBlockSize
        guard (1...4096).contains(blocks), bytes.count == blocks * blockSize, header.count == AMG65Protocol.packetLength else {
            throw AMG65UploadError.invalidBuffer(blocks: blocks, bytes: bytes.count, header: header.count)
        }
        guard channel.link == .wired else { throw ScreenKeyboardError.needsCable }
        guard !Self.isBlocked(channel.registryID) else { throw ScreenKeyboardError.needsReconnect }
        guard !isClosed else { throw HIDError.disconnected }
        // The bulk interface of the same physical keyboard: matched by the HID interface's USB location.
        guard let location = connection.locationID else { throw HIDError.deviceNotFound }
        let bulk = try openBulkChannel(location)
        defer { bulk.close() }

        if liveFramesActive {
            try transact(AMG65Protocol.stopLiveFrames, liveFrame: false)
            liveFramesActive = false
        }
        try transact([AMG65Protocol.begin, AMG65Protocol.Step("upload header", header)], liveFrame: false)
        for index in 0..<blocks {
            let label = "upload block \(index + 1)/\(blocks)"
            let block = Array(bytes[index * blockSize..<(index + 1) * blockSize])
            let reply: [UInt8]
            do {
                reply = try connection.awaitReport(expecting: 0x04, timeout: 3) { try bulk.write(block, timeout: AMG65BulkChannel.writeTimeout) }
            } catch {
                throw fail(.noAcknowledgement(step: label))
            }
            guard reply.count >= 4, reply[0] == 0x04, reply[1] == 0x41, reply[2] == 0 else {
                throw fail(.noAcknowledgement(step: label))
            }
            guard reply[3] == 1 else { throw fail(.rejected(step: label, status: reply[3])) }
            // Studio's pause after the first block.
            if index == 0 { Thread.sleep(forTimeInterval: 0.5) }
            progress(Double(index + 1) / Double(blocks))
            Thread.sleep(forTimeInterval: 0.010)
        }
        try transact(applyAfter ? [AMG65Protocol.end, AMG65Protocol.apply] : [AMG65Protocol.end], liveFrame: false)
    }

    // MARK: Receiver

    /// Sends receiver packets; each reply must echo the packet's command, length and index.
    public func runDongle(_ packets: [[UInt8]]) throws {
        guard channel.link == .dongle else { throw ScreenKeyboardError.needsCable }
        guard !Self.isBlocked(channel.registryID) else { throw ScreenKeyboardError.needsReconnect }
        for (index, packet) in packets.enumerated() {
            let label = L("alıcı paketi %@", "\(index + 1)/\(packets.count)")
            guard packet.count == 32,
                  let reply = try? connection.exchange(packet, timeout: 1.0, retries: 0, expecting: packet[0]),
                  reply.count >= 3, Array(reply.prefix(3)) == Array(packet.prefix(3)) else {
                throw fail(.noAcknowledgement(step: label))
            }
            Thread.sleep(forTimeInterval: 0.010)
        }
    }

    // MARK: Stop after failure

    /// Blocks further sending to this keyboard until it is reconnected, and returns the error to throw.
    private func fail(_ error: ScreenKeyboardError) -> ScreenKeyboardError {
        Self.block(channel.registryID)
        liveFramesActive = false
        return error
    }

    static let blockedKey = "screenKeyboard.blockedRegistryIDs"

    static func isBlocked(_ registryID: UInt64) -> Bool {
        (UserDefaults.standard.array(forKey: blockedKey) as? [String] ?? []).contains(String(registryID))
    }

    static func block(_ registryID: UInt64) {
        var list = UserDefaults.standard.array(forKey: blockedKey) as? [String] ?? []
        guard !list.contains(String(registryID)) else { return }
        list = Array((list + [String(registryID)]).suffix(16))
        UserDefaults.standard.set(list, forKey: blockedKey)
    }
}

/// An upload buffer that doesn't fit the format (1…4096 blocks of 4096 bytes and a 64 byte header).
/// Thrown before anything is sent; `AMG65LCDAnimation.buffer()` and `AMG65StripAnimation.buffer` always fit.
public enum AMG65UploadError: Error, Equatable {
    case invalidBuffer(blocks: Int, bytes: Int, header: Int)
}

/// What `AMG65Link` needs from the vendor HID interface; `RawHIDConnection` in the app, a fake in tests.
protocol AMG65Transport: AnyObject {
    var isClosed: Bool { get }
    var locationID: UInt32? { get }
    func exchange(_ request: [UInt8], timeout: TimeInterval, retries: Int, expecting: UInt8?) throws -> [UInt8]
    func awaitReport(expecting: UInt8?, timeout: TimeInterval, after send: () throws -> Void) throws -> [UInt8]
    func close()
}

extension RawHIDConnection: AMG65Transport {}

/// Where upload blocks are written; `AMG65BulkChannel` in the app, a fake in tests.
protocol AMG65BlockWriter: AnyObject {
    func write(_ block: [UInt8], timeout: TimeInterval) throws
    func close()
}

extension AMG65BulkChannel: AMG65BlockWriter {}
