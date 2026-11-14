import KeyMapperCore
import SwiftUI

/// What one key cap shows.
struct KeyCapModel {
    var label: KeyLabel
    var style: Style = .normal
    var tooltip: String = ""

    enum Style { case normal, transparent, empty, layer, modified, highlighted }
}

/// Draws a KLE style layout (with rotated clusters) and reports clicks.
struct KeyboardCanvas: View {
    let keys: [LayoutKey]
    let selected: KeySlot?
    var highlighted: Set<KeySlot> = []
    let cap: (LayoutKey) -> KeyCapModel
    let onSelect: (LayoutKey) -> Void

    private struct Placed {
        let key: LayoutKey
        let center: CGPoint
    }

    var body: some View {
        let geometry = Self.layout(keys)
        GeometryReader { proxy in
            let unit = max(14, min(58,
                                   (proxy.size.width - 8) / max(geometry.size.width, 1),
                                   (proxy.size.height - 8) / max(geometry.size.height, 1)))
            ZStack(alignment: .topLeading) {
                ForEach(Array(geometry.placed.enumerated()), id: \.offset) { _, item in
                    let model = cap(item.key)
                    KeyCapView(
                        model: model,
                        isEncoder: item.key.isEncoder,
                        isSelected: selected == item.key.slot,
                        isHighlighted: highlighted.contains(item.key.slot),
                        unit: unit
                    )
                    .frame(width: item.key.w * unit - 4, height: item.key.h * unit - 4)
                    .rotationEffect(.degrees(item.key.r))
                    .position(x: item.center.x * unit + 4, y: item.center.y * unit + 4)
                    .onTapGesture { onSelect(item.key) }
                    .help(model.tooltip)
                }
            }
            .frame(width: geometry.size.width * unit + 8, height: geometry.size.height * unit + 8, alignment: .topLeading)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(max(geometry.size.width, 1) / max(geometry.size.height, 1), contentMode: .fit)
        .frame(maxHeight: geometry.size.height * 58 + 8)
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

struct KeyCapView: View {
    let model: KeyCapModel
    let isEncoder: Bool
    let isSelected: Bool
    let isHighlighted: Bool
    let unit: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: isEncoder ? unit : unit * 0.12, style: .continuous)
        ZStack {
            shape.fill(fill)
            shape.strokeBorder(border, lineWidth: isSelected ? 2.5 : 1)
            VStack(spacing: 0) {
                if let top = model.label.top {
                    Text(top).font(.system(size: unit * 0.2)).foregroundStyle(.secondary)
                }
                Text(model.label.main)
                    .font(.system(size: unit * (model.label.main.count > 4 ? 0.2 : 0.27), weight: .medium))
                    .minimumScaleFactor(0.5)
                    .multilineTextAlignment(.center)
                if let sub = model.label.sub {
                    Text(sub)
                        .font(.system(size: unit * 0.18, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .lineLimit(1)
            .padding(2)
            .opacity(model.style == .transparent || model.style == .empty ? 0.45 : 1)
        }
        .contentShape(shape)
    }

    private var fill: Color {
        if isSelected { return Color.accentColor.opacity(0.22) }
        if isHighlighted { return Color.orange.opacity(0.3) }
        switch model.style {
        case .layer: return Color.purple.opacity(0.14)
        case .modified: return Color.orange.opacity(0.18)
        case .highlighted: return Color.green.opacity(0.18)
        default: return Color(nsColor: .controlBackgroundColor)
        }
    }

    private var border: Color {
        isSelected ? Color.accentColor : Color(nsColor: .separatorColor)
    }
}
