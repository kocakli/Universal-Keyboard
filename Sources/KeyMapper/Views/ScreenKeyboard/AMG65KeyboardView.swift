import KeyMapperCore
import SwiftUI

/// What one AMG65 key shows.
struct AMG65CapModel {
    var legend: String
    /// Assigned action, drawn under the legend in the accent colour.
    var sub: String?
    /// Painted key colour.
    var fill: Color?
    var isHighlighted = false
    var isDimmed = false
}

/// The AMG65's 65 % layout (rects from AMG65 Studio) drawn with the app's keycaps. Click picks a key; with
/// `paintsOnDrag`, dragging across keys picks each one it passes (for the colour painter).
struct AMG65KeyboardView: View {
    let keys: [AMG65Key]
    var selected: Int?
    var paintsOnDrag = false
    let cap: (AMG65Key) -> AMG65CapModel
    let onPick: (AMG65Key) -> Void

    private var bounds: CGRect { keys.reduce(CGRect.null) { $0.union($1.rect) } }

    var body: some View {
        let bounds = self.bounds
        GeometryReader { proxy in
            let scale = min(proxy.size.width / bounds.width, 1.35)
            ZStack(alignment: .topLeading) {
                ForEach(keys) { key in
                    let model = cap(key)
                    Button { onPick(key) } label: {
                        Keycap(kind: model.isDimmed ? .empty : .alpha, isSelected: selected == key.slot, isHighlighted: model.isHighlighted,
                               radius: max(4, 7 * scale), depth: max(3, 5 * scale)) {
                            label(model, scale: scale)
                        }
                        .frame(width: key.rect.width * scale - 4, height: key.rect.height * scale - 4)
                    }
                    .buttonStyle(.plain)
                    .position(x: (key.rect.midX - bounds.minX) * scale, y: (key.rect.midY - bounds.minY) * scale)
                    .accessibilityLabel(model.sub.map { "\(key.name), \($0)" } ?? key.name)
                    .accessibilityAddTraits(selected == key.slot ? .isSelected : [])
                }
            }
            .frame(width: bounds.width * scale, height: bounds.height * scale, alignment: .topLeading)
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 4).onChanged { value in
                    let point = CGPoint(x: value.location.x / scale + bounds.minX, y: value.location.y / scale + bounds.minY)
                    if let key = keys.first(where: { $0.rect.contains(point) }) { onPick(key) }
                },
                including: paintsOnDrag ? .all : .subviews
            )
            .frame(maxWidth: .infinity)
        }
        .aspectRatio(bounds.width / bounds.height, contentMode: .fit)
        .frame(maxWidth: bounds.width * 1.35)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func label(_ model: AMG65CapModel, scale: CGFloat) -> some View {
        ZStack {
            if let fill = model.fill {
                RoundedRectangle(cornerRadius: max(2, 4 * scale), style: .continuous).fill(fill).padding(2)
            }
            VStack(spacing: 1) {
                Text(model.legend)
                    .font(.system(size: max(8, 11 * scale), weight: .medium))
                    .lineLimit(1).minimumScaleFactor(0.6)
                if let sub = model.sub {
                    Text(sub)
                        .font(.system(size: max(7, 9.5 * scale), weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .lineLimit(1).minimumScaleFactor(0.6)
                }
            }
            .padding(.horizontal, 2)
            .foregroundStyle(model.fill.map(Self.legendColor) ?? (model.isDimmed ? Theme.textTertiary : Theme.text))
        }
    }

    /// Black or white legend, whichever reads better on the painted colour.
    private static func legendColor(on fill: Color) -> Color {
        guard let rgb = RGB24(fill) else { return Theme.text }
        let luminance = 0.299 * Double(rgb.r) + 0.587 * Double(rgb.g) + 0.114 * Double(rgb.b)
        return luminance > 150 ? .black : .white
    }
}
