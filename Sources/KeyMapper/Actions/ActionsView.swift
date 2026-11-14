import KeyMapperCore
import SwiftUI

/// Editor page for action bindings: trigger key → default action + per-app overrides.
struct ActionsView: View {
    @Environment(AppModel.self) private var model
    @State private var editing: EditTarget?

    /// Which action is being edited in the sheet.
    struct EditTarget: Identifiable {
        let id = UUID()
        let bindingID: UUID
        /// The app rule being edited; nil with an `app` = a new rule, nil without = the default action.
        var ruleID: UUID?
        var app: AppChoice?
        var initial: KeyAction?
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if model.needsAccessibility && !model.accessibilityTrusted { accessibilityBanner }
                howTo
                if model.bindings.isEmpty {
                    emptyState
                } else {
                    ForEach(model.bindings) { binding in
                        BindingCard(binding: binding, edit: { editing = $0 })
                    }
                }
            }
            .padding(EdgeInsets(top: 30, leading: 28, bottom: 80, trailing: 28))
        }
        .sheet(item: $editing) { target in
            ActionEditorSheet(target: target) { action in
                save(action, for: target)
                editing = nil
            } cancel: {
                editing = nil
            }
        }
        .onAppear { model.accessibilityTrusted = ActionPerformer.isAccessibilityTrusted }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(text: "Aksiyonlar", color: Theme.signal)
                Text("Uygulamalar ve kısayollar").font(.system(size: 30, weight: .bold)).tracking(-0.6)
                Text("Bir tuşa basınca uygulama açın, kestirme çalıştırın veya öndeki uygulamaya göre farklı bir kısayol gönderin.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 12)
            Toggle(isOn: Binding(get: { model.actionsEnabled }, set: { model.setActionsEnabled($0) })) {
                Text("Açık").font(.system(size: 13)).foregroundStyle(Theme.textMuted)
            }
            .toggleStyle(.switch)
            .tint(Theme.signal)
            Button {
                model.addBinding()
            } label: {
                Label("Yeni aksiyon", systemImage: "plus")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(ActionStore.nextFreeTrigger(in: model.bindings) == nil)
        }
    }

    private var accessibilityBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "hand.raised.fill").foregroundStyle(Theme.signal)
            VStack(alignment: .leading, spacing: 2) {
                Text("Tuş göndermek için izin gerekiyor").font(.system(size: 13, weight: .semibold))
                Text("Kısayol ve metin aksiyonları macOS Erişilebilirlik izni ister. Uygulama açma ve kestirmeler izinsiz çalışır.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button("İzin ver") { ActionPerformer.requestAccessibility() }
                .buttonStyle(PrimaryButtonStyle(height: 32))
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.signalTint.opacity(0.6)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.signal.opacity(0.5), lineWidth: 1))
    }

    private var howTo: some View {
        HStack(alignment: .top, spacing: 18) {
            step("1", "Tetik tuşu", "Her aksiyon F16–F20 veya F13 gibi normal klavyelerde olmayan bir tuşu kullanır; KeyMapper bu tuşu yakalar, öndeki uygulama görmez.")
            step("2", "Klavyeye ata", "Klavye editöründe paletin \"Aksiyon\" sekmesinden bir fiziksel tuşa atayın (VIA/Vial'de firmware'e, diğer klavyelerde macOS eşlemesi olarak).")
            step("3", "Uygulamaya göre", "Varsayılan işlemi ve belirli uygulamalar öndeyken çalışacak farklı işlemleri seçin.")
        }
    }

    private func step(_ number: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(Theme.rounded(13))
                .foregroundStyle(Theme.onSignal)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Theme.signal))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(text).font(.system(size: 12)).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        KeyboardStage {
            VStack(spacing: 12) {
                Image(systemName: "bolt.horizontal.circle").font(.system(size: 34)).foregroundStyle(Theme.signal)
                Text("Henüz aksiyon yok").font(.system(size: 17, weight: .semibold))
                Text("Örnek: F13'e basınca Safari'de yeni sekme, VS Code'da komut paleti, diğer her yerde Spotlight.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
                Button("İlk aksiyonu oluştur") { model.addBinding() }
                    .buttonStyle(PrimaryButtonStyle())
            }
            .frame(minHeight: 220)
        }
    }

    private func save(_ action: KeyAction?, for target: EditTarget) {
        model.setAction(action, bindingID: target.bindingID, app: target.app)
    }
}

