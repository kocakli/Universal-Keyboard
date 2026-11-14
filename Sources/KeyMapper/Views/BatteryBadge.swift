import KeyMapperCore
import SwiftUI

/// Battery icon and percentage of a connected device; red at 20 % and below.
struct BatteryBadge: View {
    let status: BatteryStatus

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
            Text(percent(status.level)).monospacedDigit()
        }
        .font(.system(size: 12))
        .foregroundStyle(status.isLow ? Theme.error : Theme.textSecondary)
        .fixedSize()
        .help(help)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("Pil %@", percent(status.level)))
    }

    private var symbol: String {
        switch status.level {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    private var help: String {
        var lines = [status.levels.count > 1
            ? L("Pil seviyeleri: %@ (en düşüğü gösteriliyor)", status.levels.map(percent).joined(separator: ", "))
            : L("Pil %@", percent(status.level))]
        if status.isLow { lines.append(L("Şarj etmenin zamanı geldi.")) }
        return lines.joined(separator: "\n")
    }

    /// "%80" in Turkish, "80%" in English: the percent sign follows the UI language.
    private func percent(_ value: Int) -> String {
        (Double(value) / 100).formatted(.percent.precision(.fractionLength(0)).locale(L10n.current.locale))
    }
}
