import Foundation

// LEOBOG AMG65 vendor protocol.
// Ported from AMG65 Studio (github.com/kocakli/amg65-studio), which builds on aumbro/leobog_amg65_rgb (MIT).
// Packet sequences are the ones those projects verified on the keyboard; see THIRD_PARTY_NOTICES.md.

/// 8-bit RGB colour.
public struct RGB24: Codable, Hashable, Sendable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8

    public init(r: UInt8, g: UInt8, b: UInt8) { self.r = r; self.g = g; self.b = b }

    public static let off = RGB24(r: 0, g: 0, b: 0)
    public var isOff: Bool { r == 0 && g == 0 && b == 0 }
    public var hex: String { String(format: "#%02X%02X%02X", r, g, b) }

    /// "#RRGGBB" or "RRGGBB"; anything else (alpha, short forms, partial edits) is rejected.
    public init?(hex: String) {
        let text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = text.hasPrefix("#") ? String(text.dropFirst()) : text
        guard digits.utf8.count == 6, digits.allSatisfy(\.isHexDigit), let value = UInt32(digits, radix: 16) else { return nil }
        self.init(r: UInt8(value >> 16 & 0xFF), g: UInt8(value >> 8 & 0xFF), b: UInt8(value & 0xFF))
    }
}

/// Backlight effect settings (command 0x13). The keyboard can't report them back, so the app remembers them.
public struct AMG65Lighting: Codable, Equatable, Sendable {
    public var mode: UInt8 = 1
    public var color = RGB24(r: 255, g: 255, b: 255)
    /// Rainbow instead of the single colour.
    public var colorful = false
    /// 0…5.
    public var brightness: UInt8 = 5
    /// 0…5, higher is faster.
    public var speed: UInt8 = 3
    /// Only used by the "Scrolling" effect.
    public var direction: UInt8 = 0

    public init() {}
}

public struct AMG65Effect: Identifiable, Hashable, Sendable {
    public let id: UInt8
    public let name: String
    /// Seen working on the keyboard (the others come from the vendor app's string table).
    public let confirmed: Bool

    public var usesSpeed: Bool { id != 1 && id != 20 }
    public var usesColor: Bool { id != 20 }
    public var usesDirection: Bool { id == 10 }
}

/// Device settings (command 0x17). The keyboard always receives every field.
public struct AMG65DeviceSettings: Codable, Equatable, Sendable {
    /// LED matrix brightness, 1 (dim) … 7 (vendor default). Confirmed.
    public var screenBrightness: UInt8 = 7
    /// Sleep after 0 never, 1 = 1 min, 2 = 5 min, 3 = 30 min.
    public var sleep: UInt8 = 0
    /// Fn toggles instead of being held.
    public var fnToggle = false
    /// Game mode and the shortcuts it blocks.
    public var gameMode = false
    public var blockAltTab = false
    public var blockAltF4 = false
    public var blockWindowsKey = false

    public init() {}
}

public enum AMG65Protocol {
    public static let packetLength = 64
    /// The LED matrix rejects 255 in a live frame (it is used as a status byte); colours are clamped to 254.
    public static let maxFrameChannel: UInt8 = 254
    /// Live frames faster than this are not acknowledged reliably.
    public static let minimumFrameInterval: TimeInterval = 0.25

    /// One 64 byte packet and the acknowledgement it must get.
    public struct Step: Equatable, Sendable {
        public enum Kind: Sendable {
            /// `04 <opcode> …`, acknowledged with `04 <opcode> 00 01`.
            case command
            /// Payload counted in the transaction checksum, acknowledged with `04 41 00 01`.
            case data
            /// Payload the keyboard does not sum (time data, live frames), acknowledged with `04 41 00 01`.
            case uncountedData
            /// All-zero packet ending a live frame; acknowledged with `04 41 00 01` or `00 00 00 FF`.
            case flush
        }

        public let label: String
        public let bytes: [UInt8]
        public let kind: Kind

        public init(_ label: String, _ bytes: [UInt8], _ kind: Kind = .command) {
            self.label = label
            self.bytes = bytes
            self.kind = kind
        }

