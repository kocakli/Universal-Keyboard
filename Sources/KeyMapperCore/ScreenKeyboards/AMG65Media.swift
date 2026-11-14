import CoreGraphics
import Foundation
import ImageIO

// LEOBOG AMG65 LCD images and LED-matrix animations, as upload buffers for `AMG65Link.upload`.
// Ported from AMG65 Studio (github.com/kocakli/amg65-studio), which builds on aumbro/leobog_amg65_rgb (MIT).
// Buffers are byte for byte Studio's (checked against Fixtures/amg65-media-golden.json); see THIRD_PARTY_NOTICES.md.

/// Limits checked before any image is decoded. Only thumbnails are decoded.
public enum AMG65MediaBudget {
    public static let maxBytes = 32 * 1024 * 1024
    public static let maxDimension = 8192
    public static let maxPixels = 32 * 1024 * 1024

    /// A source for a regular file of 1…`maxBytes` bytes with 1…`maxFrames` frames, each frame within
    /// `maxDimension` × `maxDimension` and `maxPixels`; nil otherwise.
    public static func source(_ url: URL, maxFrames: Int) -> CGImageSource? {
        guard url.isFileURL,
              let attrs = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              attrs.isRegularFile == true, let size = attrs.fileSize, size > 0, size <= maxBytes,
              let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              (1...maxFrames).contains(CGImageSourceGetCount(source)) else { return nil }
        for i in 0..<CGImageSourceGetCount(source) {
            guard let props = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [CFString: Any],
                  let w = props[kCGImagePropertyPixelWidth] as? Int,
                  let h = props[kCGImagePropertyPixelHeight] as? Int,
                  w > 0, h > 0, w <= maxDimension, h <= maxDimension, w * h <= maxPixels else { return nil }
        }
        return source
    }

    static func thumbnail(_ source: CGImageSource, index: Int, dimension: Int) -> CGImage? {
        CGImageSourceCreateThumbnailAtIndex(source, index, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: dimension,
            kCGImageSourceShouldCacheImmediately: false,
        ] as CFDictionary)
    }
}

// MARK: - LCD (command 0x72), confirmed on the keyboard

public enum AMG65LCDFormat {
    public static let width = 240, height = 135
    /// [0] frame count, [1 + i] delay of frame i in 2 ms units.
    public static let header = 256
    public static let maxFrames = 130
    public static let block = 4096
    /// The only slot tested so far.
    public static let slot: UInt8 = 1
}

/// Frames for the 240 × 135 LCD.
public struct AMG65LCDAnimation {
    /// Frames as uploaded; `load` scales them to 240 × 135, other sizes are stretched by `buffer()`.
    public var frames: [CGImage]
    public var delaysMs: [Int]
    public var name: String

    public init(frames: [CGImage], delaysMs: [Int], name: String) {
        self.frames = frames
        self.delaysMs = delaysMs
        self.name = name
    }

    /// More frames than the LCD takes; only the first `AMG65LCDFormat.maxFrames` are uploaded.
    public var truncated: Bool { frames.count > AMG65LCDFormat.maxFrames }
    public var uploadFrames: [CGImage] { Array(frames.prefix(AMG65LCDFormat.maxFrames)) }

    /// The whole upload: FF-filled, the header, then RGB565 little-endian frames, padded to 4 KB blocks.
    public func buffer() -> (bytes: [UInt8], blocks: Int) {
        let frames = uploadFrames
        let frameBytes = AMG65LCDFormat.width * AMG65LCDFormat.height * 2
        let size = AMG65LCDFormat.header + frames.count * frameBytes
        let blocks = (size + AMG65LCDFormat.block - 1) / AMG65LCDFormat.block
        var buf = [UInt8](repeating: 0xFF, count: blocks * AMG65LCDFormat.block)
        buf[0] = UInt8(frames.count)
        for (i, d) in delaysMs.prefix(frames.count).enumerated() { buf[1 + i] = UInt8(max(1, min(255, d / 2))) }
        for (i, frame) in frames.enumerated() {
            let px = Self.rgba(frame)
            var o = AMG65LCDFormat.header + i * frameBytes
            for p in stride(from: 0, to: px.count, by: 4) {
                let v = (UInt16(px[p] & 0xF8) << 8) | (UInt16(px[p + 1] & 0xFC) << 3) | UInt16(px[p + 2] >> 3)
                buf[o] = UInt8(v & 0xFF); buf[o + 1] = UInt8(v >> 8)
                o += 2
            }
        }
        return (buf, blocks)
    }

    /// The frame drawn into a 240 × 135 RGBX bitmap.
    static func rgba(_ image: CGImage) -> [UInt8] {
        let width = AMG65LCDFormat.width, height = AMG65LCDFormat.height
        var px = [UInt8](repeating: 0, count: width * height * 4)
        px.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return px
    }

