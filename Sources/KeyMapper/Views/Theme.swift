import KeyMapperCore
import SwiftUI

/// "Graphite Signal": dark graphite surfaces, signal orange for selection and
/// primary actions, cobalt for layer keys. Values mirror the design canvas tokens.
enum Theme {
    static let ground = Color(hex: 0x0E0F12)
    static let sidebar = Color(hex: 0x131418)
    static let surface = Color(hex: 0x15171B)
    static let surfaceSunken = Color(hex: 0x0A0B0D)
    static let raised = Color(hex: 0x1E2127)
    static let control = Color(hex: 0x1A1C21)
    static let line = Color(hex: 0x2A2D35)
    static let lineSoft = Color(hex: 0x22252B)
    static let text = Color(hex: 0xECEAE4)
    static let textSecondary = Color(hex: 0x9A9CA6)
    static let textTertiary = Color(hex: 0x8B8E99)
    static let textMuted = Color(hex: 0xC9CAD1)
    static let signal = Color(hex: 0xFF8A4C)
    static let signalSoft = Color(hex: 0xFFB083)
    static let signalTint = Color(hex: 0x3A2418)
    static let onSignal = Color(hex: 0x1A0E07)
    static let cobalt = Color(hex: 0x7FA8FF)
    static let cobaltText = Color(hex: 0x9DBBFF)

    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static func mono(_ size: CGFloat) -> Font {
        .system(size: size, weight: .regular, design: .monospaced)
    }

    static let eyebrow = Font.system(size: 11, weight: .semibold)
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double(hex >> 16 & 0xFF) / 255,
                  green: Double(hex >> 8 & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

/// Keycap colourway per key kind.
enum CapKind {
    case alpha, modifier, layer, empty, transparent

    var base: Color {
        switch self {
        case .alpha: return Color(hex: 0x1B1D22)
        case .modifier: return Color(hex: 0x17191D)
        case .layer: return Color(hex: 0x141B2B)
        case .empty, .transparent: return Color(hex: 0x141519)
        }
    }

    var face: Color {
        switch self {
        case .alpha: return Color(hex: 0x2A2D35)
        case .modifier: return Color(hex: 0x22252C)
        case .layer: return Color(hex: 0x1F2840)
        case .empty, .transparent: return Color(hex: 0x191B20)
        }
    }

    var legend: Color {
        switch self {
        case .alpha: return Theme.text
        case .modifier: return Color(hex: 0xB9BBC4)
        case .layer: return Theme.cobaltText
        case .empty: return Color(hex: 0x4A4D57)
        case .transparent: return Theme.textTertiary
        }
    }

    /// Classifies a keycode for colouring.
    static func of(_ code: UInt16, keycodes: KeycodeSet) -> CapKind {
        switch keycodes.decode(code) {
        case .named(0x00): return .empty
        case .named(0x01): return .transparent
        case .layer, .layerTap, .layerMod: return .layer
        case let .named(c):
            switch keycodes.entry(for: c)?.group {
            case .basic?, .numpad?, .international?: return c == 0x2C || (0x28...0x2B).contains(c) || c == 0x39 ? .modifier : .alpha
            default: return .modifier
            }
        case let .modTap(_, kc), let .mods(_, kc):
            return of(kc, keycodes: keycodes) == .alpha ? .alpha : .modifier
        default: return .modifier
        }
    }
}

/// A sculpted keycap: darker body, lighter top face inset (thicker at the bottom), soft top highlight.
struct Keycap<Content: View>: View {
    let kind: CapKind
    var isSelected = false
    var isHighlighted = false
    var radius: CGFloat = 10
    var depth: CGFloat = 7
    @ViewBuilder var content: () -> Content

    var body: some View {
        let outer = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let inner = RoundedRectangle(cornerRadius: max(radius - 2, 2), style: .continuous)
        ZStack {
            outer.fill(isSelected ? Theme.signalTint : (isHighlighted ? Color(hex: 0x3A2A16) : kind.base))
            inner
                .fill(kind.face)
                .overlay(alignment: .top) {
                    Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1).padding(.horizontal, radius * 0.6)
                }
                .overlay { content() }
                .padding(EdgeInsets(top: 2, leading: 3, bottom: depth, trailing: 3))
        }
        .overlay {
            if isSelected { outer.strokeBorder(Theme.signal, lineWidth: 2) }
        }
        .shadow(color: isSelected ? Theme.signal.opacity(0.35) : .black.opacity(0.6), radius: isSelected ? 13 : 0, y: isSelected ? 8 : 1)
        .opacity(kind == .empty && !isSelected ? 0.7 : 1)
    }
}

/// Small rounded label (capability, counts, metadata).
struct Chip: View {
    let text: String
    var foreground: Color = Color(hex: 0xB9BBC4)
    var background: Color = Color(hex: 0x17191D)
    var border: Color? = Color(hex: 0x262930)
    var font: Font = .system(size: 12)

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(background))
            .overlay { if let border { Capsule().strokeBorder(border, lineWidth: 1) } }
    }
}

extension DeviceCapability {
    var chipForeground: Color { self == .osRemap ? Color(hex: 0xB9BBC4) : (self == .vial ? Theme.signalSoft : Theme.cobaltText) }
    var chipBackground: Color { self == .osRemap ? Color(hex: 0x23262D) : (self == .vial ? Theme.signalTint : Color(hex: 0x1A2236)) }
}

struct CapabilityBadge: View {
    let capability: DeviceCapability

    var body: some View {
        Chip(text: capability.title, foreground: capability.chipForeground, background: capability.chipBackground,
             border: nil, font: .system(size: 11, weight: .semibold))
            .help(capability.detail)
    }
}