        public var expectedOpcode: UInt8 { kind == .command ? bytes[1] : 0x41 }
    }

    public static func packet(_ head: [UInt8], _ at: [Int: UInt8] = [:]) -> [UInt8] {
        var buffer = [UInt8](repeating: 0, count: packetLength)
        for (index, byte) in head.prefix(packetLength).enumerated() { buffer[index] = byte }
        for (index, byte) in at where (0..<packetLength).contains(index) { buffer[index] = byte }
        return buffer
    }

    static let begin = Step("begin", packet([0x04, 0x18]))
    static let end = Step("end", packet([0x04, 0x02]))
    static let apply = Step("apply", packet([0x04, 0xF0]))

    /// 16-bit sum of the counted data bytes; the keyboard echoes it in the end reply [4…5].
    public static func checksum(_ steps: [Step]) -> UInt16 {
        var sum = 0
        for step in steps where step.kind == .data { sum += step.bytes.reduce(0) { $0 + Int($1) } }
        return UInt16(sum & 0xFFFF)
    }

    public static let effects: [AMG65Effect] = [
        .init(id: 1, name: "Static", confirmed: true),
        .init(id: 2, name: "Single On", confirmed: false),
        .init(id: 3, name: "Single Off", confirmed: false),
        .init(id: 4, name: "Glittering", confirmed: false),
        .init(id: 5, name: "Falling", confirmed: false),
        .init(id: 6, name: "Colourful", confirmed: false),
        .init(id: 7, name: "Breath", confirmed: true),
        .init(id: 8, name: "Spectrum", confirmed: false),
        .init(id: 9, name: "Outward", confirmed: false),
        .init(id: 10, name: "Scrolling", confirmed: false),
        .init(id: 11, name: "Rolling", confirmed: false),
        .init(id: 12, name: "Rotating", confirmed: false),
        .init(id: 13, name: "Explode", confirmed: false),
        .init(id: 14, name: "Launch", confirmed: false),
        .init(id: 15, name: "Ripples", confirmed: false),
        .init(id: 16, name: "Flowing", confirmed: false),
        .init(id: 17, name: "Pulsating", confirmed: false),
        .init(id: 18, name: "Tilt", confirmed: false),
        .init(id: 19, name: "Shuttle", confirmed: false),
        .init(id: 20, name: "Backlight Off", confirmed: false),
    ]

    /// Backlight effect (command 0x13), as the vendor app sends it.
    public static func lighting(_ s: AMG65Lighting) -> [Step] {
        let data = packet([s.mode, s.color.r, s.color.g, s.color.b], [
            8: s.colorful ? 1 : 0, 9: min(s.brightness, 5), 10: min(s.speed, 5), 11: s.direction, 14: 0xAA, 15: 0x55,
        ])
        return [begin, Step("lighting header", packet([0x04, 0x13], [8: 0x01])), Step("lighting data", data, .data), end, apply]
    }

    /// Device settings (command 0x17), as the vendor app sends it (no apply packet).
    public static func settings(_ s: AMG65DeviceSettings) -> [Step] {
        let game: UInt8 = s.gameMode ? 1 : 0
        let data = packet([
            0x00, game,
            game & (s.blockAltTab ? 1 : 0), game & (s.blockAltF4 ? 1 : 0), game & (s.blockWindowsKey ? 1 : 0),
            s.fnToggle ? 1 : 0, min(s.sleep, 3), min(max(s.screenBrightness, 1), 7),
        ], [62: 0xAA, 63: 0x55])
        return [begin, Step("settings header", packet([0x04, 0x17, 0x01], [8: 0x01])), Step("settings data", data, .data), end]
    }

