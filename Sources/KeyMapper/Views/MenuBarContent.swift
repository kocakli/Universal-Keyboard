import KeyMapperCore
import SwiftUI

/// Popover shown from the menu bar icon: connected keyboards and one-click layout switching.
struct MenuBarContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                AppMark(size: 26)
                Text("KeyMapper").font(.system(size: 14, weight: .semibold))
                Spacer()
                Text(L("%@ klavye", "\(model.devices.count)")).font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
            }

            if model.devices.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("Bağlı klavye yok")).font(.system(size: 14, weight: .semibold))
                    Text(L("Bluetooth klavyeler uykudaysa bir tuşa basarak uyandırın."))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.raised))
            } else {
                ForEach(model.devices) { device in
                    DeviceMenuCard(device: device, openEditor: { openEditor(device) })
                }
            }

            actionsRow

            StatusBanner()

            Button(L("Editörü aç")) { openEditor(model.selectedDevice) }
                .buttonStyle(PrimaryButtonStyle(height: 40))
                .frame(maxWidth: .infinity)
                .keyboardShortcut("e")

            HStack {
                Toggle(isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) })) {
                    Text(L("Girişte başlat")).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                }
                .toggleStyle(.checkbox)
                .tint(Theme.accent)
                Spacer()
                LanguageMenu()
                Button(L("Çıkış  ⌘Q")) { NSApp.terminate(nil) }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .keyboardShortcut("q")
            }
        }
        .padding(16)
        .frame(width: 360)
        .foregroundStyle(Theme.text)
        .environment(\.locale, model.language.locale)
        .id(model.language)
    }

    private func openEditor(_ device: KeyboardDevice?) {
        if let device {
            model.selectedDeviceID = device.id
            model.showingActions = false
        }
        openWindow(id: EditorWindow.id)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Actions summary: on/off and a shortcut to the actions page.
    private var actionsRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "bolt.horizontal.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.accentTint))
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Aksiyonlar")).font(.system(size: 13, weight: .semibold))
                Text(actionsSubtitle).font(.system(size: 12)).foregroundStyle(Theme.textSecondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            Toggle("", isOn: Binding(get: { model.actionsEnabled }, set: { model.setActionsEnabled($0) }))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(Theme.accent)
                .labelsHidden()
                .accessibilityLabel(L("Aksiyonları aç/kapat"))
            Button(L("Düzenle")) {
                model.showingActions = true
                openWindow(id: EditorWindow.id)
                NSApp.activate(ignoringOtherApps: true)
            }
            .buttonStyle(SecondaryButtonStyle(height: 28, emphasized: true))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.raised))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
    }

    private var actionsSubtitle: String {
        let active = model.bindings.filter(\.isEnabled)
        guard model.actionsEnabled else { return L("Kapalı") }
        if active.isEmpty { return L("Tuşa uygulama veya kısayol atayın") }
        let names = active.prefix(3).map { "\($0.trigger.display) \($0.name)" }.joined(separator: " · ")
        return names
    }
}

private struct DeviceMenuCard: View {
    @Environment(AppModel.self) private var model
    let device: KeyboardDevice
    let openEditor: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(device.capability == .osRemap ? Theme.raised : Theme.accentTint)
                    KeyboardSilhouette(keys: model.states[device.id]?.definition.keys ?? [],
                                       color: device.capability == .osRemap ? Theme.textTertiary : Theme.accent)
                        .frame(width: 26, height: 16)
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.displayName).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    Text("\(device.brand.name) · \(device.transportLabel)").font(.system(size: 12)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                CapabilityBadge(capability: device.capability)
            }

            VStack(alignment: .leading, spacing: 8) {
                Eyebrow(text: L("Layout"))
                FlowLayout(spacing: 6) {
                    ForEach(model.profiles(for: device)) { profile in
                        let isOn = model.assignedProfile(for: device)?.id == profile.id
                        Button(profile.name) { Task { await model.apply(profile, to: device) } }
                            .buttonStyle(PillButtonStyle(isOn: isOn))
                            .accessibilityAddTraits(isOn ? .isSelected : [])
                    }
                    addMenu
                }
            }

            HStack(spacing: 8) {
                Circle().fill(device.capability == .osRemap ? Theme.layerText : Theme.accent).frame(width: 6, height: 6)
                Text(status).font(.system(size: 12)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                Spacer(minLength: 4)
                if model.activity[device.id] != nil { ProgressView().controlSize(.mini).tint(Theme.accent) }
                Button(L("Düzenle"), action: openEditor)
                    .buttonStyle(SecondaryButtonStyle(height: 28, emphasized: true))
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.raised))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
    }

    private var status: String {
        if let activity = model.activity[device.id] { return activity }
        if let firmware = model.firmware[device.id], firmware.isUpdateAvailable, let latest = firmware.latest {
            return L("Firmware güncellemesi var: %@", "\(latest.version)")
        }
        if device.capability == .osRemap {
            let count = model.currentRemaps(device).count
            return count == 0 ? L("macOS eşlemesi yok") : L("%@ eşleme · bağlanınca yeniden uygulanır", "\(count)")
        }
        if let profile = model.assignedProfile(for: device) { return L("%@ uygulandı", "\(profile.name)") }
        return L("Henüz profil yok")
    }

    /// "+": import a file, plus ready made remaps for macOS-level keyboards.
    private var addMenu: some View {
        Menu {
            Button(L("Dosyadan içe aktar (.vil / VIA .json)…")) {
                Task {
                    await model.ensureLoaded(device)
                    model.importLayoutFile(for: device)
                }
            }
            if device.capability == .osRemap {
                Divider()
                ForEach(AlphaLayout.all.dropFirst()) { layout in
                    Button(L("Alfabe: %@", layout.name)) { model.mergeRemaps(AlphaLayout.remaps(to: layout), device: device) }
                }
                ForEach(HIDUtilRemapper.presets, id: \.name) { preset in
                    Button(L(preset.name)) { model.mergeRemaps(preset.remaps, device: device) }
                }
                Divider()
                Button(L("Tüm eşlemeleri kaldır")) { model.setRemaps([], device: device, persist: true) }
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 30, height: 30)
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(L("Layout ekle"))
    }
}

/// Last notice / error, dismissable toast.
struct StatusBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let error = model.errorMessage {
            toast(error, icon: "exclamationmark.triangle.fill", color: Theme.error) { model.errorMessage = nil }
        } else if let notice = model.notice {
            toast(notice, icon: "checkmark.circle.fill", color: Theme.accent) { model.notice = nil }
        }
    }

    private func toast(_ text: String, icon: String, color: Color, dismiss: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).foregroundStyle(color)
            Text(text).font(.system(size: 12)).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: dismiss) { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textSecondary)
                .accessibilityLabel(L("Kapat"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: 520)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.raised))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
    }
}