// MARK: - Binding card

private struct BindingCard: View {
    @Environment(AppModel.self) private var model
    let binding: ActionBinding
    let edit: (ActionsView.EditTarget) -> Void
    @State private var name = ""

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    triggerMenu
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Aksiyon adı", text: $name)
                            .textFieldStyle(.plain)
                            .font(.system(size: 17, weight: .semibold))
                            .onSubmit(rename)
                            .onChange(of: name) { _, _ in rename() }
                        if model.refusedBindings.contains(binding.id) {
                            Text("\(binding.trigger.display) başka bir uygulama tarafından kullanılıyor; farklı bir tetik seçin.")
                                .font(.system(size: 12))
                                .foregroundStyle(Color(hex: 0xFF8E8E))
                        } else {
                            Text("Tetik: \(binding.trigger.display) · \(binding.appRules.count) uygulamaya özel kural")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    Spacer()
                    Toggle("", isOn: Binding(get: { binding.isEnabled }, set: { value in
                        var copy = binding; copy.isEnabled = value; model.update(copy)
                    }))
                    .toggleStyle(.switch)
                    .tint(Theme.signal)
                    .labelsHidden()
                    .accessibilityLabel("Aksiyonu etkinleştir")
                    Button(role: .destructive) { model.delete(binding) } label: { Image(systemName: "trash") }
                        .buttonStyle(SecondaryButtonStyle(height: 32))
                        .accessibilityLabel("Aksiyonu sil")
                }

                ActionRow(icon: AnyView(GlobeBadge()), title: "Diğer tüm uygulamalarda", action: binding.defaultAction,
                          placeholder: "Hiçbir şey yapma",
                          edit: { edit(.init(bindingID: binding.id, ruleID: nil, initial: binding.defaultAction)) },
                          remove: nil)

                ForEach(binding.appRules) { rule in
                    ActionRow(icon: AnyView(AppIcon(bundleID: rule.bundleID)), title: rule.appName, action: rule.action, placeholder: "") {
                        edit(.init(bindingID: binding.id, ruleID: rule.id, app: AppChoice(bundleID: rule.bundleID, name: rule.appName), initial: rule.action))
                    } remove: {
                        var copy = binding
                        copy.appRules.removeAll { $0.id == rule.id }
                        model.update(copy)
                    }
                }

