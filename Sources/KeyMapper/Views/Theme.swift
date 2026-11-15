import AppKit
import KeyMapperCore
import SwiftUI

/// Colours follow the macOS appearance (light / dark / increased contrast) and the user's accent
/// colour. Semantic system colours are used where they exist; custom ones have light and dark
/// values chosen for at least 4.5:1 text contrast.
enum Theme {
    static let ground = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    /// Flat area the keyboard sits on.
    static let stage = Color.dynamic(light: 0xEBEBED, dark: 0x141415)
    static let raised = Color.dynamic(light: 0xF5F5F7, dark: 0x2A2A2D)
    static let control = Color.dynamic(light: 0xFFFFFF, dark: 0x2E2E31)
    /// Selected segment / category background.
    static let selectedFill = Color.dynamic(light: 0xE2E2E6, dark: 0x3A3A3E)
    static let line = Color(nsColor: .separatorColor)

    static let text = Color(nsColor: .labelColor)
    static let textSecondary = Color.dynamic(light: 0x5C5C61, dark: 0xA8A8AD)
    static let textTertiary = Color.dynamic(light: 0x66666B, dark: 0x9A9AA0)

    /// The user's accent colour (System Settings › Appearance).
    static let accent = Color.accentColor
    static let accentTint = Color.accentColor.opacity(0.16)
    static let onAccent = Color.white

    /// Layer keys (MO, TG, LT…): teal, distinct from any system accent.
    static let layerText = Color.dynamic(light: 0x0B6B64, dark: 0x5EC7BD)
    /// Keys changed by a macOS remap or per-app rule.
    static let modified = Color.dynamic(light: 0x935400, dark: 0xE9A23B)
    static let modifiedFace = Color.dynamic(light: 0xFFF0CC, dark: 0x38301F)
    static let error = Color.dynamic(light: 0xC8001E, dark: 0xFF7B72)
    /// Confirmed / healthy states (tested on the keyboard, hooks installed).
    static let success = Color.dynamic(light: 0x1B7F3B, dark: 0x30D158)
    /// Fixed brand colour of the app icon and mark (from the icon artwork).
    static let brand = Color(hex: 0x1643EA)

    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    /// Only for literal QMK identifiers.
    static func mono(_ size: CGFloat) -> Font {
        .system(size: size, weight: .regular, design: .monospaced)
    }

    static let label = Font.system(size: 12, weight: .medium)
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double(hex >> 16 & 0xFF) / 255,
                  green: Double(hex >> 8 & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }

    /// A colour that resolves per appearance.
    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

/// Keycap colourway per key kind: a lighter top face on a darker body, like a real cap.
enum CapKind {
    case alpha, modifier, layer, empty, transparent

    var base: Color {
        switch self {
        case .alpha: return .dynamic(light: 0xD6D6DA, dark: 0x242427)
        case .modifier: return .dynamic(light: 0xC9C9CE, dark: 0x1D1D20)
        case .layer: return .dynamic(light: 0xBCDCD7, dark: 0x132321)
        case .empty, .transparent: return .dynamic(light: 0xDEDEE2, dark: 0x1A1A1C)
        }
    }

    var face: Color {
        switch self {
        case .alpha: return .dynamic(light: 0xFFFFFF, dark: 0x333336)
        case .modifier: return .dynamic(light: 0xF0F0F2, dark: 0x2B2B2E)
        case .layer: return .dynamic(light: 0xDCEFEC, dark: 0x1B302E)
        case .empty, .transparent: return .dynamic(light: 0xF5F5F7, dark: 0x232326)
        }
    }

    var legend: Color {
        switch self {
        case .alpha: return Theme.text
        case .modifier: return .dynamic(light: 0x3C3C41, dark: 0xC6C6CB)
        case .layer: return Theme.layerText
        case .empty, .transparent: return Theme.textTertiary
        }
    }

    static let edge = Color.dynamic(light: 0x85858B, dark: 0x6A6A70)

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

/// A keycap: darker body, lighter top face inset (thicker at the bottom), 1px edge.
/// Selection is an accent ring with a small gap; changed keys get an amber bar.
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
            outer.fill(kind.base)
            inner
                .fill(isHighlighted ? Theme.modifiedFace : kind.face)
                .overlay(alignment: .bottom) {
                    if isHighlighted {
                        RoundedRectangle(cornerRadius: 1.5).fill(Theme.modified)
                            .frame(height: 3)
                            .padding(.horizontal, radius)
                            .padding(.bottom, 3)
                    }
                }
                .overlay { content() }
                .padding(EdgeInsets(top: 1, leading: 2, bottom: depth, trailing: 2))
        }
        .overlay(outer.strokeBorder(CapKind.edge, lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 0, y: 1)
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: radius + 3, style: .continuous)
                    .strokeBorder(Theme.accent, lineWidth: 2)
                    .padding(-4)
            }
        }
        .opacity(kind == .empty && !isSelected ? 0.75 : 1)
    }
}

