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

    /// Lifts the block, as a replug does; `forgetStop` also drops the link's stop records.
    private func unblock(_ link: AMG65Link, forgetStop: Bool = true) {
        let id = link.channel.registryID
        let key = AMG65Link.blockedKey
        let list = (UserDefaults.standard.array(forKey: key) as? [String] ?? []).filter { $0 != String(id) }
        UserDefaults.standard.set(list, forKey: key)
        guard forgetStop else { return }
        let stops = AMG65Link.recentStops.filter { $0.registryID != id }
        UserDefaults.standard.set(try? JSONEncoder().encode(stops), forKey: AMG65Link.stopsKey)
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
        // What the stop records: the keyboard's reply (padded to 64 bytes by the fake) or the transport error.
        var expectedDetail: String
        switch failure {
        case .headerRejected:
            fake.hidReply = { $0[1] == 0x72 ? [0x04, 0x72, 0x00, 0x00] : defaultReply($0) }
            expectedEvents = ["hid 0418", "hid 0472"]
            expectedError = .rejected(step: "upload header", status: 0)
            expectedDetail = "reply 04 72 00 00 00 00 00 00"
        case .headerUnanswered:
            fake.hidReply = { $0[1] == 0x72 ? nil : defaultReply($0) }
            expectedEvents = ["hid 0418", "hid 0472"]
            expectedError = .noAcknowledgement(step: "upload header")
            expectedDetail = "timeout"
        case .blockUnanswered:
            fake.blockReply = { $0 == 1 ? nil : [0x04, 0x41, 0x00, 0x01] }
            expectedEvents = ["hid 0418", "hid 0472", "block 0", "block 1"]
            expectedError = .noAcknowledgement(step: "upload block 2/3")
            expectedDetail = "timeout"
        case .blockRejected:
            fake.blockReply = { $0 == 1 ? [0x04, 0x41, 0x00, 0x02] : [0x04, 0x41, 0x00, 0x01] }
            expectedEvents = ["hid 0418", "hid 0472", "block 0", "block 1"]
            expectedError = .rejected(step: "upload block 2/3", status: 2)
            expectedDetail = "reply 04 41 00 02 00 00 00 00"
        case .wrongBlockOpcode:
            fake.blockReply = { _ in [0x04, 0x42, 0x00, 0x01] }
            expectedEvents = ["hid 0418", "hid 0472", "block 0"]
            expectedError = .noAcknowledgement(step: "upload block 1/3")
            expectedDetail = "reply 04 42 00 01 00 00 00 00"
        case .writeFailed:
            fake.failWrite = 2
            expectedEvents = ["hid 0418", "hid 0472", "block 0", "block 1", "block 2"]
            expectedError = .noAcknowledgement(step: "upload block 3/3")
            expectedDetail = "writeFailed(-1)"
        case .endUnanswered:
            fake.hidReply = { $0[1] == 0x02 ? nil : defaultReply($0) }
            expectedEvents = ["hid 0418", "hid 0472", "block 0", "block 1", "block 2", "hid 0402"]
            expectedError = .noAcknowledgement(step: "end")
            expectedDetail = "timeout"
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

        // The stop is recorded and read back by the keyboard's id alone, as after an app restart.
        let stop = try #require(AMG65Link.lastStop(for: link.channel.registryID))
        #expect(stop.error == expectedError)
        #expect(stop.detail == expectedDetail)
        #expect(stop.completedBefore == 0)

        // Blocked until reconnected: the next upload sends nothing and keeps the recorded cause.
        fake.events = []
        #expect(throws: ScreenKeyboardError.needsReconnect) {
            try link.upload(payload(3), blocks: 3, header: header, applyAfter: true, progress: { _ in })
        }
        #expect(fake.events.isEmpty)
        #expect(AMG65Link.lastStop(for: link.channel.registryID) == stop)
    }

    @Test func aStopRecordsTheStepTheReplyAndTheSendsBeforeIt() throws {
        let fake = Fake()
        let link = link(fake)
        defer { unblock(link) }
        try link.run(AMG65Protocol.timeSync(Date()))
        #expect(AMG65Link.lastStop(for: link.channel.registryID) == nil)

        // Counted data: the fake's end reply echoes 00 00, not the checksum.
        let steps = AMG65Protocol.lighting(AMG65Lighting())
        #expect(throws: ScreenKeyboardError.checksumMismatch) { try link.run(steps) }
        let stop = try #require(AMG65Link.lastStop(for: link.channel.registryID))
        #expect(stop.reason == .checksumMismatch)
        #expect(stop.step == "end")
        #expect(stop.status == nil)
        #expect(stop.detail == String(format: "sent %04X, ", AMG65Protocol.checksum(steps)) + "reply 04 02 00 01 00 00 00 00")
        #expect(stop.completedBefore == 1)

        // A replug lifts the block; the record stays.
        unblock(link, forgetStop: false)
        #expect(!AMG65Link.isBlocked(link.channel.registryID))
        #expect(AMG65Link.lastStop(for: link.channel.registryID) == stop)
    }

    @Test func onlyTheLastTenStopsAreKept() throws {
        let links = (0..<11).map { _ in
            let fake = Fake()
            fake.hidReply = { _ in nil }
            return link(fake)
        }
        defer { links.forEach { unblock($0) } }
        for link in links {
            #expect(throws: ScreenKeyboardError.noAcknowledgement(step: "begin")) { try link.run(AMG65Protocol.timeSync(Date())) }
        }
        let kept = Set(AMG65Link.recentStops.map(\.registryID))
        #expect(AMG65Link.recentStops.count == 10)
        #expect(!kept.contains(links[0].channel.registryID))
        #expect(kept.isSuperset(of: links.dropFirst().map(\.channel.registryID)))
    }

    // MARK: Half-sent live frames

    /// The keyboard's side of live frames, as measured on the AMG65 (`kmctl screen <n> frame-recovery`, 2026-11-15: a
    /// frame cut after k data packets closed with 16 − k end packets): after a frame header (0x35) it takes the next
    /// 15 packets as frame data, whatever they hold, and answers each with `04 41 00 01`; outside a frame a command
    /// packet is answered with its opcode and a zero packet (the flush) with `00 00 00 FF`. Packet `lost` (1-based) is lost on the way; packet `unanswered` arrives but
    /// its reply is lost; after `silentAfter` packets the keyboard answers nothing.
    final class FrameKeyboard: @unchecked Sendable {
        var pending = 0
        var count = 0
        var lost: Int?
        var unanswered: Int?
        var silentAfter: Int?

        func reply(_ packet: [UInt8]) -> [UInt8]? {
            count += 1
            if let silentAfter, count > silentAfter { return nil }
            if count == lost { return nil }
            let reply: [UInt8]
            if pending > 0 {
                pending -= 1
                reply = [0x04, 0x41, 0x00, 0x01]
            } else if packet[0] == 0x04 {
                if packet[1] == 0x35 { pending = 15 }
                reply = [0x04, packet[1], 0x00, 0x01]
            } else {
                reply = [0x00, 0x00, 0x00, 0xFF]
            }
            return count == unanswered ? nil : reply
        }
    }

    private func frameLink(_ keyboard: FrameKeyboard) -> (AMG65Link, Fake) {
        let fake = Fake()
        fake.hidReply = keyboard.reply
        let link = link(fake)
        link.recoveryPause = 0
        return (link, fake)
    }

    private let blank = [RGB24](repeating: .off, count: 315)

    /// Packet 5 is the frame's third data packet (begin, header, data 1, data 2, data 3).
    @Test(arguments: [true, false])
    func anUnansweredFrameIsClosedAndSendingGoesOn(replyLost: Bool) throws {
        let keyboard = FrameKeyboard()
        if replyLost { keyboard.unanswered = 5 } else { keyboard.lost = 5 }
        let (link, fake) = frameLink(keyboard)
        defer { unblock(link) }
        #expect(throws: ScreenKeyboardError.frameBusy) { try link.showFrame(blank) }
        // The keyboard waited for 12 (or, without packet 5, 13) more data packets; the next end closed the frame.
        let ends = fake.events.dropFirst(5).filter { $0 == "hid 0402" }.count
        #expect(ends == (replyLost ? 13 : 14))
        #expect(fake.events.dropFirst(5).allSatisfy { $0 == "hid 0402" })
        #expect(keyboard.pending == 0)
        #expect(link.recoveredFrames == 1)
        #expect(!AMG65Link.isBlocked(link.channel.registryID))
        #expect(AMG65Link.lastStop(for: link.channel.registryID) == nil)
        // Back in step: the next frame and the end of live frames go through.
        try link.showFrame(blank)
        try link.endFrames()
    }

    @Test func aFrameThatCantBeClosedStopsSending() throws {
        let keyboard = FrameKeyboard()
        keyboard.silentAfter = 4
        let (link, fake) = frameLink(keyboard)
        defer { unblock(link) }
        #expect(throws: ScreenKeyboardError.noAcknowledgement(step: "frame data 3/15")) { try link.showFrame(blank) }
        // Three unanswered end packets, then nothing more.
        #expect(fake.events.dropFirst(5) == ["hid 0402", "hid 0402", "hid 0402"])
        #expect(AMG65Link.isBlocked(link.channel.registryID))
        let stop = try #require(AMG65Link.lastStop(for: link.channel.registryID))
        #expect(stop.detail == "timeout; closing the frame: no reply to 3 end packets")
        #expect(link.recoveredFrames == 0)
    }

    @Test func aRefusedFramePacketIsClosedToo() throws {
        let keyboard = FrameKeyboard()
        let (link, fake) = frameLink(keyboard)
        defer { unblock(link) }
        let answer = keyboard.reply
        fake.hidReply = { packet in
            // The header is refused (status 0) but taken: the keyboard still waits for the frame's 15 data packets.
            let reply = answer(packet)
            return packet[0] == 0x04 && packet[1] == 0x35 ? [0x04, 0x35, 0x00, 0x00] : reply
        }
        #expect(throws: ScreenKeyboardError.frameBusy) { try link.showFrame(blank) }
        #expect(fake.events.dropFirst(2).filter { $0 == "hid 0402" }.count == 16)
        #expect(!AMG65Link.isBlocked(link.channel.registryID))
    }

    @Test func otherTransactionsStillStopAtTheFirstMissingReply() throws {
        let keyboard = FrameKeyboard()
        keyboard.unanswered = 2
        let (link, fake) = frameLink(keyboard)
        defer { unblock(link) }
        #expect(throws: ScreenKeyboardError.noAcknowledgement(step: "clock header")) { try link.run(AMG65Protocol.timeSync(Date())) }
        #expect(fake.events.count == 2)
        #expect(AMG65Link.isBlocked(link.channel.registryID))
    }

    @Test func theRecoveryCheckClosesCutFrames() throws {
        for cut in [0, 5, 15] {
            let keyboard = FrameKeyboard()
            let (link, _) = frameLink(keyboard)
            defer { unblock(link) }
            // As on the keyboard: 15 data packets were awaited, `cut` were sent, so the rest plus one end close it.
            #expect(try link.checkFrameRecovery(dataPackets: cut) == 16 - cut)
            #expect(keyboard.pending == 0)
            #expect(!AMG65Link.isBlocked(link.channel.registryID))
        }
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
