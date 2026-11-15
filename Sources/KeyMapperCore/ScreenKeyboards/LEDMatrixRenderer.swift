import Foundation

// AI tool quotas and activity on the AMG65's 63 × 5 LED matrix.
// Ported from AMG65 Studio's renderer.py (github.com/kocakli/amg65-studio); output is checked pixel for pixel
// against it. Python semantics are kept on purpose: round() is round-half-even, % and // floor.

/// One provider's remaining allowance as the matrix shows it.
public struct LEDQuota: Equatable, Sendable {
    public var provider: String
    /// 0…100; nil when unknown.
    public var remainingPercent: Double?
    public var stale: Bool

    public init(provider: String, remainingPercent: Double?, stale: Bool) {
        self.provider = provider
        self.remainingPercent = remainingPercent
        self.stale = stale
    }
}

/// An observed AI tool state (from its lifecycle hooks), shown instead of the quotas while it matters.
public struct LEDActivity: Equatable, Sendable {
    public var provider: String
    /// queued, running, waiting_approval, waiting_input, completed, error
    public var state: String
    public var summary: String?
    public var expiresAt: TimeInterval
    public var stale: Bool

    public init(provider: String, state: String, summary: String? = nil, expiresAt: TimeInterval, stale: Bool = false) {
        self.provider = provider
        self.state = state
        self.summary = summary
        self.expiresAt = expiresAt
        self.stale = stale
    }
}

public enum LEDTextEffect: String, CaseIterable, Codable, Sendable { case none, scan, breathe, matrix, scroll }

public enum LEDMatrixRenderer {
    public static let width = 63
    public static let height = 5
    typealias RGB = (Int, Int, Int)

    static let providerColors: [String: RGB] = ["claude": (254, 90, 0), "codex": (123, 220, 176), "cursor": (134, 190, 248)]
    /// A = Claude, X = Codex, C = Cursor (the overview legend).
    public static let providers: [(id: String, letter: String)] = [("claude", "A"), ("codex", "X"), ("cursor", "C")]
    static let unknown: RGB = (132, 144, 157)
    static let black: RGB = (0, 0, 0)
    static let attention: RGB = (254, 180, 54)
    static let error: RGB = (250, 76, 90)

    static let font: [Character: [String]] = [
        "0": ["111", "101", "101", "101", "111"], "1": ["010", "110", "010", "010", "111"],
        "2": ["111", "001", "111", "100", "111"], "3": ["111", "001", "111", "001", "111"],
        "4": ["101", "101", "111", "001", "001"], "5": ["111", "100", "111", "001", "111"],
        "6": ["111", "100", "111", "101", "111"], "7": ["111", "001", "010", "010", "010"],
        "8": ["111", "101", "111", "101", "111"], "9": ["111", "101", "111", "001", "111"],
        "A": ["010", "101", "111", "101", "101"], "C": ["011", "100", "100", "100", "011"],
        "D": ["110", "101", "101", "101", "110"], "E": ["111", "100", "110", "100", "111"],
        "L": ["100", "100", "100", "100", "111"], "O": ["111", "101", "101", "101", "111"],
        "R": ["110", "101", "110", "101", "101"], "S": ["011", "100", "010", "001", "110"],
        "U": ["101", "101", "101", "101", "111"], "X": ["101", "101", "010", "101", "101"],
        "-": ["000", "000", "111", "000", "000"], "%": ["101", "001", "010", "100", "101"],
        "?": ["111", "001", "011", "000", "010"], " ": ["0", "0", "0", "0", "0"],
        "B": ["110", "101", "110", "101", "110"], "F": ["111", "100", "110", "100", "100"],
        "G": ["011", "100", "101", "101", "011"], "H": ["101", "101", "111", "101", "101"],
        "I": ["111", "010", "010", "010", "111"], "J": ["001", "001", "001", "101", "010"],
        "K": ["101", "110", "100", "110", "101"], "M": ["10001", "11011", "10101", "10001", "10001"],
        "N": ["1001", "1101", "1011", "1001", "1001"], "P": ["110", "101", "110", "100", "100"],
        "Q": ["111", "101", "101", "111", "001"], "T": ["111", "010", "010", "010", "010"],
        "V": ["101", "101", "101", "101", "010"], "W": ["10001", "10001", "10101", "11011", "01010"],
        "Y": ["101", "101", "010", "010", "010"], "Z": ["111", "001", "010", "100", "111"],
        ".": ["0", "0", "0", "0", "1"], ":": ["0", "1", "0", "1", "0"], "!": ["1", "1", "1", "0", "1"],
        "/": ["001", "001", "010", "100", "100"],
    ]

