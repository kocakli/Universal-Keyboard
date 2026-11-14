import KeyMapperCore
import SwiftUI

/// Logi Options+ style app switcher shown in a device's header:
/// "All apps" + one tab per app with its own key assignments + "+".
struct AppTabBar: View {
    @Environment(AppModel.self) private var model
    let device: KeyboardDevice

    var body: some View {
        let selected = model.selectedApp[device.id]
        HStack(spacing: 6) {
            tab(isOn: selected == nil, help: "Tüm uygulamalar") {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(selected == nil ? Theme.text : Theme.textSecondary)
            } action: {
                model.selectedApp[device.id] = nil
            }
            ForEach(model.appTabs(for: device)) { app in
                tab(isOn: selected == app, help: app.name) {
                    AppIcon(bundleID: app.bundleID).frame(width: 24, height: 24)
                } action: {
                    model.selectedApp[device.id] = app
                }
                .contextMenu {
                    Button("\(app.name) sekmesini kaldır", role: .destructive) { model.removeAppTab(app, device: device) }
                }
            }
            addMenu
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.lineSoft, lineWidth: 1))
    }

    private func tab<Label: View>(isOn: Bool, help: String, @ViewBuilder label: () -> Label, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                label().frame(width: 30, height: 26)
                Capsule().fill(isOn ? Theme.signal : .clear).frame(width: 22, height: 3)
            }
            .padding(.horizontal, 4)
            .padding(.top, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var addMenu: some View {
        Menu {
            Section("Açık uygulamalar") {
                ForEach(AppChoice.running.filter { app in !model.appTabs(for: device).contains(app) }) { app in
                    Button(app.name) { model.addAppTab(app, device: device) }
                }
            }
            Section("Hazır kısayolu olanlar") {
                ForEach(ActionPresets.apps) { preset in
                    Button(preset.appName) { model.addAppTab(AppChoice(bundleID: preset.bundleID, name: preset.appName), device: device) }
                }
            }
            Divider()
            Button("Başka bir uygulama seç…") { if let app = AppChoice.choose() { model.addAppTab(app, device: device) } }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Uygulama ekle")
        .accessibilityLabel("Uygulama ekle")
    }
}

/// Bottom panel while an app tab is selected: what the selected key does in that app.
struct AppKeyPanel: View {
    @Environment(AppModel.self) private var model
    let device: KeyboardDevice
    let app: AppChoice
    let layer: Int
    let slot: KeySlot?
    /// Keycode the key currently sends.
    let code: UInt16?
    let keycodes: KeycodeSet

    @State private var editing: ActionsView.EditTarget?
    @State private var working = false

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            Panel {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        AppIcon(bundleID: app.bundleID).frame(width: 40, height: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Eyebrow(text: "Uygulamaya özel")
                            Text("\(app.name) öndeyken").font(.system(size: 17, weight: .semibold))
                        }
                    }
                    if let slot, let code {
                        selectedKey(slot: slot, code: code)
                    } else {
                        Text("Klavyeden bir tuş seçin. Seçtiğiniz tuşa yalnızca \(app.name) öndeyken çalışacak bir kısayol, uygulama veya medya işlevi atayabilirsiniz.")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: 380)

            Panel {
                VStack(alignment: .leading, spacing: 12) {
                    Eyebrow(text: "\(app.name) için hazır kısayollar")
                    if presets.isEmpty {
                        Text("Bu uygulama için hazır liste yok; \"Özel aksiyon\" ile kısayolu kaydedin.")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    FlowLayout(spacing: 8) {
                        ForEach(presets, id: \.title) { preset in
                            Button {
                                Task { await apply(.keystroke(preset.combo)) }
                            } label: {
                                HStack(spacing: 8) {
                                    Text(preset.title)
                                    Text(preset.combo.display).font(Theme.rounded(12)).foregroundStyle(Theme.signalSoft)
                                }
                            }
                            .buttonStyle(PillButtonStyle(isOn: currentRule?.action == .keystroke(preset.combo), height: 34))
                            .disabled(slot == nil || refusal != nil)
                        }
                        Button {
                            Task { await openCustomEditor() }
                        } label: {
                            Label("Özel aksiyon…", systemImage: "slider.horizontal.3")
                        }
                        .buttonStyle(PillButtonStyle(isOn: false, height: 34))
                        .disabled(slot == nil || refusal != nil)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minHeight: 230)
        .sheet(item: $editing) { target in
            ActionEditorSheet(target: target) { action in
                model.setAction(action, bindingID: target.bindingID, app: target.app)
                editing = nil
            } cancel: {
                editing = nil
            }
        }
    }

    private var presets: [(title: String, combo: KeyCombo)] {
        ActionPresets.apps.first { $0.bundleID == app.bundleID }?.shortcuts ?? []
    }

    private var binding: ActionBinding? { code.flatMap { model.binding(forUsage: $0) } }
    private var currentRule: AppRule? { binding?.appRules.first { $0.bundleID == app.bundleID } }
    private var refusal: String? { code.flatMap { SmartKeys.refusal(for: $0, keycodes: keycodes) } }

    @ViewBuilder
    private func selectedKey(slot: KeySlot, code: UInt16) -> some View {
        if let binding {
            VStack(alignment: .leading, spacing: 10) {
                row(title: app.name, value: currentRule?.action.summary ?? "Varsayılanı kullanır", highlighted: currentRule != nil,
                    edit: { editing = .init(bindingID: binding.id, app: app, initial: currentRule?.action) },
                    remove: currentRule == nil ? nil : { model.setAction(nil, bindingID: binding.id, app: app) })
                row(title: "Diğer uygulamalar", value: binding.defaultAction?.summary ?? "Hiçbir şey yapmaz", highlighted: false,
                    edit: { editing = .init(bindingID: binding.id, app: nil, initial: binding.defaultAction) },
                    remove: nil)
                Text("Akıllı tuş · tetik \(binding.trigger.display)").font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
            }
        } else if let refusal {
            Label(refusal, systemImage: "exclamationmark.circle")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("Bu tuş şu an her uygulamada \"\(keycodes.shortLabel(code).isEmpty ? keycodes.name(for: code) : keycodes.shortLabel(code))\". Bir kısayol seçtiğinizde KeyMapper onu akıllı tuşa çevirir: \(app.name)'ta yeni işlevi yapar, diğer uygulamalarda eskisi gibi çalışır.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if SmartKeys.emulation(of: code, keycodes: keycodes) == nil {
                    Label("Bu tuşun şimdiki işlevi taklit edilemiyor; diğer uygulamalarda bir şey yapmayacak.", systemImage: "info.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.signalSoft)
                }
                if working { ProgressView().controlSize(.small).tint(Theme.signal) }
            }
        }
    }

    private func row(title: String, value: String, highlighted: Bool, edit: @escaping () -> Void, remove: (() -> Void)?) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                Text(value).font(.system(size: 14, weight: .semibold)).foregroundStyle(highlighted ? Theme.signalSoft : Theme.text).lineLimit(1)
            }
            Spacer()
            Button("Düzenle", action: edit).buttonStyle(SecondaryButtonStyle(height: 28))
            if let remove {
                Button(action: remove) { Image(systemName: "xmark") }
                    .buttonStyle(SecondaryButtonStyle(height: 28))
                    .accessibilityLabel("Kaldır")
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.ground))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(highlighted ? Theme.signal.opacity(0.6) : Theme.lineSoft, lineWidth: 1))
    }

    /// Ensures the key is a smart key, then stores the action for this app.
    private func apply(_ action: KeyAction) async {
        guard let binding = await ensureSmartKey() else { return }
        model.setAction(action, bindingID: binding.id, app: app)
        model.notice = "\(app.name): \(action.summary)"
    }

    private func openCustomEditor() async {
        guard let binding = await ensureSmartKey() else { return }
        editing = .init(bindingID: binding.id, app: app, initial: currentRule?.action)
    }

    private func ensureSmartKey() async -> ActionBinding? {
        if let binding { return binding }
        guard let slot else { return nil }
        working = true
        defer { working = false }
        return await model.makeSmartKey(device: device, layer: layer, slot: slot)
    }
}
