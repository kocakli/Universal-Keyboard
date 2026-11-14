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
                Text("KeyMapper").font(.system(size: 15, weight: .bold)).tracking(-0.2)
                Spacer()
                Text("\(model.devices.count) klavye").font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
            }

            if model.devices.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Bağlı klavye yok").font(.system(size: 14, weight: .semibold))
                    Text("Bluetooth klavyeler uykudaysa bir tuşa basarak uyandırın.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(hex: 0x1B1D22)))
            } else {
                ForEach(model.devices) { device in
                    DeviceMenuCard(device: device, openEditor: { openEditor(device) })
                }
            }

            actionsRow

            StatusBanner()

            Button("Editörü aç") { openEditor(model.selectedDevice) }
                .buttonStyle(PrimaryButtonStyle(height: 40))
                .frame(maxWidth: .infinity)
                .keyboardShortcut("e")

            HStack {
                Toggle(isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) })) {
                    Text("Girişte başlat").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                }
                .toggleStyle(.checkbox)
                .tint(Theme.signal)
                Spacer()
                Button("Çıkış  ⌘Q") { NSApp.terminate(nil) }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .keyboardShortcut("q")
            }
        }
        .padding(16)
        .frame(width: 360)
        .background(Theme.surface)
        .foregroundStyle(Theme.text)
        .preferredColorScheme(.dark)
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
                .foregroundStyle(Theme.signal)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.signalTint))
            VStack(alignment: .leading, spacing: 2) {
                Text("Aksiyonlar").font(.system(size: 13, weight: .semibold))
                Text(actionsSubtitle).font(.system(size: 12)).foregroundStyle(Theme.textSecondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            Toggle("", isOn: Binding(get: { model.actionsEnabled }, set: { model.setActionsEnabled($0) }))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(Theme.signal)
                .labelsHidden()
                .accessibilityLabel("Aksiyonları aç/kapat")
            Button("Düzenle") {
                model.showingActions = true
                openWindow(id: EditorWindow.id)
                NSApp.activate(ignoringOtherApps: true)
            }
            .buttonStyle(SecondaryButtonStyle(height: 28, emphasized: true))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(hex: 0x1B1D22)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
    }

    private var actionsSubtitle: String {
        let active = model.bindings.filter(\.isEnabled)
        guard model.actionsEnabled else { return "Kapalı" }
        if active.isEmpty { return "Tuşa uygulama veya kısayol atayın" }
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
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(device.capability == .osRemap ? Color(hex: 0x1F2229) : Color(hex: 0x2A1C14))
                    KeyboardSilhouette(keys: model.states[device.id]?.definition.keys ?? [],
                                       color: device.capability == .osRemap ? Theme.textTertiary : Theme.signal)
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
                Eyebrow(text: "Layout")
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
                Circle().fill(device.capability == .osRemap ? Theme.cobalt : Theme.signal).frame(width: 6, height: 6)
                Text(status).font(.system(size: 12)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                Spacer(minLength: 4)
                if model.activity[device.id] != nil { ProgressView().controlSize(.mini).tint(Theme.signal) }
                Button("Düzenle", action: openEditor)
                    .buttonStyle(SecondaryButtonStyle(height: 28, emphasized: true))
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(hex: 0x1B1D22)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
    }

    private var status: String {
        if let activity = model.activity[device.id] { return activity }
        if device.capability == .osRemap {
            let count = model.currentRemaps(device).count
            return count == 0 ? "macOS eşlemesi yok" : "\(count) eşleme · bağlanınca yeniden uygulanır"
        }
        if let profile = model.assignedProfile(for: device) { return "\(profile.name) uygulandı" }
        return "Henüz profil yok"
    }

    /// "+": import a file, plus ready made remaps for macOS-level keyboards.
    private var addMenu: some View {
        Menu {
            Button("Dosyadan içe aktar (.vil / VIA .json)…") {
                Task {
                    await model.ensureLoaded(device)
                    model.importLayoutFile(for: device)
                }
            }
            if device.capability == .osRemap {
                Divider()
                ForEach(AlphaLayout.all.dropFirst()) { layout in
                    Button("Alfabe: \(layout.name)") { model.mergeRemaps(AlphaLayout.remaps(to: layout), device: device) }
                }
                ForEach(HIDUtilRemapper.presets, id: \.name) { preset in
                    Button(preset.name) { model.mergeRemaps(preset.remaps, device: device) }
                }
                Divider()
                Button("Tüm eşlemeleri kaldır") { model.setRemaps([], device: device, persist: true) }
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 30, height: 30)
                .overlay(Circle().strokeBorder(Color(hex: 0x3A3E48), style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                .contentShape(Circle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Layout ekle")
    }
}

/// Last notice / error, dismissable toast.
struct StatusBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let error = model.errorMessage {
            toast(error, icon: "exclamationmark.triangle.fill", color: Color(hex: 0xFF8E8E)) { model.errorMessage = nil }
        } else if let notice = model.notice {
            toast(notice, icon: "checkmark.circle.fill", color: Theme.signal) { model.notice = nil }
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
                .accessibilityLabel("Kapat")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: 520)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.raised))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
    }
}
