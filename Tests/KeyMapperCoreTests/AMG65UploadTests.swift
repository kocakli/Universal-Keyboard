import Foundation
import Testing
@testable import KeyMapperCore

/// `AMG65Link.upload` against a fake HID transport and bulk channel: the packet order of AMG65 Studio's
/// `uploadBulk`, and when a failure blocks the keyboard. Serialized: the block list lives in UserDefaults.
@Suite(.serialized) struct AMG65UploadTests {
    /// Records HID packets ("hid 0418") and block writes ("block 0") in order.
    final class Fake: AMG65Transport, @unchecked Sendable {
        var events: [String] = []
        var isClosed = false
        var locationID: UInt32? = 0x0110_0000
        /// Reply for a HID packet, nil = no reply. Default: commands acknowledged with their opcode, data with 0x41.
        var hidReply: ([UInt8]) -> [UInt8]? = { packet in
            let commands: Set<UInt8> = [0x02, 0x11, 0x13, 0x17, 0x18, 0x23, 0x28, 0x31, 0x33, 0x35, 0x72, 0xF0]
            let opcode = packet[0] == 0x04 && commands.contains(packet[1]) ? packet[1] : 0x41
            return [0x04, opcode, 0x00, 0x01]
        }
        /// Reply after block n, nil = no reply.
        var blockReply: (Int) -> [UInt8]? = { _ in [0x04, 0x41, 0x00, 0x01] }
        var failWrite: Int?
        var blocks: [[UInt8]] = []
        var bulkClosed = false

        func exchange(_ request: [UInt8], timeout: TimeInterval, retries: Int, expecting: UInt8?) throws -> [UInt8] {
            events.append("hid " + request.prefix(2).map { String(format: "%02x", $0) }.joined())
            guard let reply = hidReply(request) else { throw HIDError.timeout }
            return reply + [UInt8](repeating: 0, count: 64 - reply.count)
        }

        func awaitReport(expecting: UInt8?, timeout: TimeInterval, after send: () throws -> Void) throws -> [UInt8] {
            let index = blocks.count
            try send()
            guard let reply = blockReply(index) else { throw HIDError.timeout }
            return reply + [UInt8](repeating: 0, count: 64 - reply.count)
        }

        func writeBlock(_ block: [UInt8]) throws {
            events.append("block \(blocks.count)")
            if failWrite == blocks.count { throw HIDError.writeFailed(-1) }
            blocks.append(block)
        }

        func close() { isClosed = true }
    }

    /// The fake's bulk channel side.
    final class FakeBulk: AMG65BlockWriter {
        let fake: Fake
        init(_ fake: Fake) { self.fake = fake }
        func write(_ block: [UInt8], timeout: TimeInterval) throws { try fake.writeBlock(block) }
        func close() { fake.bulkClosed = true }
    }