                addAppMenu
            }
        }
        .onAppear { name = binding.name }
    }

    private func rename() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != binding.name else { return }
        var copy = binding
        copy.name = trimmed
        model.update(copy)
    }

    private var triggerMenu: some View {
        Menu {
            ForEach(TriggerKey.all) { trigger in
                let inUse = model.bindings.contains { $0.id != binding.id && $0.trigger == trigger.combo }
                Button(trigger.name + (inUse ? " (kullanımda)" : "")) {
                    var copy = binding; copy.trigger = trigger.combo; model.update(copy)
                }
                .disabled(inUse)
            }
        } label: {
            Keycap(kind: .layer, isSelected: false, radius: 12, depth: 8) {
                VStack(spacing: 1) {
                    Text(binding.trigger.display).font(Theme.rounded(15)).foregroundStyle(Theme.cobaltText)
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.textTertiary)
                }
            }
            .frame(width: 62, height: 62)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Tetik tuşunu değiştir")
    }

    private var addAppMenu: some View {
        Menu {
            Section("Açık uygulamalar") {
                ForEach(AppChoice.running.filter { app in !binding.appRules.contains { $0.bundleID == app.bundleID } }) { app in
                    Button(app.name) { edit(.init(bindingID: binding.id, app: app)) }
                }
            }
            Menu("Hazır kısayollar") {
                ForEach(ActionPresets.apps) { preset in
                    Menu(preset.appName) {
                        ForEach(preset.shortcuts, id: \.title) { shortcut in
                            Button("\(shortcut.title)  \(shortcut.combo.display)") {
                                var copy = binding
                                copy.appRules.removeAll { $0.bundleID == preset.bundleID }
                                copy.appRules.append(AppRule(bundleID: preset.bundleID, appName: preset.appName, action: .keystroke(shortcut.combo)))
                                model.update(copy)
                            }
                        }
                    }
                }
            }
            Divider()
            Button("Başka bir uygulama seç…") {
                if let app = AppChoice.choose() { edit(.init(bindingID: binding.id, app: app)) }
            }
        } label: {
            Label("Uygulamaya özel kural ekle", systemImage: "plus")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textMuted)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .overlay(Capsule().strokeBorder(Color(hex: 0x3A3E48), style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

private struct ActionRow: View {
    let icon: AnyView
    let title: String
    let action: KeyAction?
    let placeholder: String
    let edit: () -> Void
    let remove: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            icon.frame(width: 28, height: 28)
            Text(title).font(.system(size: 13, weight: .semibold)).frame(width: 190, alignment: .leading).lineLimit(1)
            Image(systemName: "arrow.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.textTertiary)
            if let action {
                Label(action.summary, systemImage: action.kind.symbol)
                    .font(.system(size: 13))
                    .foregroundStyle(action.kind == .keystroke ? Theme.signalSoft : Theme.text)
                    .lineLimit(1)
            } else {
                Text(placeholder).font(.system(size: 13)).foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            Button("Düzenle", action: edit).buttonStyle(SecondaryButtonStyle(height: 28))
            if let remove {
                Button(action: remove) { Image(systemName: "xmark") }
                    .buttonStyle(SecondaryButtonStyle(height: 28))
                    .accessibilityLabel("Kuralı kaldır")
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.ground))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.lineSoft, lineWidth: 1))
    }
}

struct AppIcon: View {
    let bundleID: String

    var body: some View {
        if let image = AppChoice.icon(for: bundleID) {
            Image(nsImage: image).resizable().interpolation(.high)
        } else {
            RoundedRectangle(cornerRadius: 7).fill(Theme.raised)
                .overlay(Image(systemName: "app").foregroundStyle(Theme.textTertiary))
        }
    }
}

private struct GlobeBadge: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(Theme.raised)
            .overlay(Image(systemName: "globe").font(.system(size: 13)).foregroundStyle(Theme.textSecondary))
    }
}

// MARK: - Action editor

struct ActionEditorSheet: View {
    let target: ActionsView.EditTarget
    let save: (KeyAction?) -> Void
    let cancel: () -> Void

