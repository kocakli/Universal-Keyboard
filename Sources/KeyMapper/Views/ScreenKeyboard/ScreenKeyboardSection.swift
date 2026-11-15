import AppKit
import KeyMapperCore
import KeyMapperUsage
import SwiftUI

/// Everything for keyboards with their own display: AI usage on the LED matrix, LCD and clock, backlight,
/// the keyboard's own key table and device settings. Tabs are grouped as Ekran / Işık / Klavye.
struct ScreenKeyboardSection: View {
    @Environment(AppModel.self) private var model
    let device: KeyboardDevice
    let channel: ScreenKeyboardChannel
    @AppStorage("screenKeyboard.tab") private var storedTab = ScreenTab.usage.rawValue

    var body: some View {
        let tabs = ScreenTab.available(for: channel)
        let tab = ScreenTab(rawValue: storedTab).flatMap { tabs.contains($0) ? $0 : nil } ?? tabs[0]
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(L("Ekran ve ışık")).font(.system(size: 14, weight: .semibold))
                Text(channel.model.name).font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                Spacer(minLength: 12)
                ChannelStatusLine(device: device, channel: channel)
            }
            .padding(EdgeInsets(top: 14, leading: 16, bottom: 10, trailing: 16))
            if channel.link == .wired {
                ScreenStatusStrip(device: device).padding(EdgeInsets(top: 0, leading: 16, bottom: 12, trailing: 16))
            }
            ScreenTabBar(tabs: tabs, selection: tab) { storedTab = $0.rawValue }
                .padding(EdgeInsets(top: 0, leading: 12, bottom: 10, trailing: 12))
            Rectangle().fill(Theme.line).frame(height: 1)
            Group {
                switch tab {
                case .usage: UsageTab()
                case .display: LEDDisplayTab(device: device)
                case .media: MediaClockTab(device: device)
                case .effects: EffectsTab(device: device, channel: channel)
                case .keyColors: KeyColorsTab(device: device)
                case .keys: KeysTab(device: device)
                case .settings: SettingsTab(device: device)
                }
            }
            .padding(16)
        }
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.line))
    }
}

enum ScreenTab: String, CaseIterable, Identifiable {
    case usage, display, media, effects, keyColors, keys, settings

    enum Group: CaseIterable { case screen, light, keyboard }

    var id: String { rawValue }

    var group: Group {
        switch self {
        case .usage, .display, .media: return .screen
        case .effects, .keyColors: return .light
        case .keys, .settings: return .keyboard
        }
    }

    var title: String {
        switch self {
        case .usage: return L("Yapay zekâ")
        case .display: return L("LED ekran")
        case .media: return L("LCD ve saat")
        case .effects: return L("Efektler")
        case .keyColors: return L("Tuş renkleri")
        case .keys: return L("Tuş atamaları")
        case .settings: return L("Ayarlar")
        }
    }

    /// The 2.4 GHz receiver carries lighting and the key table, as in AMG65 Studio; the rest needs the cable.
    static func available(for channel: ScreenKeyboardChannel) -> [ScreenTab] {
        channel.link == .wired ? allCases : [.effects, .keyColors, .keys]
    }
}

extension ScreenTab.Group {
    var title: String {
        switch self {
        case .screen: return L("Ekran")
        case .light: return L("Işık")
        case .keyboard: return L("Klavye")
        }
    }
}

/// Tabs in labelled groups, a divider between groups; groups wrap onto a second line in a narrow window.
private struct ScreenTabBar: View {
    let tabs: [ScreenTab]
    let selection: ScreenTab
    let select: (ScreenTab) -> Void

    var body: some View {
        let groups = ScreenTab.Group.allCases.filter { group in tabs.contains { $0.group == group } }
        WrapLayout(spacing: 12, lineSpacing: 6) {
            ForEach(groups, id: \.self) { group in
                HStack(spacing: 4) {
                    if group != groups.first {
                        Rectangle().fill(Theme.line).frame(width: 1, height: 16).padding(.trailing, 10)
                    }
                    // Smaller and lighter than the tabs, so it reads as a label.
                    Text(group.title)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.trailing, 4)
                    ForEach(tabs.filter { $0.group == group }) { tab in
                        Button(tab.title) { select(tab) }
                            .buttonStyle(PillButtonStyle(isOn: tab == selection, style: .inverted, height: 26))
                            .accessibilityAddTraits(tab == selection ? .isSelected : [])
                    }
                }
            }
        }
    }
}