    final class Progress: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [Double] = []
        func add(_ value: Double) { lock.lock(); stored.append(value); lock.unlock() }
        var values: [Double] { lock.lock(); defer { lock.unlock() }; return stored }
    }

    /// A link over `fake` with an id no real keyboard has; the bulk channel is `fake` unless `openBulk` says otherwise.
    private func link(_ fake: Fake, link kind: ScreenKeyboardChannel.Link = .wired,
                      openBulk: ((UInt32) throws -> AMG65BlockWriter)? = nil) -> AMG65Link {
        let id = UInt64.random(in: 0xF000_0000_0000_0000...UInt64.max)
        let channel = ScreenKeyboardChannel(model: .leobogAMG65, link: kind, registryID: id)
        return AMG65Link(channel: channel, transport: fake, openBulkChannel: openBulk ?? { [fake] _ in FakeBulk(fake) })
    }

    private func unblock(_ link: AMG65Link) {
        let key = AMG65Link.blockedKey
        let list = (UserDefaults.standard.array(forKey: key) as? [String] ?? []).filter { $0 != String(link.channel.registryID) }
        UserDefaults.standard.set(list, forKey: key)
    }

    /// Block n is filled with n + 1.
    private func payload(_ blocks: Int) -> [UInt8] {
        (0..<blocks).flatMap { [UInt8](repeating: UInt8($0 + 1), count: 4096) }
    }

    @Test func lcdUploadFollowsStudiosSequence() throws {
        let fake = Fake()
        let link = link(fake)
        defer { unblock(link) }
        let progress = Progress()
        try link.upload(payload(3), blocks: 3, header: AMG65Protocol.lcdUploadHeader(blocks: 3), applyAfter: false,
                        progress: { progress.add($0) })
        #expect(fake.events == ["hid 0418", "hid 0472", "block 0", "block 1", "block 2", "hid 0402"])
        #expect(fake.blocks.map { Set($0) } == [[1], [2], [3]])
        #expect(fake.blocks.allSatisfy { $0.count == 4096 })
        #expect(progress.values == [1.0 / 3, 2.0 / 3, 1])
        #expect(fake.bulkClosed)
        #expect(!AMG65Link.isBlocked(link.channel.registryID))
    }

    @Test func stripUploadEndsWithApply() throws {
        let fake = Fake()
        let link = link(fake)
        defer { unblock(link) }
        let header = AMG65Protocol.stripUploadHeader(target: .boot, blocks: 1)
        try link.upload(payload(1), blocks: 1, header: header, applyAfter: true, progress: { _ in })
        #expect(fake.events == ["hid 0418", "hid 0431", "block 0", "hid 0402", "hid 04f0"])
        #expect(fake.bulkClosed)
    }

    @Test func liveFramesEndBeforeTheUpload() throws {
        let fake = Fake()
        let link = link(fake)
        defer { unblock(link) }
        try link.showFrame([RGB24](repeating: .off, count: 315))
        fake.events = []
        try link.upload(payload(1), blocks: 1, header: AMG65Protocol.lcdUploadHeader(blocks: 1), applyAfter: false, progress: { _ in })
        #expect(fake.events == ["hid 0402", "hid 04f0", "hid 0418", "hid 0472", "block 0", "hid 0402"])
        // The frames stay ended: the next transaction sends no extra stop.
        fake.events = []
        try link.run(AMG65Protocol.timeSync(Date()))
        #expect(fake.events.first == "hid 0418")
    }

    @Test func nothingIsSentWhenTheUploadCantStart() throws {
        let fake = Fake()
        let header = AMG65Protocol.lcdUploadHeader(blocks: 1)
        var opened = 0
        let counting = link(fake, openBulk: { _ in opened += 1; throw HIDError.openFailed(-1) })
        defer { unblock(counting) }

        // Sizes are checked before the bulk channel is opened.
        #expect(throws: AMG65UploadError.invalidBuffer(blocks: 0, bytes: 0, header: 64)) {
            try counting.upload([], blocks: 0, header: header, applyAfter: false, progress: { _ in })
        }
        #expect(throws: AMG65UploadError.self) {
            try counting.upload([UInt8](repeating: 0, count: 4097 * 4096), blocks: 4097, header: header, applyAfter: false, progress: { _ in })
        }
        #expect(throws: AMG65UploadError.self) {
            try counting.upload(payload(1) + [0], blocks: 1, header: header, applyAfter: false, progress: { _ in })
        }
        #expect(throws: AMG65UploadError.self) {
            try counting.upload(payload(1), blocks: 1, header: Array(header.prefix(63)), applyAfter: false, progress: { _ in })
        }
        #expect(opened == 0)

        // A bulk channel that can't be opened: its error, nothing sent, the keyboard not blocked.
        #expect(throws: HIDError.openFailed(-1)) {
            try counting.upload(payload(1), blocks: 1, header: header, applyAfter: false, progress: { _ in })
        }
        #expect(opened == 1)
        // Not even the stop of running live frames.
        try counting.showFrame([RGB24](repeating: .off, count: 315))
        fake.events = []
        #expect(throws: HIDError.openFailed(-1)) {
            try counting.upload(payload(1), blocks: 1, header: header, applyAfter: false, progress: { _ in })
        }
        #expect(fake.events.isEmpty)
        #expect(!AMG65Link.isBlocked(counting.channel.registryID))

        // No USB location: nothing to match the bulk interface with.
        let unlocated = Fake()
        unlocated.locationID = nil
        let noLocation = link(unlocated)
        #expect(throws: HIDError.deviceNotFound) {
            try noLocation.upload(payload(1), blocks: 1, header: header, applyAfter: false, progress: { _ in })
        }
        #expect(unlocated.events.isEmpty)

        // The receiver has no bulk channel.
        let dongle = Fake()
        let receiver = link(dongle, link: .dongle)
        #expect(throws: ScreenKeyboardError.needsCable) {
            try receiver.upload(payload(1), blocks: 1, header: header, applyAfter: false, progress: { _ in })
        }
        #expect(dongle.events.isEmpty)
        #expect(!dongle.bulkClosed)
    }

    enum Failure: String, CaseIterable {
        case headerRejected, headerUnanswered, blockUnanswered, blockRejected, wrongBlockOpcode, writeFailed, endUnanswered
    }

    @Test(arguments: Failure.allCases)
    func failuresBlockTheKeyboardAndStopSending(failure: Failure) throws {
        let fake = Fake()
        let defaultReply = fake.hidReply
        var expectedEvents: [String]
        var expectedError: ScreenKeyboardError
        switch failure {
        case .headerRejected:
            fake.hidReply = { $0[1] == 0x72 ? [0x04, 0x72, 0x00, 0x00] : defaultReply($0) }
            expectedEvents = ["hid 0418", "hid 0472"]
            expectedError = .rejected(step: "upload header", status: 0)
        case .headerUnanswered:
            fake.hidReply = { $0[1] == 0x72 ? nil : defaultReply($0) }
            expectedEvents = ["hid 0418", "hid 0472"]
            expectedError = .noAcknowledgement(step: "upload header")
        case .blockUnanswered:
            fake.blockReply = { $0 == 1 ? nil : [0x04, 0x41, 0x00, 0x01] }
            expectedEvents = ["hid 0418", "hid 0472", "block 0", "block 1"]
            expectedError = .noAcknowledgement(step: "upload block 2/3")
        case .blockRejected:
            fake.blockReply = { $0 == 1 ? [0x04, 0x41, 0x00, 0x02] : [0x04, 0x41, 0x00, 0x01] }
            expectedEvents = ["hid 0418", "hid 0472", "block 0", "block 1"]
            expectedError = .rejected(step: "upload block 2/3", status: 2)
        case .wrongBlockOpcode:
            fake.blockReply = { _ in [0x04, 0x42, 0x00, 0x01] }
            expectedEvents = ["hid 0418", "hid 0472", "block 0"]
            expectedError = .noAcknowledgement(step: "upload block 1/3")
        case .writeFailed:
            fake.failWrite = 2
            expectedEvents = ["hid 0418", "hid 0472", "block 0", "block 1", "block 2"]
            expectedError = .noAcknowledgement(step: "upload block 3/3")
        case .endUnanswered:
            fake.hidReply = { $0[1] == 0x02 ? nil : defaultReply($0) }
            expectedEvents = ["hid 0418", "hid 0472", "block 0", "block 1", "block 2", "hid 0402"]
            expectedError = .noAcknowledgement(step: "end")
        }
        let link = link(fake)
        defer { unblock(link) }
        let header = AMG65Protocol.lcdUploadHeader(blocks: 3)
        #expect(throws: expectedError) {
            try link.upload(payload(3), blocks: 3, header: header, applyAfter: true, progress: { _ in })
        }
        #expect(fake.events == expectedEvents)
        #expect(fake.bulkClosed)
        #expect(AMG65Link.isBlocked(link.channel.registryID))

        // Blocked until reconnected: the next upload sends nothing.
        fake.events = []
        #expect(throws: ScreenKeyboardError.needsReconnect) {
            try link.upload(payload(3), blocks: 3, header: header, applyAfter: true, progress: { _ in })
        }
        #expect(fake.events.isEmpty)
    }

    // MARK: Bulk interface lookup (IORegistry only)

    @Test func bulkInterfaceIsMatchedByIDsInterfaceAndLocation() {
        let amg65: [String: Any] = ["idVendor": 0x0C45, "idProduct": 0x800A, "bInterfaceNumber": 3, "locationID": NSNumber(value: 0x8210_0000 as UInt32)]
        #expect(AMG65BulkChannel.matches(amg65, locationID: 0x8210_0000))
        #expect(!AMG65BulkChannel.matches(amg65, locationID: 0x8220_0000))
        var other = amg65
        other["bInterfaceNumber"] = 2
        #expect(!AMG65BulkChannel.matches(other, locationID: 0x8210_0000))
        other = amg65
        other["idProduct"] = 0x800B
        #expect(!AMG65BulkChannel.matches(other, locationID: 0x8210_0000))
        other = amg65
        other["locationID"] = nil
        #expect(!AMG65BulkChannel.matches(other, locationID: 0x8210_0000))
    }

    @Test func bulkChannelThrowsWhenNoKeyboardIsAtTheLocation() {
        // Reads registry properties only; no interface is opened.
        #expect(throws: HIDError.deviceNotFound) { try AMG65BulkChannel(locationID: 0xFFFF_FFFF) }
    }
}
