import KeyMapperCore
import SwiftUI

/// Popover shown from the menu bar icon: connected keyboards and quick layout assignment.
struct MenuBarContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("KeyMapper", systemImage: "keyboard")
                    .font(.headline)
                Spacer()
                Text("\(model.devices.count) klavye")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if model.devices.isEmpty {
                Text("Bağlı klavye bulunamadı. Bluetooth klavyeler uykudaysa bir tuşa basarak uyandırın.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 6)
            } else {
                ForEach(model.devices) { device in
                    DeviceMenuCard(device: device, openEditor: { openEditor(device) })
                }
            }

            StatusBanner()

            Divider()

            HStack {
                Button {
                    openEditor(model.selectedDevice)
                } label: {
                    Label("Editörü aç", systemImage: "slider.horizontal.3")
                }
                Spacer()
                Toggle("Girişte başlat", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                    .toggleStyle(.checkbox)
                    .font(.caption)
            }
            HStack {
                Spacer()
                Button("Çıkış") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
        .padding(14)
        .frame(width: 360)
    }

    private func openEditor(_ device: KeyboardDevice?) {
        if let device { model.selectedDeviceID = device.id }
        openWindow(id: EditorWindow.id)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct DeviceMenuCard: View {
    @Environment(AppModel.self) private var model
    let device: KeyboardDevice
    let openEditor: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.displayName).font(.system(.body, weight: .semibold))
                    Text("\(device.brand.name) · \(device.transportLabel)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                CapabilityBadge(capability: device.capability)
            }

            HStack(spacing: 8) {
                Menu {
                    let profiles = model.profiles(for: device)
                    if profiles.isEmpty {
                        Text("Kayıtlı layout yok")
                    }
                    ForEach(profiles) { profile in
                        Button {
                            Task { await model.apply(profile, to: device) }
                        } label: {
                            if model.assignedProfile(for: device)?.id == profile.id {
                                Label(profile.name, systemImage: "checkmark")
                            } else {
                                Text(profile.name)
                            }
                        }
                    }
                    if device.capability == .osRemap {
                        Divider()
                        Menu("Hazır eşlemeler") {
                            ForEach(AlphaLayout.all.dropFirst()) { layout in
                                Button("Alfabe: \(layout.name)") { model.mergeRemaps(AlphaLayout.remaps(to: layout), device: device) }
                            }
                            Divider()
                            ForEach(HIDUtilRemapper.presets, id: \.name) { preset in
                                Button(preset.name) { model.mergeRemaps(preset.remaps, device: device) }
                            }
                        }
                        Button("Tüm eşlemeleri kaldır") { model.setRemaps([], device: device, persist: true) }
                    }
                    Divider()
                    Button("Dosyadan içe aktar…") {
                        Task {
                            await model.ensureLoaded(device)
                            model.importLayoutFile(for: device)
                        }
                    }
                } label: {
                    Label(model.assignedProfile(for: device)?.name ?? "Layout ata", systemImage: "square.grid.3x3")
                        .lineLimit(1)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Spacer()

                if let activity = model.activity[device.id] {
                    ProgressView().controlSize(.small)
                    Text(activity).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }

                Button("Düzenle", action: openEditor)
                    .controlSize(.small)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
    }
}

struct CapabilityBadge: View {
    let capability: DeviceCapability

    var body: some View {
        Text(capability.title)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.18)))
            .foregroundStyle(color)
            .help(capability.detail)
    }

    private var color: Color {
        switch capability {
        case .vial: return .purple
        case .via: return .blue
        case .osRemap: return .orange
        }
    }
}

/// Last notice / error, dismissable.
struct StatusBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let error = model.errorMessage {
            banner(error, icon: "exclamationmark.triangle.fill", color: .red) { model.errorMessage = nil }
        } else if let notice = model.notice {
            banner(notice, icon: "checkmark.circle.fill", color: .green) { model.notice = nil }
        }
    }

    private func banner(_ text: String, icon: String, color: Color, dismiss: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon).foregroundStyle(color)
            Text(text).font(.caption).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: dismiss) { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .font(.caption)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(color.opacity(0.1)))
    }
}
