import AppKit
import KeyMapperCore
import SwiftUI

extension AppModel {
    /// Reads the installed version (keyboard or USB descriptor) and asks the vendor for the latest one.
    func refreshFirmware(_ device: KeyboardDevice) async {
        guard device.vendorID == KeychronLauncher.vendorID else { return }
        let reported = states[device.id]?.firmwareVersion.map(KeychronLauncher.normalizeVersion)
        let current = reported ?? device.firmwareVersion
        let product = await KeychronLauncher.product(vendorProductID: device.vendorProductID)
        firmware[device.id] = FirmwareStatus(current: current, latest: product?.latest, updatePage: KeychronLauncher.site)
    }
}

/// Header chip: installed firmware, and an update offer with release notes when one exists.
struct FirmwareChip: View {
    @Environment(AppModel.self) private var model
    let device: KeyboardDevice
    @State private var showingNotes = false

    var body: some View {
        if let status = model.firmware[device.id] {
            Button {
                showingNotes = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: status.isUpdateAvailable ? "arrow.down.circle.fill" : "checkmark.seal")
                    Text(title(status))
                }
                .font(.system(size: 12, weight: status.isUpdateAvailable ? .semibold : .regular))
                .foregroundStyle(status.isUpdateAvailable ? Theme.onSignal : Color(hex: 0xB9BBC4))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(status.isUpdateAvailable ? Theme.signal : Color(hex: 0x17191D)))
                .overlay { if !status.isUpdateAvailable { Capsule().strokeBorder(Color(hex: 0x262930), lineWidth: 1) } }
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingNotes, arrowEdge: .bottom) { notes(status) }
            .help("Firmware bilgisi")
        }
    }

    private func title(_ status: FirmwareStatus) -> String {
        if status.isUpdateAvailable, let latest = status.latest { return "Güncelleme var: \(latest.version)" }
        if let current = status.current { return "Firmware \(current)\(status.latest == nil ? "" : " · güncel")" }
        return "Firmware"
    }

    private func notes(_ status: FirmwareStatus) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(text: "Firmware", color: Theme.signal)
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Yüklü").font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                    Text(status.current ?? "bilinmiyor").font(Theme.rounded(17))
                }
                if let latest = status.latest {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("En yeni\(latest.date.map { " · \($0)" } ?? "")").font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                        Text(latest.version).font(Theme.rounded(17)).foregroundStyle(status.isUpdateAvailable ? Theme.signal : Theme.text)
                    }
                }
            }
            if let text = status.latest?.notes {
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(status.isUpdateAvailable
                 ? "Güncelleme Keychron Launcher ile yüklenir (Chrome veya Edge). KeyMapper firmware yazmaz; klavyeniz güvende kalır."
                 : "Klavyeniz en yeni firmware'i kullanıyor.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            if let page = status.updatePage {
                Button(status.isUpdateAvailable ? "Keychron Launcher'da güncelle" : "Keychron Launcher'ı aç") {
                    NSWorkspace.shared.open(page)
                }
                .buttonStyle(PrimaryButtonStyle(height: 32))
            }
        }
        .padding(18)
        .frame(width: 340)
        .background(Theme.surface)
        .foregroundStyle(Theme.text)
        .preferredColorScheme(.dark)
    }
}