/// What the keyboard is doing right now: clock, LED matrix, AI tool activity, connection. Same on every tab.
private struct ScreenStatusStrip: View {
    @Environment(AppModel.self) private var model
    let device: KeyboardDevice
    @State private var started = Date()

    var body: some View {
        let prefs = model.preferences(for: device)
        let stopped = model.screenStatus[device.id]?.link.isStopped == true
        WrapLayout(spacing: 8, lineSpacing: 8) {
            item {
                Image(systemName: "clock").foregroundStyle(Theme.textSecondary)
                // Redrawn on its own: the rest of the strip only redraws when the model changes. The schedule only
                // triggers redraws; its dates lag behind the real time.
                TimelineView(.periodic(from: started, by: 5)) { _ in
                    let now = Date()
                    HStack(spacing: 6) {
                        Text(now.formatted(.dateTime.hour().minute().locale(L10n.current.locale)))
                            .monospacedDigit().font(.system(size: 12, weight: .semibold))
                        Text(ClockText.lastSync(prefs.lastClockSync, now: now, short: true)).foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            item {
                if prefs.display.enabled && !stopped {
                    TimelineView(.periodic(from: started, by: 0.5)) { context in
                        let seconds = context.date.timeIntervalSince(started)
                        LEDMatrixPreview(pixels: model.ledScene(for: device, seconds: seconds, step: Int(seconds * 2), now: context.date),
                                         height: 14)
                    }
                } else {
                    LEDMatrixPreview(pixels: [], height: 14)
                }
                Text(!prefs.display.enabled ? L("Klavyenin kendi animasyonu")
                     : stopped ? L("Gönderim durdu") : L("Kullanım gösteriliyor"))
                    .foregroundStyle(Theme.textSecondary)
            }
            if let row = ActivityCollector.selected(model.activityRows), row.state != .unknown {
                item {
                    Circle().fill(ToolColor.of(row.provider.rawValue)).frame(width: 7, height: 7)
                    Text(AppModel.toolName(row.provider)).font(.system(size: 12, weight: .semibold))
                    Text(ActivityText.state(row)).foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    private func item<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 6) { content() }
            .font(.system(size: 12))
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.raised))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Theme.line))
    }
}

/// When the keyboard clock was last set, for the status strip (`short`) and the Clock card.
enum ClockText {
    static func lastSync(_ date: Date?, now: Date, short: Bool) -> String {
        guard let date else { return short ? L("eşitlenmedi") : L("Henüz eşitlenmedi") }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = L10n.current.locale
        formatter.unitsStyle = short ? .short : .full
        let ago = formatter.localizedString(for: min(date, now), relativeTo: now)
        return short ? L("eşitlendi %@", ago) : L("Son eşitleme: %@", ago)
    }
}

extension ScreenKeyboardStatus.Link {
    /// Nothing reaches the keyboard: another program holds it, a replug is needed, or the channel failed.
    var isStopped: Bool {
        switch self {
        case .busy, .needsReconnect, .failed: return true
        case .idle, .ready: return false
        }
    }
}

/// Connection, the running job (with upload progress) and any stop that needs the user.
private struct ChannelStatusLine: View {
    @Environment(AppModel.self) private var model
    let device: KeyboardDevice
    let channel: ScreenKeyboardChannel