    @State private var kind: KeyAction.Kind = .openApp
    @State private var app: AppChoice?
    @State private var url = ""
    @State private var shortcut = ""
    @State private var shortcuts: [String] = []
    @State private var combo: KeyCombo?
    @State private var text = ""
    @State private var systemKey: SystemKey = .playPause

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                if let app = target.app { AppIcon(bundleID: app.bundleID).frame(width: 28, height: 28) }
                Text(title).font(.system(size: 18, weight: .semibold))
            }

            FlowLayout(spacing: 6) {
                ForEach(KeyAction.Kind.allCases) { option in
                    Button {
                        kind = option
                    } label: {
                        Label(option.title, systemImage: option.symbol)
                    }
                    .buttonStyle(PillButtonStyle(isOn: kind == option, height: 32))
                }
            }

            Group {
                switch kind {
                case .openApp: appFields
                case .openURL: field("https://… , ~/Belgeler/rapor.pdf veya zoommtg://…", text: $url)
                case .runShortcut: shortcutFields
                case .keystroke: keystrokeFields
                case .typeText: field("Yazılacak metin", text: $text)
                case .systemKey:
                    FlowLayout(spacing: 6) {
                        ForEach(SystemKey.allCases) { key in
                            Button(key.title) { systemKey = key }
                                .buttonStyle(PillButtonStyle(isOn: systemKey == key, height: 32))
                        }
                    }
                }
            }
            .frame(minHeight: 70, alignment: .top)

            if kind.needsAccessibility {
                Label("Bu işlem için KeyMapper'ın Erişilebilirlik izni olmalı.", systemImage: "info.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }

            HStack {
                if target.initial != nil {
                    Button("Kaldır") { save(nil) }.buttonStyle(SecondaryButtonStyle())
                }
                Spacer()
                Button("Vazgeç", action: cancel)
                    .buttonStyle(SecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button("Kaydet") { save(currentAction) }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(currentAction == nil)
            }
        }
        .padding(22)
        .frame(width: 560)
        .background(Theme.surface)
        .foregroundStyle(Theme.text)
        .preferredColorScheme(.dark)
        .onAppear(perform: load)
        .task { shortcuts = await ActionPerformer.shortcutNames() }
    }

    private var title: String {
        if let app = target.app { return "\(app.name) öndeyken" }
        return "Diğer tüm uygulamalarda"
    }

    private var appFields: some View {
        HStack(spacing: 10) {
            if let app {
                AppIcon(bundleID: app.bundleID).frame(width: 32, height: 32)
                Text(app.name).font(.system(size: 14, weight: .semibold))
            } else {
                Text("Uygulama seçilmedi").foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            Menu {
                ForEach(AppChoice.running) { choice in Button(choice.name) { app = choice } }
            } label: {
                Text("Açık uygulamalar").font(.system(size: 13)).padding(.horizontal, 12).frame(height: 32)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.control))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.line))
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            Button("Seç…") { if let choice = AppChoice.choose() { app = choice } }
                .buttonStyle(SecondaryButtonStyle(height: 32))
        }
    }

    private var shortcutFields: some View {
        HStack(spacing: 10) {
            field("Kestirme adı", text: $shortcut)
            if !shortcuts.isEmpty {
                Menu {
                    ForEach(shortcuts, id: \.self) { name in Button(name) { shortcut = name } }
                } label: {
                    Text("Listeden seç").font(.system(size: 13)).padding(.horizontal, 12).frame(height: 36)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.control))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.line))
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            }
        }
    }

    private var keystrokeFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                KeyRecorder(combo: $combo)
                Menu {
                    if let app = target.app, let preset = ActionPresets.apps.first(where: { $0.bundleID == app.bundleID }) {
                        Section(preset.appName) {
                            ForEach(preset.shortcuts, id: \.title) { item in
                                Button("\(item.title)  \(item.combo.display)") { combo = item.combo }
                            }
                        }
                    }
                    Section("Sistem") {
                        ForEach(ActionPresets.system, id: \.title) { item in
                            Button("\(item.title)  \(item.combo.display)") { combo = item.combo }
                        }
                    }
                } label: {
                    Text("Hazır").font(.system(size: 13)).padding(.horizontal, 12).frame(height: 36)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.control))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.line))
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            }
            Text("Kaydet'e tıklayıp göndermek istediğiniz kısayola basın (ör. ⌘⇧P).")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func field(_ prompt: String, text: Binding<String>) -> some View {
        TextField(prompt, text: text)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.ground))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
    }

    private var currentAction: KeyAction? {
        switch kind {
        case .openApp: return app.map { .openApp(bundleID: $0.bundleID, name: $0.name) }
        case .openURL: return url.trimmingCharacters(in: .whitespaces).isEmpty ? nil : .openURL(url)
        case .runShortcut: return shortcut.trimmingCharacters(in: .whitespaces).isEmpty ? nil : .runShortcut(shortcut)
        case .keystroke: return combo.map { .keystroke($0) }
        case .typeText: return text.isEmpty ? nil : .typeText(text)
        case .systemKey: return .systemKey(systemKey)
        }
    }

    private func load() {
        guard let action = target.initial else {
            kind = target.app == nil ? .openApp : .keystroke
            return
        }
        kind = action.kind
        switch action {
        case let .openApp(bundleID, name): app = AppChoice(bundleID: bundleID, name: name)
        case let .openURL(value): url = value
        case let .runShortcut(value): shortcut = value
        case let .keystroke(value): combo = value
        case let .typeText(value): text = value
        case let .systemKey(value): systemKey = value
        }
    }
}