    /// Clock (command 0x28): date, time and ISO weekday (Mon = 1 … Sun = 7) in `timeZone`.
    /// `view` [1] selects the LCD page to show; 0 keeps the current one.
    public static func timeSync(_ date: Date, timeZone: TimeZone = .autoupdatingCurrent, view: UInt8 = 0) -> [Step] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .weekday], from: date)
        let isoWeekday = UInt8(((c.weekday ?? 1) + 5) % 7 + 1)
        let data = packet([
            0x00, view, 0x5A, UInt8((c.year ?? 2000) % 100), UInt8(c.month ?? 1), UInt8(c.day ?? 1),
            UInt8(c.hour ?? 0), UInt8(c.minute ?? 0), UInt8(c.second ?? 0), 0x00, isoWeekday,
        ], [62: 0xAA, 63: 0x55])
        return [begin, Step("clock header", packet([0x04, 0x28], [8: 0x01])), Step("clock data", data, .uncountedData), end]
    }

    /// Per-key colour table (command 0x23): slot n = [n, R, G, B] for 128 slots.
    /// Shown once the custom effect is selected with `customColorMode`.
    public static func customColors(_ colors: [Int: RGB24]) -> [Step] {
        var table = [UInt8](repeating: 0, count: 512)
        for (index, color) in colors where (0..<128).contains(index) {
            table[index * 4] = UInt8(index)
            table[index * 4 + 1] = color.r
            table[index * 4 + 2] = color.g
            table[index * 4 + 3] = color.b
        }
        var steps = [begin, Step("colour table header", packet([0x04, 0x23], [8: 0x08]))]
        for part in 0..<8 {
            steps.append(Step("colour data \(part + 1)/8", Array(table[part * 64..<(part + 1) * 64]), .data))
        }
        steps += [end, apply]
        return steps
    }

    /// Selects the per-key colour effect (mode 0x80) after `customColors`.
    public static func customColorMode(brightness: UInt8) -> [Step] {
        let data = packet([0x80, 0, 0, 0], [9: min(brightness, 5), 10: 0x0F, 11: 0x0F, 14: 0xAA, 15: 0x55])
        return [begin, Step("lighting header", packet([0x04, 0x13], [8: 0x01])), Step("custom mode data", data, .data), end, apply]
    }

    /// Key table (command 0x11): 127 slots × 4 bytes, AA 55 at the end. An all-zero slot is the factory key.
    public static func keyTable(_ slots: [Int: [UInt8]]) -> [Step] {
        var table = [UInt8](repeating: 0, count: 512)
        for (index, slot) in slots where (0..<127).contains(index) {
            for (offset, byte) in slot.prefix(4).enumerated() { table[index * 4 + offset] = byte }
        }
        table[510] = 0xAA
        table[511] = 0x55
        var steps = [begin, Step("key table header", packet([0x04, 0x11], [8: 0x08]))]
        for part in 0..<8 {
            steps.append(Step("key table data \(part + 1)/8", Array(table[part * 64..<(part + 1) * 64]), .data))
        }
        steps += [end, apply]
        return steps
    }

    /// One live LED-matrix frame (command 0x35, RAM only): 315 RGB pixels, row-major from the top left.
    /// The keyboard takes four 14-column blocks, then the last 7 columns, each block row by row.
    public static func liveFrame(_ pixels: [RGB24]) -> [Step] {
        precondition(pixels.count == 315, "the AMG65 matrix has 63 × 5 pixels")
        var raw: [UInt8] = []
        raw.reserveCapacity(960)
        func append(_ pixel: RGB24) {
            raw += [min(pixel.r, maxFrameChannel), min(pixel.g, maxFrameChannel), min(pixel.b, maxFrameChannel)]
        }
        for block in 0..<4 { for y in 0..<5 { for x in (block * 14)..<(block * 14 + 14) { append(pixels[y * 63 + x]) } } }
        for y in 0..<5 { for x in 56..<63 { append(pixels[y * 63 + x]) } }
        raw += [0xAA, 0x55] + [UInt8](repeating: 0, count: 13)
        var steps = [begin, Step("frame header", packet([0x04, 0x35], [8: 15]))]
        for (part, offset) in stride(from: 0, to: 960, by: 64).enumerated() {
            steps.append(Step("frame data \(part + 1)/15", Array(raw[offset..<offset + 64]), .uncountedData))
        }
        steps += [Step("frame flush", [UInt8](repeating: 0, count: packetLength), .flush), end]
        return steps
    }

    /// Ends live frames so the keyboard returns to its own LED animation.
    public static let stopLiveFrames: [Step] = [end, apply]

    /// Uploads (`AMG65Link.upload`) are sent in blocks of this size on the bulk channel.
    public static let uploadBlockSize = 4096

    /// Header of an LCD image upload (command 0x72): the slot at [2], the block count at [8…9] (little endian).
    public static func lcdUploadHeader(blocks: Int, slot: UInt8 = AMG65LCDFormat.slot) -> [UInt8] {
        packet([0x04, 0x72, slot], [8: UInt8(truncatingIfNeeded: blocks), 9: UInt8(truncatingIfNeeded: blocks >> 8)])
    }

    /// Header of an LED-matrix animation upload (command 0x33, or 0x31 for the boot animation): the block count
    /// at [8…9] (little endian). The upload ends with an apply packet.
    public static func stripUploadHeader(target: AMG65StripTarget, blocks: Int) -> [UInt8] {
        packet([0x04, target.command], [8: UInt8(truncatingIfNeeded: blocks), 9: UInt8(truncatingIfNeeded: blocks >> 8)])
    }
}

