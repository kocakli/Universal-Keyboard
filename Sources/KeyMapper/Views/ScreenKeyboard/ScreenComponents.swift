import AppKit
import KeyMapperCore
import SwiftUI

/// A group inside the screen keyboard section (one level above the section's own surface).
struct ScreenCard<Content: View>: View {
    var title: String?
    var spacing: CGFloat = 12
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            if let title { Eyebrow(text: title) }
            content()
        }
        // Fills the height it is offered, so cards side by side in `AdaptiveColumns` end level.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.raised))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.line))
    }
}

/// Equal-width columns: as many as fit at `minimum` each, but never more than there are items, so two cards share
/// the whole width instead of leaving an empty third column. Items in a row get the row's height.
struct AdaptiveColumns: Layout {
    var minimum: CGFloat = 300
    var spacing: CGFloat = 12

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        // nil or infinite (a stack measuring its ideal size): as many columns as items, each at the minimum.
        let ideal = max(minimum, CGFloat(subviews.count) * (minimum + spacing) - spacing)
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? ideal
        let heights = rowHeights(subviews, width: width)
        return CGSize(width: width, height: heights.reduce(0, +) + spacing * CGFloat(max(heights.count - 1, 0)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (columns, columnWidth) = grid(width: bounds.width, count: subviews.count)
        var y = bounds.minY
        for (row, height) in zip(rows(subviews.count, columns), rowHeights(subviews, width: bounds.width)) {
            for (column, index) in row.enumerated() {
                subviews[index].place(at: CGPoint(x: bounds.minX + CGFloat(column) * (columnWidth + spacing), y: y),
                                      anchor: .topLeading, proposal: ProposedViewSize(width: columnWidth, height: height))
            }
            y += height + spacing
        }
    }

    private func grid(width: CGFloat, count: Int) -> (columns: Int, width: CGFloat) {
        let fit = width.isFinite ? Int(max(0, (width + spacing) / (minimum + spacing))) : count
        let columns = max(1, min(count, fit))
        return (columns, (width - spacing * CGFloat(columns - 1)) / CGFloat(columns))
    }

    private func rows(_ count: Int, _ columns: Int) -> [[Int]] {
        stride(from: 0, to: count, by: columns).map { Array($0..<min($0 + columns, count)) }
    }

    private func rowHeights(_ subviews: Subviews, width: CGFloat) -> [CGFloat] {
        let (columns, columnWidth) = grid(width: width, count: subviews.count)
        return rows(subviews.count, columns).map { row in
            row.map { subviews[$0].sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)).height }.max() ?? 0
        }
    }
}

/// Title and one line of explanation at the top of a tab, with optional trailing controls.
struct TabHeader<Trailing: View>: View {
    let title: String
    let detail: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            trailing()
        }
    }
}

extension TabHeader where Trailing == EmptyView {
    init(title: String, detail: String) { self.init(title: title, detail: detail) { EmptyView() } }
}

/// The note, the unsent marker and the one primary button of everything that writes to the keyboard.
struct ApplyRow: View {
    let pending: Bool
    let note: String
    var title = L("Klavyeye gönder")
    /// Disables the button (something is being sent, or there is nothing to send).
    var disabled = false
    var secondary: (title: String, action: () -> Void)?
    let apply: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(note)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            if pending {
                Text(L("Gönderilmedi")).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.modified)
            }
            if let secondary {
                Button(secondary.title, action: secondary.action).buttonStyle(SecondaryButtonStyle(height: 28))
            }
            Button(title, action: apply)
                .buttonStyle(PrimaryButtonStyle(height: 28))
                .disabled(disabled)
        }
    }
}

/// Amber note for anything written to the keyboard's permanent memory.
struct FlashWarning: View {
    let text: String

    var body: some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .font(.system(size: 11))
        .foregroundStyle(Theme.modified)
    }
}

/// Whether a setting was seen working on the keyboard.
struct TestedTag: View {
    let tested: Bool

    var body: some View {
        Chip(text: tested ? L("Denendi") : L("Denenmedi"),
             foreground: tested ? Theme.success : Theme.modified,
             background: (tested ? Theme.success : Theme.modified).opacity(0.12),
             font: .system(size: 10, weight: .medium))
            .help(tested ? L("Bu klavyede çalıştığı görüldü.") : L("Bu klavyede henüz denenmedi."))
    }
}