    /// Loads a GIF / PNG / JPEG within `AMG65MediaBudget` (at most 130 frames) and scales every frame to
    /// 240 × 135: `fill` crops to cover, otherwise the frame fits with black bars. GIF delays are clamped to
    /// 20…510 ms (100 ms when missing). Nil when the file is out of budget or no frame decodes.
    public static func load(url: URL, fill: Bool) -> AMG65LCDAnimation? {
        guard let src = AMG65MediaBudget.source(url, maxFrames: AMG65LCDFormat.maxFrames) else { return nil }
        let count = CGImageSourceGetCount(src)
        var frames: [CGImage] = [], delays: [Int] = []
        for i in 0..<count {
            guard let img = AMG65MediaBudget.thumbnail(src, index: i, dimension: 480) else { continue }
            frames.append(scaled(img, fill: fill))
            let props = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [CFString: Any]
            let gif = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let d = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double) ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
            delays.append(d.isFinite ? Int(max(20, min(510, d * 1000))) : 100)
        }
        return frames.isEmpty ? nil : AMG65LCDAnimation(frames: frames, delaysMs: delays, name: url.lastPathComponent)
    }

    /// The image on a black 240 × 135 canvas, centred: `fill` scales it to cover the canvas, otherwise to fit.
    public static func scaled(_ image: CGImage, fill: Bool) -> CGImage {
        let w = CGFloat(AMG65LCDFormat.width), h = CGFloat(AMG65LCDFormat.height)
        guard let ctx = CGContext(data: nil, width: AMG65LCDFormat.width, height: AMG65LCDFormat.height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return image }
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.interpolationQuality = .high
        let iw = CGFloat(image.width), ih = CGFloat(image.height)
        let s = fill ? max(w / iw, h / ih) : min(w / iw, h / ih)
        let dw = iw * s, dh = ih * s
        ctx.draw(image, in: CGRect(x: (w - dw) / 2, y: (h - dh) / 2, width: dw, height: dh))
        return ctx.makeImage() ?? image
    }
}

// MARK: - LED matrix (command 0x33 animation / 0x31 boot animation), confirmed on the keyboard

/// The 63 × 5 LED matrix as an upload target (Studio calls it the LED strip).
public enum AMG65StripFormat {
    public static let width = 63, height = 5, leds = 315

    /// Row-major pixel → LED index (4 panels of 14 × 5, then one of 7 × 5). Same as the vendor app's table at 0x59c7f0.
    public static let position: [Int] = (0..<height).flatMap { r in
        (0..<width).map { c in c < 56 ? 70 * (c / 14) + 14 * r + c % 14 : 280 + 7 * r + (c - 56) }
    }
}

public enum AMG65StripTarget: String, CaseIterable, Identifiable, Codable, Sendable {
    /// The matrix's own animation (command 0x33, up to 260 frames).
    case animation
    /// The boot animation (command 0x31, up to 200 frames).
    case boot

    public var id: String { rawValue }
    public var command: UInt8 { self == .animation ? 0x33 : 0x31 }
    public var maxFrames: Int { self == .animation ? 260 : 200 }
}

/// Frames of 63 × 5 RGB pixels (row-major) for the LED matrix.
public struct AMG65StripAnimation: Equatable, Sendable {
    public var frames: [[RGB24]]
    public var name: String

    public init(frames: [[RGB24]], name: String) {
        self.frames = frames
        self.name = name
    }

    /// Estimated time per frame on the keyboard for a delay word: ≈ 75 ms + 2.2 ms × delay
    /// (Studio's user timings: delay 20 ≈ 118 ms, 80 ≈ 250 ms).
    public static func estimatedFrameMs(delay: UInt16) -> Double { 75 + 2.2 * Double(delay) }

    /// The whole upload: frame count and delay (little endian), the first `target.maxFrames` frames as RGB in LED
    /// order scaled by `brightness` (0…1), AA 55 after the last frame, zero-padded to 4 KB blocks.
    public func buffer(delay: UInt16, brightness: Double, target: AMG65StripTarget) -> (bytes: [UInt8], blocks: Int) {
        let frames = Array(self.frames.prefix(target.maxFrames))
        let end = 4 + frames.count * AMG65StripFormat.leds * 3
        let blocks = (end + 2 + 4095) / 4096
        var buf = [UInt8](repeating: 0, count: blocks * 4096)
        buf[0] = UInt8(frames.count & 0xFF); buf[1] = UInt8(frames.count >> 8)
        buf[2] = UInt8(delay & 0xFF); buf[3] = UInt8(delay >> 8)
        let k = max(0, min(1, brightness))
        for (f, frame) in frames.enumerated() {
            for (i, c) in frame.enumerated() where i < AMG65StripFormat.leds {
                let o = 4 + 3 * (f * AMG65StripFormat.leds + AMG65StripFormat.position[i])
                buf[o] = UInt8(Double(c.r) * k); buf[o + 1] = UInt8(Double(c.g) * k); buf[o + 2] = UInt8(Double(c.b) * k)
            }
        }
        buf[end] = 0xAA; buf[end + 1] = 0x55
        return (buf, blocks)
    }