/// 2.4 GHz receiver protocol: [cmd, length, index, payload…] in 32 byte packets, byte 31 = sum of bytes 0…30.
public enum AMG65DongleProtocol {
    public static func packet(_ cmd: UInt8, length: UInt8, index: UInt8, _ payload: [UInt8]) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: 32)
        data[0] = cmd
        data[1] = length
        data[2] = index
        for (offset, byte) in payload.prefix(28).enumerated() { data[3 + offset] = byte }
        data[31] = UInt8(data[0..<31].reduce(0) { $0 + Int($1) } & 0xFF)
        return data
    }

    /// A table split into 28 byte chunks (the last one shorter).
    static func chunks(_ cmd: UInt8, _ table: [UInt8]) -> [[UInt8]] {
        stride(from: 0, to: table.count, by: 28).enumerated().map { index, start in
            let part = Array(table[start..<min(start + 28, table.count)])
            return packet(cmd, length: UInt8(part.count), index: UInt8(index), part)
        }
    }

    /// Backlight effect (cmd 05): the same fields as the cable's lighting data.
    public static func lighting(_ s: AMG65Lighting) -> [[UInt8]] {
        [packet(0x05, length: 0x10, index: 0, [
            s.mode, s.color.r, s.color.g, s.color.b, 0, 0, 0, 0,
            s.colorful ? 1 : 0, min(s.brightness, 5), min(s.speed, 5), s.direction, 0, 0, 0xAA, 0x55,
        ])]
    }

    /// Per-key colours: the custom effect, then a 576 byte table (slot n = [n, R, G, B], AA 55 at 574) as cmd 0x14.
    public static func customColors(_ colors: [Int: RGB24], brightness: UInt8) -> [[UInt8]] {
        var table = [UInt8](repeating: 0, count: 576)
        for (index, color) in colors where (0..<144).contains(index) {
            table[index * 4] = UInt8(index)
            table[index * 4 + 1] = color.r
            table[index * 4 + 2] = color.g
            table[index * 4 + 3] = color.b
        }
        table[574] = 0xAA
        table[575] = 0x55
        let mode = packet(0x05, length: 0x10, index: 0, [0x80, 0, 0, 0, 0, 0, 0, 0, 0, min(brightness, 5), 0, 0, 0, 0, 0xAA, 0x55])
        return [mode] + chunks(0x14, table)
    }

    /// Key table (cmd 0x10): the cable's 512 byte table in 19 chunks.
    public static func keyTable(_ slots: [Int: [UInt8]]) -> [[UInt8]] {
        var table = [UInt8](repeating: 0, count: 512)
        for (index, slot) in slots where (0..<127).contains(index) {
            for (offset, byte) in slot.prefix(4).enumerated() { table[index * 4 + offset] = byte }
        }
        table[510] = 0xAA
        table[511] = 0x55
        return chunks(0x10, table)
    }
}
