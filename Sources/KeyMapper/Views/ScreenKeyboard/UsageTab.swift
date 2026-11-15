import KeyMapperCore
import KeyMapperUsage
import SwiftUI

/// Remaining Claude / Codex / Cursor allowance (each provider switched on by the user) and, opt-in, what each tool
/// is doing right now.
struct UsageTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TabHeader(title: L("Yapay zekâ kullanımı"),
                      detail: L("KeyMapper, bu Mac'te zaten oturum açtığınız Claude (masaüstü uygulaması ya da Claude Code), Codex ve Cursor'dan kalan kullanımı okur. Yalnızca açtığınız sağlayıcılar okunur; parola istenmez, oturum bilgileri kaydedilmez, yenilenmez veya paylaşılmaz."))
            AdaptiveColumns(minimum: 210) {
                ForEach(UsageEngine.providers, id: \.self) { UsageCard(provider: $0) }
            }
            HStack(spacing: 10) {
                Button(L("Şimdi yenile")) { model.refreshUsage(force: true) }
                    .buttonStyle(SecondaryButtonStyle(height: 26))
                    .disabled(model.usageProviders.isEmpty || model.usageRefreshing)
                if model.usageRefreshing { ProgressView().controlSize(.small) }
                Spacer()
                Text(L("5 dakikada bir yenilenir")).font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
            }
            ActivityCard()
        }
        .font(.system(size: 13))
    }
}

private struct UsageCard: View {
    @Environment(AppModel.self) private var model
    let provider: String

    var body: some View {
        let enabled = model.isUsageEnabled(provider)
        let row = model.usage.first { $0.provider == provider }
        let name = UsageNormalizer.labels[provider] ?? provider
        ScreenCard(spacing: 8) {
            HStack(spacing: 8) {
                Circle().fill(ToolColor.of(provider)).frame(width: 8, height: 8)
                Text(name).font(.system(size: 13, weight: .semibold))
                Spacer()
                Toggle(name, isOn: Binding(get: { enabled }, set: { model.setUsage(provider, enabled: $0) }))
                    .toggleStyle(.switch).controlSize(.mini).labelsHidden()
            }
            if !enabled {
                Text(L("Kapalı; açınca okunur.")).foregroundStyle(Theme.textTertiary).font(.system(size: 12))
            } else if model.usageAwaiting.contains(provider) {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(L("Okunuyor…")).foregroundStyle(Theme.textSecondary)
                }
            } else if let row {
                details(row)
            } else {
                Text("--").font(.system(size: 22, weight: .semibold, design: .rounded)).foregroundStyle(Theme.textTertiary)
            }
        }
    }

    @ViewBuilder
    private func details(_ row: ProviderUsage) -> some View {
        if let remaining = row.remainingPercent {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(percent(remaining))
                    .font(.system(size: 24, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(row.stale ? Theme.textTertiary : Theme.text)
                if let label = row.remainingLabel { Text(label).foregroundStyle(Theme.textSecondary).font(.system(size: 12)) }
                if row.stale { Chip(text: L("eski"), foreground: Theme.modified, font: .system(size: 10, weight: .medium)) }
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.selectedFill)
                    Capsule().fill(ToolColor.of(provider).opacity(row.stale ? 0.45 : 1))
                        .frame(width: proxy.size.width * min(max(remaining, 0), 100) / 100)
                }
            }
            .frame(height: 6)
            .accessibilityHidden(true)
        } else {
            Text("--").font(.system(size: 22, weight: .semibold, design: .rounded)).foregroundStyle(Theme.textTertiary)
        }
        let others = row.windows.filter { $0.label != row.remainingLabel && $0.remainingPercent != nil }
        if !others.isEmpty {
            Text(others.map { "\($0.label) \(percent($0.remainingPercent!))" }.joined(separator: " · "))
                .font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
        }
        if let reset = row.windows.first(where: { $0.label == row.remainingLabel })?.resetsAt {
            Text(L("Sıfırlanma: %@", relative(reset))).font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
        }
        if let message = row.errorDescription {
            Text(message).font(.system(size: 11)).foregroundStyle(Theme.modified).fixedSize(horizontal: false, vertical: true)
            if row.error == "keychain_locked", ["claude", "cursor"].contains(provider) {
                Button(L("Anahtar Zinciri'ne izin ver")) { model.authorizeKeychain(for: provider) }
                    .buttonStyle(SecondaryButtonStyle(height: 22))
            }
        }
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

