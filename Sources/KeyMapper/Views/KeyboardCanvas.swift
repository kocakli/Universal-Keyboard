import AppKit
import KeyMapperCore
import SwiftUI

/// What one key cap shows.
struct KeyCapModel {
    var label: KeyLabel
    var kind: CapKind = .alpha
    var subColor: Color = Theme.accent
    var isHighlighted = false
    /// App icon for keys that open an app.
    var icon: NSImage?
    var tooltip: String = ""
}

/// Draws a KLE style layout (with rotated clusters) as sculpted keycaps and reports clicks.
struct KeyboardCanvas: View {
    let keys: [LayoutKey]
    let selected: KeySlot?
    let cap: (LayoutKey) -> KeyCapModel
    let onSelect: (LayoutKey) -> Void
    var maxUnit: CGFloat = 60
    /// A trackball's or mouse's body, drawn behind its buttons.
    var deviceBody: DeviceBody?

    private struct Placed {
        let key: LayoutKey
        let center: CGPoint
    }

    var body: some View {
        let geometry = Self.layout(keys, body: deviceBody)
        GeometryReader { proxy in
            let unit = max(16, min(maxUnit,
                                   proxy.size.width / max(geometry.size.width, 1),
                                   proxy.size.height / max(geometry.size.height, 1)))
            ZStack(alignment: .topLeading) {
                if let deviceBody {
                    DeviceBodyView(shape: deviceBody, unit: unit)
                        .offset(x: -geometry.origin.x * unit, y: -geometry.origin.y * unit)
                }
                ForEach(Array(geometry.placed.enumerated()), id: \.offset) { _, item in
                    let model = cap(item.key)
                    Button {
                        onSelect(item.key)
                    } label: {
                        Keycap(kind: model.kind, isSelected: selected == item.key.slot, isHighlighted: model.isHighlighted,
                               radius: unit * 0.18, depth: max(4, unit * 0.12)) {
                            KeyLegend(label: model.label, unit: unit, kind: model.kind, subColor: model.subColor, icon: model.icon)
                        }
                        .frame(width: item.key.w * unit - 6, height: item.key.h * unit - 6)
                    }
                    .buttonStyle(.plain)
                    .rotationEffect(.degrees(item.key.r))
                    .position(x: item.center.x * unit, y: item.center.y * unit)
                    .help(model.tooltip)
                    .accessibilityLabel(model.label.main.isEmpty ? L("Boş tuş") : model.label.main)
                }
            }
            .frame(width: geometry.size.width * unit, height: geometry.size.height * unit, alignment: .topLeading)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(max(geometry.size.width, 1) / max(geometry.size.height, 1), contentMode: .fit)
        .frame(maxWidth: geometry.size.width * maxUnit, maxHeight: geometry.size.height * maxUnit)
    }

    /// Rotates each key around its cluster origin and normalises everything (keys and body) to start at (0, 0);
    /// `origin` is where the layout's (0, 0) ended up.
    private static func layout(_ keys: [LayoutKey], body: DeviceBody?) -> (placed: [Placed], size: CGSize, origin: CGPoint) {
        guard !keys.isEmpty else { return ([], .zero, .zero) }
        var minX = Double.infinity, minY = Double.infinity, maxX = -Double.infinity, maxY = -Double.infinity
        if let body {
            minX = 0; minY = 0; maxX = body.width; maxY = body.height
        }
        var centers: [CGPoint] = []
        for key in keys {
            let angle = key.r * .pi / 180
            func rotate(_ x: Double, _ y: Double) -> (Double, Double) {
                guard key.r != 0 else { return (x, y) }
                let dx = x - key.rx, dy = y - key.ry
                return (key.rx + dx * cos(angle) - dy * sin(angle), key.ry + dx * sin(angle) + dy * cos(angle))
            }
            let corners = [(key.x, key.y), (key.x + key.w, key.y), (key.x, key.y + key.h), (key.x + key.w, key.y + key.h)].map { rotate($0.0, $0.1) }
            for corner in corners {
                minX = min(minX, corner.0); maxX = max(maxX, corner.0)
                minY = min(minY, corner.1); maxY = max(maxY, corner.1)
            }
            let center = rotate(key.x + key.w / 2, key.y + key.h / 2)
            centers.append(CGPoint(x: center.0, y: center.1))
        }
        let placed = zip(keys, centers).map { key, center in
            Placed(key: key, center: CGPoint(x: center.x - minX, y: center.y - minY))
        }
        return (placed, CGSize(width: maxX - minX, height: maxY - minY), CGPoint(x: minX, y: minY))
    }
}

/// A pointing device's shell: sections, the ball in its scroll ring, small buttons with no keycode.
private struct DeviceBodyView: View {
    let shape: DeviceBody
    let unit: CGFloat