    static let stateIcons: [String: [String]] = [
        "queued": ["01110", "10001", "10101", "10001", "01110"],
        "waiting_approval": ["00100", "00100", "00100", "00000", "00100"],
        "waiting_input": ["01110", "00010", "00100", "00000", "00100"],
        "completed": ["00001", "00010", "10100", "01000", "00000"],
        "error": ["10001", "01010", "00100", "01010", "10001"],
    ]

    public static let activityLabels = ["running": "RUN", "queued": "QUEUE", "waiting_approval": "ASK",
                                        "waiting_input": "INPUT", "completed": "DONE", "error": "ERROR"]
    static let activityPriority = ["waiting_approval": 5, "waiting_input": 5, "error": 4, "running": 3, "queued": 2, "completed": 1]
    static let workLabels = ["working": "RUN", "using_tool": "TOOL", "running_command": "EXEC", "reading_files": "READ",
                             "editing_files": "EDIT", "searching": "FIND", "compacting": "CTX", "input_received": "READY"]

    // MARK: Python-compatible arithmetic

    /// Python's round(): half to even.
    static func pyRound(_ value: Double) -> Int { Int(value.rounded(.toNearestOrEven)) }
    /// Python's % (result has the divisor's sign).
    static func pyMod(_ a: Int, _ b: Int) -> Int { let r = a % b; return r != 0 && (r < 0) != (b < 0) ? r + b : r }
    static func scaled(_ rgb: RGB, _ factor: Double) -> RGB { (pyRound(Double(rgb.0) * factor), pyRound(Double(rgb.1) * factor), pyRound(Double(rgb.2) * factor)) }

    static func clampedBrightness(_ value: Double) -> Double { value.isFinite ? min(max(value, 0), 1) : 0.4 }

    static func value(_ quota: LEDQuota?) -> Double? {
        guard let v = quota?.remainingPercent, v.isFinite, (0...100).contains(v) else { return nil }
        return v
    }

    static func providerRGB(_ provider: String, gain: Double) -> RGB {
        let rgb = providerColors[provider] ?? unknown
        // A per-user, Claude-only green balance (some keys render its orange too yellow).
        return provider == "claude" ? (rgb.0, pyRound(Double(rgb.1) * gain), rgb.2) : rgb
    }

    static func color(_ quota: LEDQuota, brightness: Double, gain: Double) -> RGB {
        let factor = brightness * (quota.stale ? 0.45 : 1.0)
        let rgb = value(quota) != nil ? providerRGB(quota.provider, gain: gain) : unknown
        return scaled((min(254, rgb.0), min(254, rgb.1), min(254, rgb.2)), factor)
    }

    // MARK: Drawing

    static func draw(_ pixels: inout [RGB], text: String, x start: Int, color: RGB, right: Int = 56) {
        var x = start
        for character in text {
            let glyph = font[character] ?? font["?"]!
            for (y, row) in glyph.enumerated() {
                for (dx, bit) in row.enumerated() where bit == "1" && 0 <= x + dx && x + dx < right {
                    pixels[y * width + x + dx] = color
                }
            }
            x += glyph[0].count + 1
        }
    }

    /// Bitmap width including only the spacing between characters.
    public static func textWidth(_ text: String) -> Int {
        max(0, text.reduce(0) { $0 + (font[$1] ?? font["?"]!)[0].count + 1 } - 1)
    }

    static func icon(_ pixels: inout [RGB], rows: [String], x: Int, color: RGB) {
        for (y, row) in rows.enumerated() {
            for (dx, bit) in row.enumerated() where bit == "1" && 0 <= x + dx && x + dx < width {
                pixels[y * width + x + dx] = color
            }
        }
    }

    /// Three meters at the right edge (columns 57, 59, 61): a level per 20 %, a dim baseline for 0,
    /// a middle dot for unknown.
    static func bars(_ pixels: inout [RGB], _ quotas: [LEDQuota], brightness: Double, gain: Double) {
        for (index, quota) in quotas.enumerated() {
            let x = 57 + index * 2
            let color = color(quota, brightness: brightness, gain: gain)
            guard let value = value(quota) else {
                pixels[2 * width + x] = color
                continue
            }
            let level = Int((value / 20).rounded(.up))
            for y in 0..<5 { pixels[y * width + x] = y >= 5 - level ? color : (color.0 / 10, color.1 / 10, color.2 / 10) }
        }
    }