/// Small rounded label (counts, metadata).
struct Chip: View {
    let text: String
    var foreground: Color = Theme.textSecondary
    var background: Color = Theme.raised
    var border: Color? = nil
    var font: Font = .system(size: 12)

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(background))
            .overlay { if let border { RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(border, lineWidth: 1) } }
    }
}

struct CapabilityBadge: View {
    let capability: DeviceCapability

    var body: some View {
        Chip(text: capability.title, font: .system(size: 11, weight: .medium))
            .help(capability.detail)
    }
}

private extension ControlSize {
    static func forHeight(_ height: CGFloat) -> ControlSize {
        height >= 38 ? .large : (height <= 28 ? .small : .regular)
    }
}

/// Primary action: the system's prominent bordered button (accent filled).
struct PrimaryButtonStyle: PrimitiveButtonStyle {
    var height: CGFloat = 32

    func makeBody(configuration: Configuration) -> some View {
        Button(configuration)
            .buttonStyle(.borderedProminent)
            .controlSize(.forHeight(height))
    }
}

/// Secondary action: the system's bordered button.
struct SecondaryButtonStyle: PrimitiveButtonStyle {
    var height: CGFloat = 32
    var emphasized = false

    func makeBody(configuration: Configuration) -> some View {
        Button(configuration)
            .buttonStyle(.bordered)
            .controlSize(.forHeight(height))
    }
}

/// Toggle-like token (layers, categories, hold actions, profiles).
struct PillButtonStyle: ButtonStyle {
    var isOn: Bool
    var style: Style = .signal
    var height: CGFloat = 28

    /// signal: accent tint when on; inverted: neutral segment; plain: accent fill, no frame when off.
    enum Style { case signal, inverted, plain }

    func makeBody(configuration: Configuration) -> some View {
        let (fg, bg, border): (Color, Color, Color) = {
            switch (style, isOn) {
            case (.signal, true): return (Theme.accent, Theme.accentTint, Theme.accent.opacity(0.55))
            case (.inverted, true): return (Theme.text, Theme.selectedFill, .clear)
            case (.plain, true): return (Theme.onAccent, Theme.accent, .clear)
            case (.plain, false), (.inverted, false): return (Theme.textSecondary, .clear, .clear)
            default: return (Theme.text, Theme.control, Theme.line)
            }
        }()
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        return configuration.label
            .font(.system(size: 12, weight: isOn ? .semibold : .regular))
            .foregroundStyle(fg)
            .padding(.horizontal, 10)
            .frame(minWidth: 30)
            .frame(height: height)
            .background(shape.fill(bg.opacity(configuration.isPressed ? 0.75 : 1)))
            .overlay(shape.strokeBorder(border, lineWidth: 1))
            .contentShape(shape)
    }
}

/// Content group.
struct Panel<Content: View>: View {
    var padding: CGFloat = 16
    var fill: Color = Theme.surface
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
    }
}

/// Small section label, sentence case.
struct Eyebrow: View {
    let text: String
    var color: Color = Theme.textSecondary

    var body: some View {
        Text(text)
            .font(Theme.label)
            .foregroundStyle(color)
    }
}

/// The transparent KeyMapper glyph shipped in the app bundle (Resources/Glyph.png).
enum BrandGlyph {
    /// Template image; nil when running outside the .app (e.g. `swift run`).
    static let image: NSImage? = {
        guard let image = NSImage(named: "Glyph") else { return nil }
        image.isTemplate = true
        return image
    }()

    /// Menu bar sized copy (16 pt tall), drawn by macOS in the menu bar's colour.
    static let menuBar: NSImage? = {
        guard let image = image?.copy() as? NSImage else { return nil }
        let aspect = image.size.width / max(image.size.height, 1)
        image.size = NSSize(width: (16 * aspect).rounded(), height: 16)
        image.isTemplate = true
        return image
    }()
}

/// App mark: the icon's glyph on the brand blue, like a small app icon.
struct AppMark: View {
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous).fill(Theme.brand)
            if let glyph = BrandGlyph.image {
                Image(nsImage: glyph)
                    .resizable()
                    .renderingMode(.template)
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.white)
                    .padding(size * 0.2)
            } else {
                Image(systemName: "keyboard").font(.system(size: size * 0.48, weight: .semibold)).foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Tiny silhouette of a keyboard's real layout.
struct KeyboardSilhouette: View {
    let keys: [LayoutKey]
    var color: Color = Theme.accent

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

/// The standard macOS sidebar material behind the editor's device list.
struct SidebarBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
