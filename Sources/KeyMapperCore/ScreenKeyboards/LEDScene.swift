import Foundation

/// What the AMG65 LED matrix shows while KeyMapper streams to it. Defaults follow AMG65 Studio.
public struct LEDDisplaySettings: Codable, Equatable, Sendable {
    public enum Mode: String, Codable, CaseIterable, Sendable {
        /// The three quotas side by side.
        case overview
        /// Overview for 12 s, then each provider for 4 s.
        case rotate
        /// The custom text.
        case text
    }

    /// Stream to the matrix at all (off: the keyboard shows its own animation).
    public var enabled = false
    public var mode: Mode = .overview
    /// 0…1.
    public var brightness = 0.4
    /// Uppercase printable ASCII, at most 48 characters.
    public var text = "KEYMAPPER"
    public var textColor = RGB24(r: 0x7B, g: 0xDC, b: 0xB0)
    public var textEffect: LEDTextEffect = .none
    /// Show observed AI tool activity (needs the activity hooks).
    public var activityEnabled = true
    /// Show activity as the provider's walking character.
    public var mascotEnabled = false
    /// "all", or one provider shown on its own.
    public var trackedProvider = "all"
    /// Claude-only green balance for keyboards that render its orange too yellow.
    public var claudeGreenGain = 1.0

    public init() {}

    public static let maximumTextLength = 48

    /// Keeps only characters the matrix font can draw, uppercased and bounded.
    public static func sanitized(_ text: String) -> String {
        let upper = text.uppercased()
        let allowed = upper.unicodeScalars.filter { (32...126).contains($0.value) }
        return String(String.UnicodeScalarView(allowed).prefix(maximumTextLength))
    }
}

public enum LEDScene {
    /// One frame of the scene, as AMG65 Studio's bridge chose it (every 0.5 s).
    /// - Parameters:
    ///   - seconds: time since streaming started (rotation and activity timing);
    ///   - animationStep: frames rendered so far (two steps per second of animation).
    public static func frame(settings: LEDDisplaySettings, quotas: [LEDQuota], activities: [LEDActivity],
                             seconds: Double, animationStep: Int, now: TimeInterval) -> (pixels: [RGB24], view: String) {
        let brightness = settings.brightness, gain = settings.claudeGreenGain
        let elapsed = Double(animationStep) / 2
        let tracked = settings.trackedProvider
        let activity = settings.activityEnabled
            ? LEDMatrixRenderer.selectActivity(activities, elapsed: seconds, now: now, provider: tracked) : nil
        let mascot = activity != nil && settings.mascotEnabled
        var pixels: [RGB24]
        let view: String
        if let activity {
            pixels = mascot
                ? LEDMatrixRenderer.mascot(activity, quotas: quotas, brightness: brightness, elapsed: elapsed, claudeGreenGain: gain)
                : LEDMatrixRenderer.activity(activity, quotas: quotas, brightness: brightness, elapsed: elapsed, claudeGreenGain: gain)
            view = "activity"
        } else if tracked != "all" {
            let quota = quotas.first { $0.provider == tracked } ?? LEDQuota(provider: tracked, remainingPercent: nil, stale: false)
            pixels = LEDMatrixRenderer.detail(quota, brightness: brightness, claudeGreenGain: gain)
            view = tracked
        } else if settings.mode == .text {
            pixels = LEDMatrixRenderer.text(LEDDisplaySettings.sanitized(settings.text), color: settings.textColor,
                                            brightness: brightness, elapsed: elapsed, marquee: settings.textEffect == .scroll)
            view = "text"
        } else {
            let phase = Int(max(0, seconds)) % 24
            if settings.mode == .overview || phase < 12 {
                pixels = LEDMatrixRenderer.overview(quotas, brightness: brightness, claudeGreenGain: gain)
                view = "overview"
            } else {
                let provider = LEDMatrixRenderer.providers[(phase - 12) / 4].id
                let quota = quotas.first { $0.provider == provider } ?? LEDQuota(provider: provider, remainingPercent: nil, stale: false)
                pixels = LEDMatrixRenderer.detail(quota, brightness: brightness, claudeGreenGain: gain)
                view = provider
            }
        }
        // Attention screens (approval, input, error) stay still; a scrolling text already moves.
        let calm = activity.map { ["running", "queued", "completed"].contains($0.state) } ?? true
        if !mascot && calm && !(view == "text" && settings.textEffect == .scroll) {
            pixels = LEDMatrixRenderer.applyTextEffect(pixels, effect: settings.textEffect, brightness: brightness,
                                                       elapsed: elapsed, left: activity != nil ? 7 : 0)
        }
        return (pixels, view)
    }
}