    /// A GIF / PNG / JPEG within `AMG65MediaBudget` (at most 260 frames), every frame scaled to 63 × 5.
    public static func load(url: URL) -> AMG65StripAnimation? {
        guard let src = AMG65MediaBudget.source(url, maxFrames: 260) else { return nil }
        var frames: [[RGB24]] = []
        for i in 0..<CGImageSourceGetCount(src) {
            if let img = AMG65MediaBudget.thumbnail(src, index: i, dimension: 126) { frames.append(pixels(img)) }
        }
        return frames.isEmpty ? nil : AMG65StripAnimation(frames: frames, name: url.lastPathComponent)
    }

    /// The image drawn into 63 × 5 pixels.
    static func pixels(_ image: CGImage) -> [RGB24] {
        let w = AMG65StripFormat.width, h = AMG65StripFormat.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        px.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return }
            ctx.interpolationQuality = .medium
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return stride(from: 0, to: px.count, by: 4).map { RGB24(r: px[$0], g: px[$0 + 1], b: px[$0 + 2]) }
    }

    /// Text scrolling right to left in a 3 × 5 pixel font: one frame per column, from blank to blank.
    /// At most 48 characters, shown in capitals; characters the font lacks are drawn as "?".
    public static func scrollingText(_ text: String, color: RGB24) -> AMG65StripAnimation {
        let columns = AMG65TinyFont.columns(String(String(text.prefix(48)).uppercased().prefix(48)))
        let total = columns.count + AMG65StripFormat.width
        var frames: [[RGB24]] = []
        for shift in 0..<total {
            var f = [RGB24](repeating: .off, count: AMG65StripFormat.leds)
            for x in 0..<AMG65StripFormat.width {
                let col = x + shift - AMG65StripFormat.width
                guard col >= 0, col < columns.count else { continue }
                for y in 0..<5 where columns[col] & (1 << y) != 0 { f[y * AMG65StripFormat.width + x] = color }
            }
            frames.append(f)
        }
        return AMG65StripAnimation(frames: frames, name: "“\(String(text.prefix(48)))”")
    }
}

/// 3 × 5 pixel font. Each glyph is 3 columns; bit y (0 = top) set = lit.
enum AMG65TinyFont {
    private static let rows: [Character: [String]] = [
        "A": ["010", "101", "111", "101", "101"], "B": ["110", "101", "110", "101", "110"],
        "C": ["011", "100", "100", "100", "011"], "D": ["110", "101", "101", "101", "110"],
        "E": ["111", "100", "110", "100", "111"], "F": ["111", "100", "110", "100", "100"],
        "G": ["011", "100", "101", "101", "011"], "H": ["101", "101", "111", "101", "101"],
        "I": ["111", "010", "010", "010", "111"], "J": ["001", "001", "001", "101", "010"],
        "K": ["101", "101", "110", "101", "101"], "L": ["100", "100", "100", "100", "111"],
        "M": ["101", "111", "111", "101", "101"], "N": ["110", "101", "101", "101", "101"],
        "O": ["010", "101", "101", "101", "010"], "P": ["110", "101", "110", "100", "100"],
        "Q": ["010", "101", "101", "110", "011"], "R": ["110", "101", "110", "101", "101"],
        "S": ["011", "100", "010", "001", "110"], "T": ["111", "010", "010", "010", "010"],
        "U": ["101", "101", "101", "101", "111"], "V": ["101", "101", "101", "101", "010"],
        "W": ["101", "101", "111", "111", "101"], "X": ["101", "101", "010", "101", "101"],
        "Y": ["101", "101", "010", "010", "010"], "Z": ["111", "001", "010", "100", "111"],
        "0": ["111", "101", "101", "101", "111"], "1": ["010", "110", "010", "010", "111"],
        "2": ["110", "001", "010", "100", "111"], "3": ["110", "001", "010", "001", "110"],
        "4": ["101", "101", "111", "001", "001"], "5": ["111", "100", "110", "001", "110"],
        "6": ["011", "100", "111", "101", "111"], "7": ["111", "001", "010", "010", "010"],
        "8": ["111", "101", "111", "101", "111"], "9": ["111", "101", "111", "001", "110"],
        "!": ["010", "010", "010", "000", "010"], "?": ["110", "001", "010", "000", "010"],
        ".": ["000", "000", "000", "000", "010"], ",": ["000", "000", "000", "010", "100"],
        ":": ["000", "010", "000", "010", "000"], "-": ["000", "000", "111", "000", "000"],
        "+": ["000", "010", "111", "010", "000"], "'": ["010", "010", "000", "000", "000"],
        "/": ["001", "001", "010", "100", "100"], "#": ["101", "111", "101", "111", "101"],
        "<": ["001", "010", "100", "010", "001"], ">": ["100", "010", "001", "010", "100"],
        "%": ["101", "001", "010", "100", "101"], "=": ["000", "111", "000", "111", "000"],
        " ": ["000", "000", "000", "000", "000"],
    ]

    /// Column bitmaps of `text`, one blank column after each glyph.
    static func columns(_ text: String) -> [UInt8] {
        var out: [UInt8] = []
        for ch in text {
            let g = rows[ch] ?? rows["?"]!
            for c in 0..<3 {
                var bits: UInt8 = 0
                for y in 0..<5 where Array(g[y])[c] == "1" { bits |= 1 << y }
                out.append(bits)
            }
            out.append(0)
        }
        return out
    }
}