    static func quotas(_ list: [LEDQuota]) -> [LEDQuota] {
        providers.map { provider in list.first { $0.provider == provider.id } ?? LEDQuota(provider: provider.id, remainingPercent: nil, stale: false) }
    }

    static func frame(_ pixels: [RGB]) -> [RGB24] {
        pixels.map { RGB24(r: UInt8(clamping: $0.0), g: UInt8(clamping: $0.1), b: UInt8(clamping: $0.2)) }
    }

    // MARK: Screens

    /// Three quota cells (A / X / C with the remaining %) and three meters. Stale values are dimmed with an
    /// amber marker; unknown values show "--". Nothing is inferred from errors.
    public static func overview(_ list: [LEDQuota], brightness: Double = 0.4, claudeGreenGain: Double = 1) -> [RGB24] {
        let brightness = clampedBrightness(brightness), gain = clampedBrightness(claudeGreenGain)
        var pixels = [RGB](repeating: black, count: width * height)
        let quotas = quotas(list)
        for (index, provider) in providers.enumerated() {
            let quota = quotas[index]
            let text = value(quota).map { String(pyRound($0)) } ?? "--"
            let left = index * 19
            let color = color(quota, brightness: brightness, gain: gain)
            draw(&pixels, text: provider.letter, x: left, color: color, right: left + 3)
            draw(&pixels, text: text, x: left + 16 - textWidth(text), color: color, right: left + 16)
            if quota.stale { pixels[min(55, left + 17)] = scaled(attention, brightness) }
        }
        bars(&pixels, quotas, brightness: brightness, gain: gain)
        return frame(pixels)
    }

    /// One provider's full name and its remaining percentage, with a meter.
    public static func detail(_ quota: LEDQuota, brightness: Double = 0.4, claudeGreenGain: Double = 1) -> [RGB24] {
        let brightness = clampedBrightness(brightness), gain = clampedBrightness(claudeGreenGain)
        var pixels = [RGB](repeating: black, count: width * height)
        let label = ["claude": "CLAUDE", "codex": "CODEX", "cursor": "CURSOR"][quota.provider] ?? "?"
        let color = color(quota, brightness: brightness, gain: gain)
        draw(&pixels, text: label, x: 1, color: color)
        let value = value(quota)
        let text = value.map { "\(pyRound($0))%" } ?? "--"
        draw(&pixels, text: text, x: 51 - textWidth(text), color: color, right: 51)
        if quota.stale {
            draw(&pixels, text: "?", x: 58, color: scaled(attention, brightness), right: 63)
        } else if let value {
            let level = Int((value / 20).rounded(.up))
            for x in [58, 59, 60] {
                for y in 0..<5 { pixels[y * width + x] = y >= 5 - level ? color : (color.0 / 10, color.1 / 10, color.2 / 10) }
            }
        } else {
            draw(&pixels, text: "?", x: 58, color: color, right: 63)
        }
        return frame(pixels)
    }

    /// Custom text (uppercase ASCII), centred when it fits and scrolled at 2 px/s otherwise;
    /// `marquee` always scrolls, repeating with a ten-pixel gap.
    public static func text(_ text: String, color: RGB24, brightness: Double, elapsed: Double = 0, marquee: Bool = false) -> [RGB24] {
        let brightness = clampedBrightness(brightness)
        let rgb = scaled((min(254, Int(color.r)), min(254, Int(color.g)), min(254, Int(color.b))), brightness)
        let textWidth = textWidth(text)
        let step = Int(max(0, elapsed) * 2)
        var pixels = [RGB](repeating: black, count: width * height)
        if marquee {
            let period = max(1, textWidth + 10)
            var x = pyMod(-step, period) - period
            while x < 56 {
                draw(&pixels, text: text, x: x, color: rgb)
                x += period
            }
        } else {
            let x = textWidth <= 56 ? max(0, (56 - textWidth) / 2) : 56 - pyMod(step, textWidth + 68)
            draw(&pixels, text: text, x: x, color: rgb)
        }
        icon(&pixels, rows: ["11111", "00100", "00100", "00100", "00100"], x: 58, color: rgb)
        return frame(pixels)
    }

    /// Keeps the hue when brightening: the factor is limited once instead of clipping each channel.
    static func scaleKeepingHue(_ rgb: RGB, _ factor: Double) -> RGB {
        let peak = max(rgb.0, rgb.1, rgb.2)
        let limited = peak > 0 ? min(factor, 254 / Double(peak)) : factor
        return scaled(rgb, limited)
    }

