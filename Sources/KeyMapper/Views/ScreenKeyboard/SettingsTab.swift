import KeyMapperCore
import SwiftUI

/// Settings the keyboard keeps itself (command 0x17). Only the LED screen brightness was seen working so far.
struct SettingsTab: View {
    @Environment(AppModel.self) private var model
    let device: KeyboardDevice

    var body: some View {
        let prefs = model.preferences(for: device)
        let settings = prefs.settings
        VStack(alignment: .leading, spacing: 14) {
            TabHeader(title: L("Klavye ayarları"), detail: L("Klavyede saklanır; başka bir bilgisayarda da geçerlidir."))
            AdaptiveColumns(minimum: 300) {
                ScreenCard(title: L("Ekran")) {
                    labelled(L("LED ekran parlaklığı"), tested: true)
                    StepPicker(value: binding(\.screenBrightness), range: 1...7, label: L("LED ekran parlaklığı"))
                    Rectangle().fill(Theme.line).frame(height: 1)
                    labelled(L("Uyku"), tested: false)
                    Segmented(label: L("Uyku"), selection: binding(\.sleep), options: [
                        (UInt8(0), L("Hiçbir zaman")), (UInt8(1), L("%@ dakika", "1")),
                        (UInt8(2), L("%@ dakika", "5")), (UInt8(3), L("%@ dakika", "30")),
                    ], maxWidth: 380)
                }
                ScreenCard(title: L("Tuşlar")) {
                    switchRow(L("Fn tuşu basılı tutmak yerine aç/kapa çalışsın"), isOn: binding(\.fnToggle))
                    Rectangle().fill(Theme.line).frame(height: 1)
                    switchRow(L("Oyun modu"), isOn: binding(\.gameMode))
                    if settings.gameMode {
                        VStack(alignment: .leading, spacing: 8) {
                            SwitchRow(label: L("Alt+Tab'ı engelle"), isOn: binding(\.blockAltTab))
                            SwitchRow(label: L("Alt+F4'ü engelle"), isOn: binding(\.blockAltF4))
                            SwitchRow(label: L("Windows tuşunu engelle"), isOn: binding(\.blockWindowsKey))
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.control))
                    }
                    Text(L("Mac'te Windows tuşu ⌘, Alt tuşu ⌥ olarak çalışır."))
                        .font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                }
            }
            ApplyRow(pending: prefs.appliedSettings != settings,
                     note: L("LED ekran parlaklığı doğrulandı; uyku, Fn ve oyun modunun bu klavyedeki etkisi henüz doğrulanmadı."),
                     disabled: model.isScreenBusy(device)) {
                Task { await model.applyScreenSettings(device) }
            }
            Text(L("Klavye bir komutu reddederse KeyMapper bu klavyeye yazmayı durdurur; kablo çıkarılıp takılınca yeniden başlar. 2.4 GHz alıcıyla yalnızca ışıklar ve tuş atamaları gönderilebilir."))
                .font(.system(size: 11)).foregroundStyle(Theme.textTertiary).fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 13))
    }

    private func labelled(_ text: String, tested: Bool) -> some View {
        HStack {
            Text(text)
            Spacer()
            TestedTag(tested: tested)
        }
    }

    private func switchRow(_ text: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            Text(text).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            TestedTag(tested: false)
            Toggle(text, isOn: isOn).toggleStyle(.switch).controlSize(.small).labelsHidden()
        }
    }

    private func binding<T>(_ path: WritableKeyPath<AMG65DeviceSettings, T>) -> Binding<T> {
        Binding(
            get: { model.preferences(for: device).settings[keyPath: path] },
            set: { value in model.updatePreferences(for: device) { $0.settings[keyPath: path] = value } }
        )
    }
}