/// Whole steps as a row of buttons (brightness 1…7, speed 0…5).
struct StepPicker: View {
    @Binding var value: UInt8
    let range: ClosedRange<UInt8>
    var label: String

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(range), id: \.self) { step in
                let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
                Button { value = step } label: {
                    Text("\(step)")
                        .font(.system(size: 12, weight: step == value ? .semibold : .regular))
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, minHeight: 26)
                        .foregroundStyle(step == value ? Theme.onAccent : (step < value ? Theme.text : Theme.textSecondary))
                        .background(shape.fill(step == value ? Theme.accent : (step < value ? Theme.accentTint : Theme.control)))
                        .overlay(shape.strokeBorder(step == value ? Color.clear : Theme.line))
                        .contentShape(shape)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: 320)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(value)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: if value < range.upperBound { value += 1 }
            case .decrement: if value > range.lowerBound { value -= 1 }
            @unknown default: break
            }
        }
    }
}

/// Segmented choice with a fixed maximum width.
struct Segmented<Value: Hashable>: View {
    let label: String
    @Binding var selection: Value
    let options: [(Value, String)]
    var maxWidth: CGFloat = 360

    var body: some View {
        Picker(label, selection: $selection) {
            ForEach(options, id: \.0) { Text($0.1).tag($0.0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: maxWidth, alignment: .leading)
    }
}

/// Label column + control, used for settings rows inside cards.
struct SettingRow<Control: View>: View {
    let label: String
    var labelWidth: CGFloat = 110
    @ViewBuilder var control: () -> Control

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(label).foregroundStyle(Theme.textSecondary).frame(width: labelWidth, alignment: .leading)
            control().frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 13))
    }
}

/// Lays children out left to right and wraps to a new line when the width runs out.
struct WrapLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].indices.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if needed > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row(indices: [index], width: size.width, height: size.height))
            } else {
                rows[rows.count - 1].indices.append(index)
                rows[rows.count - 1].width = needed
                rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
            }
        }
        return rows.filter { !$0.indices.isEmpty }
    }
}

// MARK: - Colours

extension Color {
    init(_ rgb: RGB24) {
        self.init(.sRGB, red: Double(rgb.r) / 255, green: Double(rgb.g) / 255, blue: Double(rgb.b) / 255)
    }
}

extension RGB24 {
    init?(_ color: Color) {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        self.init(r: UInt8((rgb.redComponent * 255).rounded()), g: UInt8((rgb.greenComponent * 255).rounded()),
                  b: UInt8((rgb.blueComponent * 255).rounded()))
    }

    /// Swatches offered next to the colour picker.
    static let swatches: [RGB24] = [
        RGB24(r: 255, g: 255, b: 255), RGB24(r: 255, g: 59, b: 48), RGB24(r: 255, g: 149, b: 0), RGB24(r: 255, g: 214, b: 10),
        RGB24(r: 52, g: 199, b: 89), RGB24(r: 0, g: 199, b: 190), RGB24(r: 10, g: 132, b: 255), RGB24(r: 94, g: 92, b: 230),
        RGB24(r: 191, g: 90, b: 242), RGB24(r: 255, g: 55, b: 95),
    ]
}

/// AI tools' brand colours, used for dots and bars (not for text).
enum ToolColor {
    static func of(_ provider: String) -> Color {
        switch provider {
        case "claude": return Color(hex: 0xFE5A00)
        case "codex": return Color(hex: 0x3FB98A)
        case "cursor": return Color(hex: 0x5A9FE8)
        default: return Theme.accent
        }
    }
}

/// A row of colour swatches plus the system colour picker.
struct SwatchRow: View {
    @Binding var color: RGB24
    var isActive = true
    var label: String

    var body: some View {
        HStack(spacing: 6) {
            ForEach(RGB24.swatches, id: \.self) { swatch in
                let selected = isActive && swatch == color
                Button { color = swatch } label: {
                    Circle().fill(Color(swatch))
                        .frame(width: 20, height: 20)
                        .overlay(Circle().strokeBorder(Theme.line))
                        .padding(3)
                        .overlay(Circle().strokeBorder(selected ? Theme.accent : .clear, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(swatch.hex)
            }
            ColorPicker(label, selection: Binding(get: { Color(color) }, set: { if let value = RGB24($0) { color = value } }),
                        supportsOpacity: false)
                .labelsHidden()
                .help(L("Başka bir renk seçin"))
        }
    }
}