    /// Animates a text frame (left of the gauge only). Attention screens are never decorated.
    public static func applyTextEffect(_ frame: [RGB24], effect: LEDTextEffect, brightness: Double = 0.4,
                                       elapsed: Double = 0, left: Int = 0) -> [RGB24] {
        let brightness = clampedBrightness(brightness)
        precondition(frame.count == width * height && (0..<56).contains(left))
        let source: [RGB] = frame.map { (Int($0.r), Int($0.g), Int($0.b)) }
        var pixels = source
        if effect == .none || brightness == 0 { return frame }
        let step = Int(max(0, elapsed) * 2)
        switch effect {
        case .none:
            break
        case .scroll:
            let span = 56 - left
            let offset = pyMod(step, span + 8)
            for y in 0..<height {
                for x in 0..<span {
                    let from = pyMod(x + offset, span + 8)
                    pixels[y * width + left + x] = from < span ? source[y * width + left + from] : black
                }
            }
        case .breathe:
            let factor = 0.92 + 0.08 * cos(Double(step) * 2 * .pi / 12)
            for y in 0..<height { for x in left..<56 { pixels[y * width + x] = scaleKeepingHue(source[y * width + x], factor) } }
        case .scan:
            let head = pyMod(step * 3, 64) - 4
            for y in 0..<height {
                for x in left..<56 {
                    let distance = abs(x - head)
                    let factor = distance < 2 ? 1.25 : distance < 4 ? 1.05 : 0.85
                    pixels[y * width + x] = scaleKeepingHue(source[y * width + x], factor)
                }
            }
        case .matrix:
            // Whole glyphs (split on empty columns) wrap downward, then settle; rain only fills empty pixels.
            let columns = (left..<56).filter { x in (0..<height).contains { source[$0 * width + x] != black } }
            var groups: [[Int]] = []
            for x in columns {
                if let last = groups.last?.last, x == last + 1 { groups[groups.count - 1].append(x) } else { groups.append([x]) }
            }
            for y in 0..<height { for x in left..<56 { pixels[y * width + x] = black } }
            let phase = pyMod(step, 11)
            for (index, group) in groups.enumerated() {
                let fall = phase - pyMod(index, 3)
                let offset = 0 < fall && fall < height ? fall : 0
                for x in group { for y in 0..<height { pixels[pyMod(y + offset, height) * width + x] = source[y * width + x] } }
            }
            for x in stride(from: left + 2, to: 56, by: 5) {
                let head = pyMod(step + (x / 5) * 3, 11) - 3
                for tail in 0..<3 {
                    let y = head - tail
                    if 0 <= y && y < height, pixels[y * width + x] == black {
                        pixels[y * width + x] = scaleKeepingHue((20, 168, 72), brightness * 0.24 / Double(tail + 1))
                    }
                }
            }
        }
        return LEDMatrixRenderer.frame(pixels)
    }

    // MARK: Activity

    /// Fixed state words only; tool names, prompts and file names never reach the display.
    public static func activityLabel(_ activity: LEDActivity) -> String {
        if activity.state == "running" { return activity.summary.flatMap { workLabels[$0] } ?? "RUN" }
        return activityLabels[activity.state] ?? ""
    }

    /// Prefers attention events and rotates equally urgent providers; working states leave 4 s of every 10 s
    /// for the quotas.
    public static func selectActivity(_ list: [LEDActivity], elapsed: Double, now: TimeInterval, provider: String = "all") -> LEDActivity? {
        guard ["all", "claude", "codex", "cursor"].contains(provider) else { return nil }
        let candidates = list.filter { row in
            providerColors[row.provider] != nil && activityLabels[row.state] != nil
                && (provider == "all" || row.provider == provider)
                && row.expiresAt.isFinite && row.expiresAt > now && !row.stale
        }
        guard let priority = candidates.compactMap({ activityPriority[$0.state] }).max() else { return nil }
        let rows = candidates.filter { activityPriority[$0.state] == priority }
        let seconds = Int(max(0, elapsed))
        if provider == "all", [2, 3].contains(priority), seconds % 10 >= 6 { return nil }
        return rows[Int(max(0, elapsed) / 4) % rows.count]
    }