/// Click, then press a key combination; it is captured locally (our window is in front, no permission needed).
struct KeyRecorder: View {
    @Binding var combo: KeyCombo?
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            recording ? stop() : start()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: recording ? "record.circle" : "keyboard")
                    .foregroundStyle(recording ? Theme.signal : Theme.textSecondary)
                Text(recording ? "Kısayola basın…" : (combo?.display ?? "Kısayol kaydet"))
                    .font(combo == nil || recording ? .system(size: 13) : Theme.rounded(15))
                    .foregroundStyle(recording ? Theme.signalSoft : Theme.text)
            }
            .padding(.horizontal, 14)
            .frame(minWidth: 200, minHeight: 36, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(recording ? Theme.signalTint : Theme.ground))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(recording ? Theme.signal : Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 0x35 && event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
                stop() // Escape cancels
                return nil
            }
            combo = KeyRecorder.combo(from: event)
            stop()
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    static func combo(from event: NSEvent) -> KeyCombo {
        var modifiers: KeyCombo.Modifiers = []
        let flags = event.modifierFlags
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        return KeyCombo(keyCode: event.keyCode, modifiers: modifiers, key: legend(for: event))
    }

    private static let specialKeys: [UInt16: String] = [
        0x24: "↩", 0x30: "⇥", 0x31: "Space", 0x33: "⌫", 0x35: "Esc", 0x75: "⌦",
        0x7B: "←", 0x7C: "→", 0x7D: "↓", 0x7E: "↑", 0x73: "Home", 0x77: "End", 0x74: "PgUp", 0x79: "PgDn",
        0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4", 0x60: "F5", 0x61: "F6", 0x62: "F7", 0x64: "F8",
        0x65: "F9", 0x6D: "F10", 0x67: "F11", 0x6F: "F12", 0x69: "F13", 0x6B: "F14", 0x71: "F15", 0x6A: "F16",
        0x40: "F17", 0x4F: "F18", 0x50: "F19", 0x5A: "F20",
    ]

    private static func legend(for event: NSEvent) -> String {
        if let special = specialKeys[event.keyCode] { return special }
        let characters = event.charactersIgnoringModifiers ?? ""
        return characters.isEmpty ? String(format: "#%02X", event.keyCode) : characters.uppercased()
    }
}

/// Sidebar entry for the actions page.
struct ActionsNavCard: View {
    @Environment(AppModel.self) private var model
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "bolt.horizontal.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? Theme.onSignal : Theme.signal)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(isSelected ? Theme.signal : Theme.signalTint))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Aksiyonlar").font(.system(size: 14, weight: .semibold))
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(isSelected ? Theme.raised : .clear))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(isSelected ? Color(hex: 0x30343D) : .clear, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var subtitle: String {
        guard model.actionsEnabled else { return "Kapalı" }
        let count = model.bindings.filter(\.isEnabled).count
        return count == 0 ? "Uygulama aç, kısayol gönder" : "\(count) aktif aksiyon"
    }
}
