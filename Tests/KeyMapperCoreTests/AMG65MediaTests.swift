import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import Testing
@testable import KeyMapperCore

/// Byte-for-byte parity with AMG65 Studio's key layout, key actions, LCD and LED-matrix uploads.
/// `Fixtures/amg65-media-golden.json` was produced by compiling Studio's own `Keymap.swift`, `LEDStrip.swift`,
/// `LCD.swift` and `MediaBudget.swift` (copied verbatim; only `L()` and the SwiftUI part of `RGB` stubbed) with the
/// inputs rebuilt below, plus the upload header expressions of `KeyboardHID.uploadLCD` and `StripModel.upload`.
@Suite struct AMG65MediaTests {
    private static let golden: [String: Any] = {
        guard let url = Bundle.module.url(forResource: "amg65-media-golden", withExtension: "json", subdirectory: "Fixtures"),
              let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return object
    }()

    private func list(_ key: String) throws -> [[String: Any]] {
        try #require(Self.golden[key] as? [[String: Any]], "\(key) missing from the golden file")
    }

    private func hex(_ bytes: some Sequence<UInt8>) -> String { bytes.map { String(format: "%02x", $0) }.joined() }
    private func sha(_ bytes: [UInt8]) -> String { hex(SHA256.hash(data: Data(bytes))) }

    // MARK: Inputs (the same as the golden generator's)

    static func stripFrames(count: Int, pixels: Int, seed: Int) -> [[RGB24]] {
        (0..<count).map { f in
            (0..<pixels).map { i in
                RGB24(r: UInt8((i * 3 + f * 7 + seed) % 256), g: UInt8((i * 5 + f * 11 + seed * 3) % 256),
                      b: UInt8((i * 7 + f * 13 + 255 - seed) % 256))
            }
        }
    }

