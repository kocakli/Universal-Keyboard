import KeyMapperCore
import SwiftUI

/// What one key cap shows.
struct KeyCapModel {
    var label: KeyLabel
    var kind: CapKind = .alpha
    var subColor: Color = Theme.accent
    var isHighlighted = false
    var tooltip: String = ""
}

/// Draws a KLE style layout (with rotated clusters) as sculpted keycaps and reports clicks.
struct KeyboardCanvas: View {
    let keys: [LayoutKey]
    let selected: KeySlot?
    let cap: (LayoutKey) -> KeyCapModel
    let onSelect: (LayoutKey) -> Void
    var maxUnit: CGFloat = 60

    private struct Placed {
        let key: LayoutKey
        let center: CGPoint
    }

    var body: some View {
        let geometry = Self.layout(keys)
        GeometryReader { proxy in
            let unit = max(16, min(maxUnit,
                                   proxy.size.width / max(geometry.size.width, 1),
                                   proxy.size.height / max(geometry.size.height, 1)))
            ZStack(alignment: .topLeading) {
                ForEach(Array(geometry.placed.enumerated()), id: \.offset) { _, item in
                    let model = cap(item.key)
                    Button {
                        onSelect(item.key)
                    } label: {
                        Keycap(kind: model.kind, isSelected: selected == item.key.slot, isHighlighted: model.isHighlighted,
                               radius: unit * 0.18, depth: max(4, unit * 0.12)) {
                            KeyLegend(label: model.label, unit: unit, kind: model.kind, subColor: model.subColor)
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

    /// Rotates each key around its cluster origin and normalises everything to start at (0, 0).
    private static func layout(_ keys: [LayoutKey]) -> (placed: [Placed], size: CGSize) {
        guard !keys.isEmpty else { return ([], .zero) }
        var minX = Double.infinity, minY = Double.infinity, maxX = -Double.infinity, maxY = -Double.infinity
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
        return (placed, CGSize(width: maxX - minX, height: maxY - minY))
    }
}

/// Legend printed on a keycap: optional shifted legend, main legend, hold / layer hint.
struct KeyLegend: View {
    let label: KeyLabel
    let unit: CGFloat
    let kind: CapKind
    var subColor: Color = Theme.accent

    var body: some View {
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