/// Orange filled action.
struct PrimaryButtonStyle: ButtonStyle {
    var height: CGFloat = 36

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.onSignal)
            .padding(.horizontal, 16)
            .frame(height: height)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.signal.opacity(configuration.isPressed ? 0.8 : 1)))
            .contentShape(Rectangle())
    }
}

/// Dark bordered action.
struct SecondaryButtonStyle: ButtonStyle {
    var height: CGFloat = 36
    var emphasized = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: emphasized ? .semibold : .regular))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 12)
            .frame(height: height)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(configuration.isPressed ? Theme.raised : (emphasized ? Color(hex: 0x23262D) : Theme.control)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(emphasized ? Color(hex: 0x30343D) : Theme.line, lineWidth: 1))
            .contentShape(Rectangle())
    }
}

/// Pill that can be on/off (layers, categories, hold actions, profiles).
struct PillButtonStyle: ButtonStyle {
    var isOn: Bool
    var style: Style = .signal
    var height: CGFloat = 30

    enum Style { case signal, inverted, plain }

    func makeBody(configuration: Configuration) -> some View {
        let (fg, bg, border): (Color, Color, Color) = {
            switch (style, isOn) {
            case (.signal, true): return (Theme.signalSoft, Theme.signalTint, Theme.signal)
            case (.inverted, true): return (Theme.ground, Theme.text, Theme.text)
            case (.plain, true): return (Theme.onSignal, Theme.signal, Theme.signal)
            case (.plain, false): return (Theme.textSecondary, .clear, .clear)
            default: return (Theme.textMuted, Theme.control, Theme.line)
            }
        }()
        return configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(fg)
            .padding(.horizontal, 12)
            .frame(minWidth: 34)
            .frame(height: height)
            .background(Capsule().fill(bg.opacity(configuration.isPressed ? 0.8 : 1)))
            .overlay(Capsule().strokeBorder(border, lineWidth: 1))
            .contentShape(Capsule())
    }
}

/// Rounded dark panel.
struct Panel<Content: View>: View {
    var padding: CGFloat = 18
    var fill: Color = Theme.surface
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.lineSoft, lineWidth: 1))
    }
}

struct Eyebrow: View {
    let text: String
    var color: Color = Theme.textTertiary

    var body: some View {
        Text(text.uppercased(with: Locale(identifier: "tr_TR")))
            .font(Theme.eyebrow)
            .tracking(0.9)
            .foregroundStyle(color)
    }
}

/// App mark: an orange key with three legends.
struct AppMark: View {
    var size: CGFloat = 28

    var body: some View {
        let s = size / 28
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8 * s, style: .continuous).fill(Theme.signal)
            RoundedRectangle(cornerRadius: 1.5 * s).fill(Theme.onSignal).frame(width: 5 * s, height: 5 * s).offset(x: 6 * s, y: 7 * s)
            RoundedRectangle(cornerRadius: 1.5 * s).fill(Theme.onSignal).frame(width: 5 * s, height: 5 * s).offset(x: 15 * s, y: 7 * s)
            RoundedRectangle(cornerRadius: 1.5 * s).fill(Theme.onSignal).frame(width: 14 * s, height: 4 * s).offset(x: 6 * s, y: 15 * s)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Tiny dot-matrix silhouette of a keyboard's real layout.
struct KeyboardSilhouette: View {
    let keys: [LayoutKey]
    var color: Color = Theme.signal

    var body: some View {
        Canvas { context, size in
            let matrix = keys.filter { !$0.isEncoder }
            guard !matrix.isEmpty else {
                // Generic keyboard: four bars.
                for i in 0..<4 {
                    let width = i == 3 ? size.width * 0.5 : size.width
                    let rect = CGRect(x: (size.width - width) / 2, y: CGFloat(i) * size.height / 4 + 1, width: width, height: size.height / 4 - 2)
                    context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(color))
                }
                return
            }
            let minX = matrix.map(\.x).min() ?? 0, maxX = matrix.map { $0.x + $0.w }.max() ?? 1
            let minY = matrix.map(\.y).min() ?? 0, maxY = matrix.map { $0.y + $0.h }.max() ?? 1
            let scale = min(size.width / (maxX - minX), size.height / (maxY - minY))
            for key in matrix {
                let rect = CGRect(x: (key.x - minX) * scale + 0.6, y: (key.y - minY) * scale + 0.6,
                                  width: key.w * scale - 1.2, height: key.h * scale - 1.2)
                var path = Path(roundedRect: rect, cornerRadius: scale * 0.2)
                if key.r != 0 {
                    let pivot = CGPoint(x: (key.rx - minX) * scale, y: (key.ry - minY) * scale)
                    path = path.applying(CGAffineTransform(translationX: -pivot.x, y: -pivot.y)
                        .concatenating(CGAffineTransform(rotationAngle: key.r * .pi / 180))
                        .concatenating(CGAffineTransform(translationX: pivot.x, y: pivot.y)))
                }
                context.fill(path, with: .color(color))
            }
        }
        .accessibilityHidden(true)
    }
}

/// Dot grid used behind the keyboard stage.
struct DotGrid: View {
    var spacing: CGFloat = 18
    var color: Color = Color(hex: 0x1C1E24)

    var body: some View {
        Canvas { context, size in
            var y: CGFloat = spacing / 2
            while y < size.height {
                var x: CGFloat = spacing / 2
                while x < size.width {
                    context.fill(Path(ellipseIn: CGRect(x: x - 1, y: y - 1, width: 2, height: 2)), with: .color(color))
                    x += spacing
                }
                y += spacing
            }
        }
        .accessibilityHidden(true)
    }
}