    static func image(width: Int, height: Int, _ pixel: (Int, Int) -> (UInt8, UInt8, UInt8)) -> CGImage {
        var px = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let (r, g, b) = pixel(x, y)
                let o = (y * width + x) * 4
                px[o] = r; px[o + 1] = g; px[o + 2] = b
            }
        }
        let provider = CGDataProvider(data: Data(px) as CFData)!
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }

    static func pattern(seed: Int, width: Int = 240, height: Int = 135) -> CGImage {
        image(width: width, height: height) { x, y in
            (UInt8((x * 7 + y * 3 + seed) & 255), UInt8((x * 2 + y * 5 + seed * 2) & 255), UInt8((x ^ y ^ seed) & 255))
        }
    }

    private func target(_ name: Any?) throws -> AMG65StripTarget {
        try #require((name as? String).flatMap(AMG65StripTarget.init(rawValue:)))
    }

    // MARK: Layout and key actions

    @Test func layoutMatchesStudio() throws {
        let golden = try list("layout")
        #expect(AMG65Layout.keys.count == golden.count)
        for (key, g) in zip(AMG65Layout.keys, golden) {
            #expect(key.slot == g["slot"] as? Int)
            #expect(Int(key.code) == g["code"] as? Int)
            #expect(key.name == g["name"] as? String)
            #expect([key.rect.minX, key.rect.minY, key.rect.width, key.rect.height].map(Double.init) == g["rect"] as? [Double])
            #expect(key.remappable == g["remappable"] as? Bool)
            #expect(key.isKnob == g["isKnob"] as? Bool)
            #expect(key.id == key.slot)
        }
        #expect(AMG65Layout.litKeys.map(\.slot) == Self.golden["litKeySlots"] as? [Int])
        #expect(Set(AMG65Layout.keys.map(\.slot)).count == AMG65Layout.keys.count)
    }

    @Test func keyActionSlotsAndCodableMatchStudio() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let golden = try list("keyActions")
        #expect(golden.count > 60)
        for g in golden {
            let json = try #require(g["json"] as? String)
            // Studio's saved key maps decode as they are, and encode the same way.
            let action = try JSONDecoder().decode(AMG65KeyAction.self, from: Data(json.utf8))
            #expect(hex(action.slotBytes) == g["slot"] as? String, "\(json)")
            #expect(action.tested == g["tested"] as? Bool)
            #expect(String(decoding: try encoder.encode(action), as: UTF8.self) == json)
        }
        // A modifier usage becomes its modifier bit.
        #expect(AMG65KeyAction.key(modifiers: 0x01, code: 0xE3).slotBytes == [0x02, 0x09, 0x00, 0x00])
        #expect(AMG65KeyAction.media(0x00CD).slotBytes == [0x03, 0xCD, 0x00, 0x00])
    }

    @Test func keyNameTablesMatchStudio() throws {
        let groups = try list("hidGroups")
        #expect(AMG65HIDKeys.groups.map(\.name) == groups.compactMap { $0["name"] as? String })
        for (group, g) in zip(AMG65HIDKeys.groups, groups) {
            let keys = try #require(g["keys"] as? [[String: Any]])
            #expect(group.keys.map { Int($0.code) } == keys.compactMap { $0["code"] as? Int })
            #expect(group.keys.map(\.name) == keys.compactMap { $0["name"] as? String })
        }
        let names = try #require(Self.golden["hidNames"] as? [String])
        #expect(names.count == 256)
        for code in 0...255 {
            // Studio formats unknown usages as "Key %02X"; KeyMapper leaves that to the app.
            #expect((AMG65HIDKeys.name(UInt8(code)) ?? String(format: "Key %02X", code)) == names[code])
        }
        let media = try list("media")
        #expect(AMG65MediaKeys.all.map { Int($0.usage) } == media.compactMap { $0["usage"] as? Int })
        #expect(AMG65MediaKeys.all.map(\.name) == media.compactMap { $0["name"] as? String })
        let mouse = try list("mouse")
        #expect(AMG65MouseActions.buttons.map { Int($0.mask) } == mouse.compactMap { $0["mask"] as? Int })
        #expect(AMG65MouseActions.buttons.map(\.name) == mouse.compactMap { $0["name"] as? String })
        let modifiers = try list("modifiers")
        #expect(AMG65Modifier.allCases.map { Int($0.bit) } == modifiers.compactMap { $0["bit"] as? Int })
        #expect(AMG65Modifier.allCases.map(\.symbol) == modifiers.compactMap { $0["symbol"] as? String })
        #expect(AMG65Modifier.allCases.map(\.name) == modifiers.compactMap { $0["name"] as? String })
    }

    // MARK: Upload headers

    @Test func uploadHeadersMatchStudio() throws {
        for g in try list("lcdHeaders") {
            let blocks = try #require(g["blocks"] as? Int), slot = try #require(g["slot"] as? Int)
            #expect(hex(AMG65Protocol.lcdUploadHeader(blocks: blocks, slot: UInt8(slot))) == g["hex"] as? String)
        }
        #expect(AMG65Protocol.lcdUploadHeader(blocks: 3) == AMG65Protocol.lcdUploadHeader(blocks: 3, slot: 1))
        for g in try list("stripHeaders") {
            let blocks = try #require(g["blocks"] as? Int)
            #expect(hex(AMG65Protocol.stripUploadHeader(target: try target(g["target"]), blocks: blocks)) == g["hex"] as? String)
        }
    }

    // MARK: LED matrix

    @Test func stripFormatMatchesStudio() throws {
        #expect(AMG65StripFormat.position == Self.golden["stripPosition"] as? [Int])
        #expect(AMG65StripFormat.position.sorted() == Array(0..<315))
        for g in try list("stripTargets") {
            let t = try target(g["target"])
            #expect(Int(t.command) == g["command"] as? Int)
            #expect(t.maxFrames == g["maxFrames"] as? Int)
        }
    }

    @Test func stripBuffersMatchStudio() throws {
        let cases = try list("stripBuffers")
        #expect(cases.count == 62)
        for g in cases {
            let count = try #require(g["count"] as? Int), pixels = try #require(g["pixels"] as? Int)
            let seed = try #require(g["seed"] as? Int), delay = try #require(g["delay"] as? Int)
            let brightness = try #require(g["brightness"] as? Double)
            let animation = AMG65StripAnimation(frames: Self.stripFrames(count: count, pixels: pixels, seed: seed), name: "golden")
            let (bytes, blocks) = animation.buffer(delay: UInt16(delay), brightness: brightness, target: try target(g["target"]))
            let context = "\(count)×\(pixels) seed \(seed), delay \(delay), brightness \(brightness), \(g["target"] ?? "")"
            #expect(blocks == g["blocks"] as? Int, "\(context)")
            #expect(bytes.count == g["size"] as? Int, "\(context)")
            #expect(hex(bytes.prefix(64)) == g["head"] as? String, "\(context)")
            #expect(sha(bytes) == g["sha256"] as? String, "\(context)")
        }
    }

    @Test func scrollingTextMatchesStudio() throws {
        for g in try list("scrollingText") {
            let text = try #require(g["text"] as? String)
            let rgb = try #require(g["color"] as? [Int])
            let animation = AMG65StripAnimation.scrollingText(text, color: RGB24(r: UInt8(rgb[0]), g: UInt8(rgb[1]), b: UInt8(rgb[2])))
            #expect(animation.name == g["name"] as? String)
            #expect(animation.frames.count == g["frameCount"] as? Int)
            #expect(animation.frames.allSatisfy { $0.count == 315 })
            let processed = String(String(text.prefix(48)).uppercased().prefix(48))
            #expect(AMG65TinyFont.columns(processed).map(Int.init) == g["columns"] as? [Int], "\(text)")
            #expect(sha(animation.frames.flatMap { $0.flatMap { [$0.r, $0.g, $0.b] } }) == g["framesSha256"] as? String, "\(text)")
            let (bytes, blocks) = animation.buffer(delay: 10, brightness: 1, target: .animation)
            #expect(blocks == g["bufferBlocks"] as? Int)
            #expect(sha(bytes) == g["bufferSha256"] as? String, "\(text)")
        }
    }

    // MARK: LCD

    @Test func lcdBuffersMatchStudio() throws {
        let inputs: [String: ([CGImage], [Int])] = [
            "one": ([Self.pattern(seed: 0)], [100]),
            "three": ([Self.pattern(seed: 1), Self.pattern(seed: 2), Self.pattern(seed: 3)], [0, 3, 600]),
            "noDelays": ([Self.pattern(seed: 4), Self.pattern(seed: 5)], []),
            "extraDelays": ([Self.pattern(seed: 6), Self.pattern(seed: 7)], [40, 80, 120]),
            "negativeDelay": ([Self.pattern(seed: 9)], [-50]),
            "truncated": (Array(repeating: Self.pattern(seed: 8), count: 131), Array(repeating: 20, count: 131)),
            "scaled": ([AMG65LCDAnimation.scaled(Self.pattern(seed: 10, width: 480, height: 135), fill: true),
                        AMG65LCDAnimation.scaled(Self.pattern(seed: 11, width: 240, height: 45), fill: false)], [30, 50]),
        ]
        let cases = try list("lcdBuffers")
        #expect(cases.count == inputs.count)
        for g in cases {
            let name = try #require(g["name"] as? String)
            let (frames, delays) = try #require(inputs[name])
            let animation = AMG65LCDAnimation(frames: frames, delaysMs: delays, name: name)
            let (bytes, blocks) = animation.buffer()
            #expect(animation.truncated == g["truncated"] as? Bool, "\(name)")
            #expect(blocks == g["blocks"] as? Int, "\(name)")
            #expect(bytes.count == g["size"] as? Int, "\(name)")
            #expect(hex(bytes.prefix(256)) == g["header"] as? String, "\(name)")
            #expect(hex(bytes[256..<320]) == g["sample"] as? String, "\(name)")
            #expect(sha(bytes) == g["sha256"] as? String, "\(name)")
        }
    }

    @Test func lcdPixelsAreRGB565LittleEndian() {
        // Pixel (2, 0) of pattern 0 is (14, 4, 2): 0x0800 | 0x0020 | 0x0000.
        let (bytes, blocks) = AMG65LCDAnimation(frames: [Self.pattern(seed: 0)], delaysMs: [100], name: "x").buffer()
        #expect(blocks == (256 + 240 * 135 * 2 + 4095) / 4096)
        #expect(Array(bytes[256 + 4..<256 + 6]) == [0x20, 0x08])
        #expect(bytes.last == 0xFF)
    }

    // MARK: Loading files

    private func writeImage(_ name: String, type: String, frames: [CGImage], delays: [Double] = []) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("amg65-media-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, type as CFString, frames.count, nil))
        for (index, frame) in frames.enumerated() {
            let properties = index < delays.count
                ? [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delays[index]]] as CFDictionary : nil
            CGImageDestinationAddImage(destination, frame, properties)
        }
        #expect(CGImageDestinationFinalize(destination))
        return url
    }

    private func solid(_ width: Int, _ height: Int, _ r: UInt8, _ g: UInt8, _ b: UInt8) -> CGImage {
        Self.image(width: width, height: height) { _, _ in (r, g, b) }
    }

    @Test func gifsLoadScaledWithClampedDelays() throws {
        let red = solid(16, 9, 255, 0, 0)
        let url = try writeImage("red.gif", type: "com.compuserve.gif", frames: [red, red, red], delays: [0.05, 0.005, 1.0])
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let lcd = try #require(AMG65LCDAnimation.load(url: url, fill: true))
        #expect(lcd.name == "red.gif")
        #expect(lcd.frames.count == 3)
        #expect(lcd.frames.allSatisfy { $0.width == 240 && $0.height == 135 })
        #expect(lcd.delaysMs == [50, 20, 510])
        #expect(!lcd.truncated)

        let strip = try #require(AMG65StripAnimation.load(url: url))
        #expect(strip.frames.count == 3)
        #expect(strip.frames.allSatisfy { $0.count == 315 })
        let middle = strip.frames[0][2 * 63 + 31]
        #expect(middle.r >= 250 && middle.g <= 5 && middle.b <= 5)
    }

    @Test func mediaBudgetRejectsBeforeDecoding() throws {
        #expect(AMG65MediaBudget.source(URL(string: "https://example.com/a.gif")!, maxFrames: 10) == nil)
        #expect(AMG65LCDAnimation.load(url: URL(fileURLWithPath: "/nonexistent/amg65.gif"), fill: true) == nil)

        let tiny = solid(1, 1, 1, 2, 3)
        let many = try writeImage("many.gif", type: "com.compuserve.gif", frames: Array(repeating: tiny, count: 131))
        defer { try? FileManager.default.removeItem(at: many.deletingLastPathComponent()) }
        // 131 frames: too many for the LCD (130), fine for the LED matrix (260).
        #expect(AMG65LCDAnimation.load(url: many, fill: false) == nil)
        #expect(AMG65StripAnimation.load(url: many)?.frames.count == 131)

        let tooMany = try writeImage("too-many.gif", type: "com.compuserve.gif", frames: Array(repeating: tiny, count: 261))
        defer { try? FileManager.default.removeItem(at: tooMany.deletingLastPathComponent()) }
        #expect(AMG65StripAnimation.load(url: tooMany) == nil)

        let wide = try writeImage("wide.png", type: "public.png", frames: [solid(AMG65MediaBudget.maxDimension + 1, 1, 0, 0, 0)])
        defer { try? FileManager.default.removeItem(at: wide.deletingLastPathComponent()) }
        #expect(AMG65StripAnimation.load(url: wide) == nil)

        let empty = FileManager.default.temporaryDirectory.appendingPathComponent("amg65-empty-\(UUID().uuidString).gif")
        try Data().write(to: empty)
        defer { try? FileManager.default.removeItem(at: empty) }
        #expect(AMG65StripAnimation.load(url: empty) == nil)
    }
}