    var body: some View {
        let status = model.screenStatus[device.id] ?? .init()
        HStack(spacing: 8) {
            if let upload = model.screenUploads[device.id], upload.isRunning {
                ProgressView(value: upload.progress).frame(width: 80)
                Text(upload.kind == .lcd ? L("LCD resmi yükleniyor") : L("LED animasyonu yükleniyor"))
                Text(upload.progress.formatted(.percent.precision(.fractionLength(0)).locale(L10n.current.locale))).monospacedDigit()
            } else if let working = status.working {
                ProgressView().controlSize(.small)
                Text(working)
            } else {
                switch status.link {
                case .idle, .ready:
                    Image(systemName: channel.link == .wired ? "cable.connector" : "antenna.radiowaves.left.and.right")
                    Text(channel.link == .wired ? L("USB kablosu") : L("2.4 GHz alıcı"))
                case .busy:
                    Image(systemName: "lock.fill")
                    Text(L("Başka bir uygulama (AMG65 Studio) klavyeyi kullanıyor"))
                    Button(L("Tekrar dene")) { Task { await model.retryScreenKeyboard(device) } }
                        .buttonStyle(SecondaryButtonStyle(height: 24))
                case .needsReconnect:
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.error)
                    Text(L("Gönderim durduruldu; kabloyu çıkarıp yeniden takın"))
                    if let stop = status.stop { StopDetailsButton(stop: stop) }
                case let .failed(message):
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.error)
                    Text(message).lineLimit(2)
                    Button(L("Tekrar dene")) { Task { await model.retryScreenKeyboard(device) } }
                        .buttonStyle(SecondaryButtonStyle(height: 24))
                }
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(Theme.textSecondary)
    }
}

private struct StopDetailsButton: View {
    let stop: ScreenKeyboardStop
    @State private var shown = false

    var body: some View {
        Button(L("Neden?")) { shown.toggle() }
            .buttonStyle(SecondaryButtonStyle(height: 24))
            .popover(isPresented: $shown, arrowEdge: .bottom) { StopDetails(stop: stop) }
    }
}

/// What was recorded when sending stopped: the cause, when, the keyboard's reply, and how many sends had finished
/// since the channel opened.
private struct StopDetails: View {
    let stop: ScreenKeyboardStop

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Gönderim neden durdu")).font(.system(size: 13, weight: .semibold))
            Text(stop.error.localizedDescription).fixedSize(horizontal: false, vertical: true)
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    Text(L("Ne zaman")).foregroundStyle(Theme.textTertiary)
                    Text(when)
                }
                GridRow {
                    Text(L("Yanıt")).foregroundStyle(Theme.textTertiary)
                    Text(stop.detail).font(.system(size: 11, design: .monospaced))
                }
            }
            Text(stop.completedBefore == 0
                 ? L("Kanal açıldıktan sonra hiçbir gönderim tamamlanmamıştı; klavye, önceki bir programın yarım bıraktığı işlemin devamını bekliyor olabilir.")
                 : L("Kanal açıldıktan sonra sorunsuz biten gönderim sayısı: %@", "\(stop.completedBefore)"))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 12))
        .textSelection(.enabled)
        .padding(14)
        .frame(width: 340, alignment: .leading)
    }

    /// Date and time to the second (to line it up with app launches), and how long ago.
    private var when: String {
        let locale = L10n.current.locale
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        let now = Date()
        return stop.date.formatted(.dateTime.day().month().hour().minute().second().locale(locale))
            + " · " + formatter.localizedString(for: min(stop.date, now), relativeTo: now)
    }
}

/// Words for an AI tool's current activity.
enum ActivityText {
    static func state(_ row: ActivityRow) -> String {
        if row.stale { return L("bir süredir ses yok") }
        switch row.state {
        case .running: return summary(row.summary) ?? L("çalışıyor")
        case .queued: return L("sırada")
        case .waitingApproval: return L("onay bekliyor")
        case .waitingInput: return L("yanıt bekliyor")
        case .completed: return L("bitti")
        case .error: return L("hata verdi")
        case .unknown: return L("boşta")
        }
    }

    private static func summary(_ summary: ActivitySummary) -> String? {
        switch summary {
        case .runningCommand: return L("komut çalıştırıyor")
        case .readingFiles: return L("dosya okuyor")
        case .editingFiles: return L("dosya düzenliyor")
        case .searching: return L("arıyor")
        case .usingTool: return L("araç kullanıyor")
        case .compacting: return L("bağlamı sıkıştırıyor")
        default: return nil
        }
    }
}