/// Opt-in activity tracking and each tool's hooks. Hook files are written only from these buttons.
private struct ActivityCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScreenCard(title: L("Etkinlik"), spacing: 10) {
            HStack(spacing: 12) {
                Text(L("Araçların ne yaptığını izle")).font(.system(size: 13, weight: .semibold))
                Spacer()
                Toggle(L("Araçların ne yaptığını izle"), isOn: Binding(get: { model.activityEnabled }, set: { model.setActivityEnabled($0) }))
                    .toggleStyle(.switch).controlSize(.small).labelsHidden()
            }
            Text(L("Açıkken KeyMapper, araçların kancalarından gelen olayları ve Codex'in oturum kayıtlarını (~/.codex) bu Mac'te okur; LED ekran çalışan ya da onay bekleyen aracı gösterir. Hiçbir bilgi bu Mac'ten çıkmaz."))
                .font(.system(size: 11)).foregroundStyle(Theme.textTertiary).fixedSize(horizontal: false, vertical: true)
            if model.activityEnabled {
                VStack(spacing: 0) {
                    ForEach(Array(ActivityProvider.allCases.enumerated()), id: \.element) { index, provider in
                        if index > 0 { Rectangle().fill(Theme.line).frame(height: 1) }
                        HookRow(provider: provider).padding(.vertical, 8)
                    }
                }
                if !model.canInstallHooks {
                    FlashWarning(text: L("Kancalar yalnızca Uygulamalar klasöründeki KeyMapper'dan kurulabilir, çünkü uygulamanın yolu araçların ayar dosyasına yazılır."))
                }
                Text(L("Bağlamak ve kaldırmak aracın ayar dosyasını değiştirir; her değişiklikten önce dosyanın yedeği alınır."))
                    .font(.system(size: 11)).foregroundStyle(Theme.textTertiary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct HookRow: View {
    @Environment(AppModel.self) private var model
    let provider: ActivityProvider
    @State private var working = false

    var body: some View {
        let state = model.hookStates[provider]
        let row = model.activityRows.first { $0.provider == provider }
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Circle().fill(ToolColor.of(provider.rawValue)).frame(width: 7, height: 7)
                Text(AppModel.toolName(provider)).font(.system(size: 13, weight: .semibold)).frame(width: 96, alignment: .leading)
                Text(row.map(ActivityText.state) ?? L("boşta")).foregroundStyle(Theme.textSecondary).lineLimit(1)
                Spacer(minLength: 8)
                if let status = state?.status { statusChip(status) }
                if working { ProgressView().controlSize(.small) }
                buttons(state)
            }
            if let error = state?.error {
                Text(error).font(.system(size: 11)).foregroundStyle(Theme.modified).fixedSize(horizontal: false, vertical: true)
            } else if state?.studioEntries == true {
                Text(L("AMG65 Studio'nun kancaları hâlâ bu aracın ayarlarında."))
                    .font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
            }
        }
        .font(.system(size: 12))
    }

    private func statusChip(_ status: HookInstallStatus) -> some View {
        switch status {
        case .installed: return Chip(text: L("Bağlı"), foreground: Theme.success, background: Theme.success.opacity(0.12), font: .system(size: 10, weight: .medium))
        case .partial: return Chip(text: L("Kısmen bağlı"), foreground: Theme.modified, background: Theme.modified.opacity(0.12), font: .system(size: 10, weight: .medium))
        case .notInstalled: return Chip(text: L("Bağlı değil"), font: .system(size: 10, weight: .medium))
        }
    }

    @ViewBuilder
    private func buttons(_ state: HookState?) -> some View {
        let status = state?.status
        if state?.studioEntries == true {
            Button(L("Studio'dan devral")) { run(.takeOver) }
                .buttonStyle(SecondaryButtonStyle(height: 24))
                .disabled(working || !model.canInstallHooks)
                .help(L("Studio'nun kancalarını kaldırır ve KeyMapper'ınkileri ekler."))
        } else if status != .installed {
            Button(L("Kancaları bağla")) { run(.install) }
                .buttonStyle(SecondaryButtonStyle(height: 24))
                .disabled(working || !model.canInstallHooks || state == nil)
        }
        if status == .installed || status == .partial {
            Button(L("Kaldır")) { run(.remove) }
                .buttonStyle(SecondaryButtonStyle(height: 24))
                .disabled(working)
        }
    }

    private func run(_ change: AppModel.HookChange) {
        working = true
        Task {
            await model.changeHooks(provider, change)
            working = false
        }
    }
}