    var body: some View {
        let shell = RoundedRectangle(cornerRadius: shape.cornerRadius * unit, style: .continuous)
        ZStack(alignment: .topLeading) {
            shell.fill(Theme.raised)
                .overlay(shell.strokeBorder(Theme.line, lineWidth: 1))
                .frame(width: shape.width * unit, height: shape.height * unit)
            ForEach(Array(shape.seams.enumerated()), id: \.offset) { _, x in
                Rectangle().fill(Theme.line)
                    .frame(width: 1, height: shape.height * unit - 2)
                    .offset(x: x * unit, y: 1)
            }
            if let ring = shape.ring {
                // Knurled scroll ring.
                circle(ring) {
                    Circle().fill(Theme.stage)
                        .overlay(Circle().inset(by: unit * 0.1)
                            .stroke(CapKind.edge.opacity(0.7), style: StrokeStyle(lineWidth: unit * 0.16, dash: [1.5, 2.5])))
                        .overlay(Circle().strokeBorder(Theme.line, lineWidth: 1))
                }
            }
            if let ball = shape.ball {
                circle(ball) {
                    Circle()
                        .fill(RadialGradient(colors: [CapKind.edge.opacity(0.9), Theme.stage],
                                             center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: ball.radius * unit * 1.6))
                        .overlay(Circle().strokeBorder(Theme.line, lineWidth: 1))
                        .overlay(alignment: .topLeading) {
                            Circle().fill(Color.white.opacity(0.4))
                                .frame(width: unit * 0.22, height: unit * 0.22)
                                .blur(radius: unit * 0.05)
                                .offset(x: ball.radius * unit * 0.55, y: ball.radius * unit * 0.5)
                        }
                }
            }
            ForEach(Array(shape.buttons.enumerated()), id: \.offset) { _, button in
                circle(button) {
                    Circle().fill(Theme.control).overlay(Circle().strokeBorder(CapKind.edge, lineWidth: 1))
                }
            }
        }
        .frame(width: shape.width * unit, height: shape.height * unit, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func circle(_ circle: DeviceBody.Circle, @ViewBuilder content: () -> some View) -> some View {
        content()
            .frame(width: circle.radius * 2 * unit, height: circle.radius * 2 * unit)
            .offset(x: (circle.x - circle.radius) * unit, y: (circle.y - circle.radius) * unit)
    }
}

/// Legend printed on a keycap: optional shifted legend, main legend, hold / layer hint.
struct KeyLegend: View {
    let label: KeyLabel
    let unit: CGFloat
    let kind: CapKind
    var subColor: Color = Theme.accent
    var icon: NSImage?

    var body: some View {
        if let icon {
            VStack(spacing: 2) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: unit * 0.42, height: unit * 0.42)
                Text(label.main)
                    .font(.system(size: unit * 0.15, weight: .semibold))
                    .foregroundStyle(kind.legend)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
            .padding(.horizontal, 2)
        } else {
            legend
        }
    }

    private var legend: some View {
        VStack(spacing: 1) {
            if let top = label.top {
                Text(top).font(.system(size: unit * 0.17)).foregroundStyle(Theme.textTertiary)
            }
            Text(label.main)
                .font(Theme.rounded(unit * mainScale))
                .foregroundStyle(kind.legend)
                .minimumScaleFactor(0.5)
            if let sub = label.sub {
                Text(sub).font(.system(size: unit * 0.17, weight: .bold)).foregroundStyle(subColor)
            }
        }
        .lineLimit(1)
        .padding(.horizontal, 2)
    }

    private var mainScale: CGFloat {
        switch label.main.count {
        case 0...1: return 0.31
        case 2...3: return 0.24
        default: return 0.2
        }
    }
}

/// Stage behind a keyboard: a flat, slightly recessed area.
struct KeyboardStage<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 16) { content() }
            .padding(24)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.stage))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
    }
}
