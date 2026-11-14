import KeyMapperCore
import KeyMapperUsage
import SwiftUI

/// Remaining Claude / Codex / Cursor allowance, each provider switched on by the user.
struct UsagePanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("KeyMapper, bu Mac'te zaten oturum açtığınız Claude Code, Codex ve Cursor'dan kalan kullanımı okur. Yalnızca açtığınız sağlayıcılar okunur; parola istenmez, oturum bilgileri kaydedilmez veya paylaşılmaz."))
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(UsageEngine.providers, id: \.self) { provider in
                UsageRow(provider: provider)
            }
            HStack {
                Button(L("Şimdi yenile")) { model.refreshUsage(force: true) }
                    .buttonStyle(SecondaryButtonStyle(height: 26))
                    .disabled(model.usageProviders.isEmpty || model.usageRefreshing)
                if model.usageRefreshing { ProgressView().controlSize(.small) }
                Spacer()
                Text(L("5 dakikada bir yenilenir")).font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
            }
        }
        .font(.system(size: 13))
    }
}

private struct UsageRow: View {
    @Environment(AppModel.self) private var model
    let provider: String

    var body: some View {
        let enabled = model.isUsageEnabled(provider)
        let row = model.usage.first { $0.provider == provider }
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Toggle(isOn: Binding(get: { enabled }, set: { model.setUsage(provider, enabled: $0) })) {
                    Text(UsageNormalizer.labels[provider] ?? provider).font(.system(size: 13, weight: .semibold))
                }
                Spacer()
                if enabled, model.usageAwaiting.contains(provider) {
                    ProgressView().controlSize(.small)
                    Text(L("Okunuyor…")).foregroundStyle(Theme.textSecondary)
                } else if enabled, let row {
                    if let remaining = row.remainingPercent {
                        Text(percent(remaining)).monospacedDigit().font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(row.stale ? Theme.textTertiary : Theme.text)
                        if let label = row.remainingLabel { Text(label).foregroundStyle(Theme.textSecondary) }
                        if row.stale { Chip(text: L("eski"), foreground: Theme.modified) }
                    } else {
                        Text("--").foregroundStyle(Theme.textTertiary)
                    }
                }
            }
            if enabled, !model.usageAwaiting.contains(provider), let row {
                let others = row.windows.filter { $0.label != row.remainingLabel && $0.remainingPercent != nil }
                if !others.isEmpty {
                    Text(others.map { "\($0.label) \(percent($0.remainingPercent!))" }.joined(separator: " · "))
                        .font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                }
                if let reset = row.windows.first(where: { $0.label == row.remainingLabel })?.resetsAt {
                    Text(L("Sıfırlanma: %@", relative(reset))).font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                }
                if let message = row.errorDescription {
                    HStack(spacing: 8) {
                        Text(message).font(.system(size: 11)).foregroundStyle(Theme.modified)
                        if row.error == "keychain_locked", ["claude", "cursor"].contains(provider) {
                            Button(L("Anahtar Zinciri'ne izin ver")) { model.authorizeKeychain(for: provider) }
                                .buttonStyle(SecondaryButtonStyle(height: 22))
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func percent(_ value: Double) -> String {
        (value / 100).formatted(.percent.precision(.fractionLength(0)).locale(L10n.current.locale))
    }

    private func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = L10n.current.locale
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