    /// State icon, provider name, state word and the three meters.
    public static func activity(_ activity: LEDActivity, quotas list: [LEDQuota], brightness: Double = 0.4,
                                elapsed: Double = 0, claudeGreenGain: Double = 1) -> [RGB24] {
        let brightness = clampedBrightness(brightness), gain = clampedBrightness(claudeGreenGain)
        var pixels = [RGB](repeating: black, count: width * height)
        guard providerColors[activity.provider] != nil, activityLabels[activity.state] != nil else { return frame(pixels) }
        let color = scaled(providerRGB(activity.provider, gain: gain), brightness)
        let label = ["codex": "CODEX", "claude": "CLAUDE", "cursor": "CURSOR"][activity.provider]!
        draw(&pixels, text: label, x: 7, color: color, right: 30)
        draw(&pixels, text: activityLabel(activity), x: 32, color: color, right: 53)
        if activity.state == "running" {
            let orbit = [(2, 0), (4, 2), (2, 4), (0, 2)]
            let active = Int(max(0, elapsed) * 2) % orbit.count
            for (index, point) in orbit.enumerated() {
                pixels[point.1 * width + point.0] = index == active ? color : (color.0 / 5, color.1 / 5, color.2 / 5)
            }
            pixels[2 * width + 2] = color
        } else {
            let accent = ["waiting_approval", "waiting_input"].contains(activity.state) ? attention
                : activity.state == "error" ? error : providerRGB(activity.provider, gain: gain)
            icon(&pixels, rows: stateIcons[activity.state]!, x: 0, color: scaled(accent, brightness))
        }
        bars(&pixels, quotas(list), brightness: brightness, gain: gain)
        return frame(pixels)
    }

    // Original five-row characters drawn for AMG65 Studio (not official brand mascots).
    static let mascots: [String: [String]] = [
        "claude": ["00111111100", "11101110111", "00111111100", "00111111100", "00101010100"],
        "codex": ["00000100000", "00111111100", "01101110110", "00111111100", "00011011000"],
        "cursor": ["00000001000", "00111111100", "11110111111", "00111111100", "00000001000"],
    ]
    static let claudeWalkLegs = ["01010010100", "00101001010"]

    /// The provider's character walking (running) or posing, its letter, the state word and the meters.
    public static func mascot(_ activity: LEDActivity, quotas list: [LEDQuota], brightness: Double = 0.4,
                              elapsed: Double = 0, claudeGreenGain: Double = 1) -> [RGB24] {
        let brightness = clampedBrightness(brightness), gain = clampedBrightness(claudeGreenGain)
        guard var rows = mascots[activity.provider], activityLabels[activity.state] != nil else {
            return self.activity(activity, quotas: list, brightness: brightness, elapsed: elapsed, claudeGreenGain: gain)
        }
        var pixels = [RGB](repeating: black, count: width * height)
        let state = activity.state, provider = activity.provider
        let step = Int(max(0, elapsed) * 2)
        var x = 3, facing = 0
        let providerColor = scaled(providerRGB(provider, gain: gain), brightness)
        var color = providerColor
        if state == "running" {
            let travel = step % 12
            x = 1 + 2 * (travel <= 6 ? travel : 12 - travel)
            facing = 0 < travel && travel <= 6 ? 1 : -1
            if provider == "claude" {
                rows[4] = claudeWalkLegs[step % 2]
            } else if provider == "codex" {
                rows[4] = ["00011011000", "00110001100"][step % 2]
                rows[0] = ["00000100000", "00000010000"][step % 2]
            } else if step % 2 == 1 {
                rows[2] = "11111011111"
            }
        } else if state == "completed" {
            x = 5
            if step % 2 == 1 { rows[0] = ["claude": "10111111101", "codex": "01000100010", "cursor": "10000001001"][provider]! }
        } else if state == "error" {
            color = scaleKeepingHue(color, 0.55)
        }
        if facing != 0 && provider == "claude" {
            var eyes = [Character](repeating: "1", count: 11)
            for eye in [3 + facing, 7 + facing] { eyes[eye] = "0" }
            rows[1] = String(eyes)
        } else if facing == -1 && provider == "cursor" {
            rows = rows.map { String($0.reversed()) }
        }
        icon(&pixels, rows: rows, x: x, color: color)
        if state != "running" {
            let accent = ["waiting_approval", "waiting_input"].contains(state) ? attention : state == "error" ? error : providerRGB(provider, gain: gain)
            icon(&pixels, rows: stateIcons[state]!, x: 18, color: scaled(accent, brightness))
        }
        let letter = providers.first { $0.id == provider }!.letter
        draw(&pixels, text: letter, x: 26, color: providerColor, right: 29)
        let stateColor = state == "error" ? scaled(error, brightness) : providerColor
        draw(&pixels, text: activityLabel(activity), x: 32, color: stateColor, right: 53)
        bars(&pixels, quotas(list), brightness: brightness, gain: gain)
        return frame(pixels)
    }
}
