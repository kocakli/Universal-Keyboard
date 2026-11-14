import KeyMapperCore
import SwiftUI

/// Main window: keyboards on the left, layout editor on the right ("Graphite Signal" design).
struct EditorWindow: View {
    static let id = "editor"
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 0) {
            Sidebar()
                .frame(width: 264)
            Rectangle().fill(Theme.line).frame(width: 1)
            Group {
                if model.showingActions {
                    ActionsView()
                } else if let device = model.selectedDevice {
                    DeviceDetail(device: device).id(device.id)
                } else {
                    EmptyDetail()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.ground)
        .foregroundStyle(Theme.text)
        .environment(\.locale, model.language.locale)
        .id(model.language)
        .frame(minWidth: 1040, minHeight: 720)
        .overlay(alignment: .bottom) { StatusBanner().padding(18) }
        .sheet(item: $model.unlock) { _ in UnlockSheet() }
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
        .onDisappear { NSApp.setActivationPolicy(.accessory) }
    }
}

// MARK: - Sidebar

private struct Sidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                AppMark()
                VStack(alignment: .leading, spacing: 1) {
                    Text("KeyMapper").font(.system(size: 14, weight: .semibold))
                    Text(L("Evrensel klavye eşleyici")).font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                }
            }
            .padding(.horizontal, 6)

            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(text: L("Bağlı klavyeler · %@", "\(model.devices.count)")).padding(.horizontal, 8)
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(model.devices) { device in
                            DeviceCard(device: device, isSelected: !model.showingActions && model.selectedDeviceID == device.id) {
                                model.selectedDeviceID = device.id
                                model.showingActions = false
                            }
                        }
                        if model.devices.isEmpty {
                            Text(L("Bağlı klavye yok. Bluetooth klavyeyi bir tuşa basarak uyandırın."))
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textSecondary)
                                .padding(12)
                        }
                    }
                }
                .scrollIndicators(.never)
            }

            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(text: L("Otomasyon")).padding(.horizontal, 8)
                ActionsNavCard(isSelected: model.showingActions) { model.showingActions = true }
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 10) {
                Text(L("Desteklenenler")).font(.system(size: 12, weight: .semibold))
                Text(L("Vial ve VIA/QMK klavyeler firmware'de, diğer tüm klavyeler macOS seviyesinde düzenlenir."))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle(isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) })) {
                    Text(L("Girişte başlat")).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(Theme.accent)
                LanguageMenu()
                AboutButton()
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.raised))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
        }
        .padding(EdgeInsets(top: 46, leading: 14, bottom: 16, trailing: 14))
        .frame(maxHeight: .infinity, alignment: .top)
        .background(SidebarBackground().ignoresSafeArea())
    }
}

private struct DeviceCard: View {
    @Environment(AppModel.self) private var model
    let device: KeyboardDevice
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    KeyboardSilhouette(keys: model.states[device.id]?.definition.keys ?? [],
                                       color: isSelected ? Theme.accent : Theme.textTertiary)
                        .frame(width: 40, height: 22)
                    Spacer()
                    CapabilityBadge(capability: device.capability)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.displayName).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    HStack(spacing: 8) {
                        Text("\(device.brand.name) · \(device.transportLabel)").font(.system(size: 12)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                        if let battery = model.batteries[device.id] { BatteryBadge(status: battery) }
                    }
                }
                HStack(spacing: 6) {
                    if let profile = model.assignedProfile(for: device) {
                        Circle().fill(Theme.accent).frame(width: 6, height: 6)
                        Text(L("Layout: %@", profile.name)).foregroundStyle(Theme.textSecondary)
                    } else {
                        Text(device.capability == .osRemap ? L("Eşleme yok") : L("Profil atanmadı")).foregroundStyle(Theme.textTertiary)
                    }
                }
                .font(.system(size: 12))
                .lineLimit(1)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(isSelected ? Theme.selectedFill : .clear))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.clear, lineWidth: 0))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct EmptyDetail: View {
    var body: some View {
        VStack(spacing: 14) {
            AppMark(size: 56)
            Text(L("Klavye seçin")).font(.system(size: 20, weight: .semibold))
            Text(L("USB veya Bluetooth ile bağlı bir klavye seçin.")).foregroundStyle(Theme.textSecondary)
        }
    }
}

// MARK: - Detail

struct DeviceDetail: View {
    @Environment(AppModel.self) private var model
    let device: KeyboardDevice

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if device.capability == .osRemap || model.states[device.id] != nil {
                    HStack {
                        Text(model.selectedApp[device.id].map { L("%@ için atamalar", "\($0.name)") } ?? L("Tüm uygulamalar"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                        AppTabBar(device: device)
                    }
                }
                DeviceHeader(device: device)
                if device.capability == .osRemap {
                    RemapEditor(device: device)
                } else {
                    switch model.phase(for: device) {
                    case .idle, .loading:
                        LoadingStage()
                    case let .failed(message):
                        FailureView(device: device, message: message)
                    case .loaded:
                        if let state = model.states[device.id] {
                            FirmwareEditor(device: device, state: state)
                        }
                    }
                }
            }
            .padding(EdgeInsets(top: 30, leading: 28, bottom: 80, trailing: 28))
        }
        .scrollIndicators(.automatic)
        .task {
            await model.ensureLoaded(device)
            await model.refreshFirmware(device)
        }
    }
}

private struct LoadingStage: View {
    var body: some View {
        KeyboardStage {
            VStack(spacing: 12) {
                ProgressView().controlSize(.large).tint(Theme.accent)
                Text(L("Klavye okunuyor…")).foregroundStyle(Theme.textSecondary)
            }
            .frame(height: 300)
        }
    }
}

private struct FailureView: View {
    @Environment(AppModel.self) private var model
    let device: KeyboardDevice
    let message: String

    var body: some View {
        KeyboardStage {
            VStack(spacing: 14) {
                Image(systemName: "exclamationmark.triangle").font(.system(size: 30)).foregroundStyle(Theme.accent)
                Text(L("Klavye okunamadı")).font(.system(size: 17, weight: .semibold))
                Text(message).font(.system(size: 13)).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center).frame(maxWidth: 460)
                HStack {
                    Button(L("Tekrar dene")) { Task { await model.ensureLoaded(device, force: true) } }
                        .buttonStyle(PrimaryButtonStyle())
                    if device.capability == .via {
                        Button(L("VIA tanım dosyası yükle…")) { model.importDefinition(for: device) }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                }
            }
            .frame(minHeight: 300)
        }
    }
}

private struct DeviceHeader: View {
    @Environment(AppModel.self) private var model
    let device: KeyboardDevice
    @State private var savingName: String?

    var body: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                // Product names are Latin: uppercase them without Turkish dotted-İ rules.
                Text(device.displayName).font(.title.weight(.semibold)).lineLimit(1)
                HStack(spacing: 12) {
                    Text(device.capability.title)
                    Text(device.transportLabel)
                    Text(device.deviceKey).monospacedDigit()
                    if let battery = model.batteries[device.id] { BatteryBadge(status: battery) }
                }
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                HStack(spacing: 6) {
                    ForEach(chips, id: \.self) { Chip(text: $0) }
                    FirmwareChip(device: device)
                    if let activity = model.activity[device.id] {
                        ProgressView().controlSize(.small).tint(Theme.accent)
                        Text(activity).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                    }
                }
                .padding(.top, 4)
            }
            Spacer(minLength: 12)
            HStack(spacing: 8) {
                profileMenu
                if device.capability != .osRemap {
                    Button {
                        Task { await model.ensureLoaded(device, force: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise").font(.system(size: 13, weight: .semibold))
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .help(L("Klavyeden yeniden oku"))
                    .accessibilityLabel(L("Klavyeden yeniden oku"))
                }
                Button(L("Profil olarak kaydet")) { savingName = L("Profil %@", "\(model.profiles(for: device).count + 1)") }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!isLoaded)
            }
        }
        .alert(L("Layout'u profil olarak kaydet"), isPresented: Binding(get: { savingName != nil }, set: { if !$0 { savingName = nil } })) {
            TextField(L("Profil adı"), text: Binding(get: { savingName ?? "" }, set: { savingName = $0 }))
            Button(L("Kaydet")) {
                let name = (savingName ?? "").trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { model.saveCurrentLayout(of: device, name: name) }
                savingName = nil
            }
            Button(L("Vazgeç"), role: .cancel) { savingName = nil }
        } message: {
            Text(L("Klavyedeki mevcut düzen kaydedilir; daha sonra menü çubuğundan tek tıkla geri yükleyebilirsiniz."))
        }
    }

    private var isLoaded: Bool { device.capability == .osRemap || model.states[device.id] != nil }

    private var chips: [String] {
        if device.capability == .osRemap {
            let count = model.currentRemaps(device).count
            return [L("macOS eşlemesi"), count == 0 ? L("Eşleme yok") : L("%@ eşleme", "\(count)"), device.brand.name]
        }
        guard let state = model.states[device.id] else { return [device.brand.name] }
        var list = [L("%@ katman", "\(state.layerCount)"), L("%@×%@ matris", "\(state.definition.rows)", "\(state.definition.cols)")]
        if state.definition.encoderCount > 0 { list.append(L("%@ encoder", "\(state.definition.encoderCount)")) }
        list.append(L("Tanım: %@", "\(state.definition.source.title.lowercased(with: L10n.current.locale))"))
        if let active = state.keychron?.baseLayer { list.append(L("Etkin katman %@", "\(active)")) }
        return list
    }

    private var profileMenu: some View {
        let profiles = model.profiles(for: device)
        return Menu {
            Section(L("Profil uygula")) {
                if profiles.isEmpty { Text(L("Kayıtlı profil yok")) }
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
            }
            Divider()
            Button(L("Dosyadan içe aktar (.vil / VIA .json)…")) { model.importLayoutFile(for: device) }
            if device.capability != .osRemap {
                Menu(L("Dışa aktar")) {
                    Button(L("Vial (.vil)")) { model.export(device, format: .vial) }
                    Button(L("VIA (.json)")) { model.export(device, format: .via) }
                    Button(L("KeyMapper profili (.json)")) { model.export(device, format: .profile) }
                }
                .disabled(!isLoaded)
            }
            if device.capability == .via {
                Button(L("VIA tanım dosyası yükle…")) { model.importDefinition(for: device) }
            }
            if !profiles.isEmpty {
                Menu(L("Profil sil")) {
                    ForEach(profiles) { profile in
                        Button(profile.name, role: .destructive) { model.delete(profile) }
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(L("Profil")).foregroundStyle(Theme.textTertiary)
                Text(model.assignedProfile(for: device)?.name ?? L("Seç")).fontWeight(.semibold)
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.textSecondary)
            }
            .font(.system(size: 13))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.control))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

// MARK: - Firmware editor

/// VIA / Vial keymap editor.
private struct FirmwareEditor: View {
    @Environment(AppModel.self) private var model
    let device: KeyboardDevice
    let state: KeyboardState

    @State private var layer = 0
    @State private var selection: KeySlot?
    @State private var expression = ""
    @State private var alphaTarget = AlphaLayout.colemakDH
    /// Explanation of the hold chip under the pointer.
    @State private var hoveredHold: String?
    /// Action being assigned to (or edited on) the selected key.
    @State private var actionTarget: ActionsView.EditTarget?

    var body: some View {
        let keys = state.definition.visibleKeys(options: state.layoutOptions).filter { !$0.isEncoder }
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                layerPills
                if let base = baseLayer, base != layer { baseLayerHint(base) }
                Spacer(minLength: 12)
                if app == nil { alphaControls }
            }

            KeyboardStage {
                KeyboardCanvas(keys: keys, selected: selection, cap: cap(for:)) { key in select(key.slot) }
                    .frame(minHeight: 220)
                if state.definition.encoderCount > 0 { encoderRow }
            }

            if let app {
                AppKeyPanel(device: device, app: app, layer: layer, slot: selection, code: currentCode, keycodes: state.keycodes)
            } else {
                HStack(alignment: .top, spacing: 18) {
                    inspector.frame(width: 360)
                    Panel {
                        KeycodePicker(keycodes: state.keycodes, layerCount: state.layerCount, categories: PickerCategory.allCases,
                                      annotations: model.actionNamesByUsage, details: model.actionDetailsByUsage,
                                      onCreateAction: startAction) { assign($0) }
                            // Stays hoverable without a selection so descriptions can be read first.
                            .opacity(selection == nil ? 0.6 : 1)
                    }
                    .frame(height: 380)
                }
            }
        }
        .onChange(of: layer) { _, _ in expression = currentCode.map { state.keycodes.name(for: $0) } ?? "" }
        // Keychron: start on the layer the keyboard is typing on, so edits take effect right away.
        .onAppear { if let base = baseLayer { layer = base } }
        .sheet(item: $actionTarget) { target in
            ActionEditorSheet(target: target) { action in
                actionTarget = nil
                guard let slot = selection else { return }
                Task { await model.assignKeyAction(action, device: device, layer: layer, slot: slot) }
            } cancel: {
                actionTarget = nil
            }
        }
    }

    private var app: AppChoice? { model.selectedApp[device.id] }

    /// Layer a Keychron keyboard types on without holding a layer key (reported by the firmware).
    private var baseLayer: Int? {
        guard let base = state.keychron?.baseLayer, base < state.layerCount else { return nil }
        return base
    }

    // MARK: Pieces

    private var layerPills: some View {
        HStack(spacing: 4) {
            ForEach(0..<state.layerCount, id: \.self) { index in
                Button("\(index)") { layer = index }
                    .buttonStyle(PillButtonStyle(isOn: layer == index, style: .plain))
                    .overlay(alignment: .bottom) {
                        if index == baseLayer {
                            Circle().fill(Color.accentColor).frame(width: 4, height: 4).offset(y: -2)
                        }
                    }
                    .help(index == baseLayer ? L("Klavye şu an bu katmanla yazıyor.") : "")
                    .accessibilityLabel(index == baseLayer ? L("Katman %@, etkin", "\(index)") : L("Katman %@", "\(index)"))
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
    }

    private func baseLayerHint(_ base: Int) -> some View {
        Button {
            layer = base
        } label: {
            Label(L("Klavye şu an %@. katmanda", "\(base)"), systemImage: "exclamationmark.circle")
                .font(.system(size: 12))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.textSecondary)
        .help(L("Bu katmanda yaptığınız atamalar ancak bu katmana geçildiğinde çalışır. Tıklayınca etkin katmana geçilir."))
    }

    private var alphaControls: some View {
        let current = model.alphaLayout(device: device, layer: layer)
        let source = Binding(get: { current }, set: { model.setAlphaLayout($0, device: device, layer: layer) })
        return HStack(spacing: 8) {
            Text(L("Alfabe")).font(.system(size: 13)).foregroundStyle(Theme.textTertiary)
            layoutMenu(selection: source)
                .help(L("Bu katmanın şu anki harf düzeni. KeyMapper her dönüşümden sonra bunu günceller; düzeni başka bir araçla değiştirdiyseniz buradan düzeltin."))
            Image(systemName: "arrow.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.textTertiary)
            layoutMenu(selection: $alphaTarget)
            Button(L("%@. katmana uygula", "\(layer)")) {
                Task { await model.convertAlpha(device: device, layer: layer, to: alphaTarget) }
            }
            .buttonStyle(SecondaryButtonStyle(height: 32, emphasized: true))
            .disabled(current == alphaTarget)
            .help(L("Harf tuşlarını seçilen düzene çevirir; home-row mod ve layer-tap gibi basılı tutma işlevleri korunur."))
            if model.alphaUndo[device.id]?.layer == layer {
                Button(L("Geri al")) { Task { await model.undoAlpha(device: device) } }
                    .buttonStyle(SecondaryButtonStyle(height: 32))
                    .help(L("Katmanı son dönüşümden önceki haline döndürür."))
            }
        }
    }

    private func layoutMenu(selection: Binding<AlphaLayout>) -> some View {
        Menu {
            ForEach(AlphaLayout.all) { layout in
                Button(layout.name) { selection.wrappedValue = layout }
            }
        } label: {
            Text(selection.wrappedValue.name)
                .font(.system(size: 13))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.raised))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    /// Knob rotations: each direction gets its own function; pressing the knob is a normal key on the board.
    private var encoderRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(L("Döner düğmeler")).font(Theme.label).foregroundStyle(Theme.textSecondary)
                Text(L("Çevirme yönlerine ayrı işlev atanır; düğmeye basmak klavyede ayrı bir tuştur."))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
            }
            FlowLayout(spacing: 10) {
                ForEach(0..<state.definition.encoderCount, id: \.self) { index in
                    HStack(spacing: 8) {
                        KnobIcon()
                        Text(L("Düğme %@", "\(index + 1)")).font(.system(size: 12, weight: .medium))
                        ForEach([false, true], id: \.self) { clockwise in
                            let slot = KeySlot.encoder(index: index, clockwise: clockwise)
                            let code = state.keymap.keycode(layer: layer, slot: slot) ?? 0
                            let legend = app.map { model.appCap(code: code, app: $0, keycodes: state.keycodes).label.main }
                                ?? state.keycodes.title(for: code)
                            Button("\(clockwise ? "↻" : "↺") \(legend)") { select(slot) }
                                .buttonStyle(PillButtonStyle(isOn: selection == slot, height: 26))
                                .help(clockwise ? L("Sağa çevir") : L("Sola çevir"))
                        }
                        if app == nil { knobPresetMenu(index) }
                    }
                    .padding(EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 8))
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.surface))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
                }
            }
        }
    }

    private func knobPresetMenu(_ index: Int) -> some View {
        Menu {
            ForEach(KnobPreset.all, id: \.title) { preset in
                Button(L(preset.title)) { applyKnobPreset(preset, index: index) }
            }
        } label: {
            HStack(spacing: 4) {
                Text(L("Hazır ayar"))
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }
            .font(.system(size: 12))
            .foregroundStyle(Theme.accent)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(L("İki yönü birden ayarla"))
    }

    private func applyKnobPreset(_ preset: KnobPreset, index: Int) {
        guard let ccw = state.keycodes.parse(preset.ccw), let cw = state.keycodes.parse(preset.cw) else { return }
        Task {
            await model.assign(ccw, device: device, layer: layer, slot: .encoder(index: index, clockwise: false))
            await model.assign(cw, device: device, layer: layer, slot: .encoder(index: index, clockwise: true))
            if model.errorMessage == nil { model.notice = L("Düğme %@: %@", "\(index + 1)", L(preset.title)) }
        }
    }

    private var inspector: some View {
        Panel {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    Keycap(kind: currentCode.map { CapKind.of($0, keycodes: state.keycodes) } ?? .empty,
                           isSelected: selection != nil, radius: 16, depth: 10) {
                        if let code = currentCode {
                            KeyLegend(label: state.keycodes.label(for: code).withPlaceholder(code: code), unit: 88,
                                      kind: CapKind.of(code, keycodes: state.keycodes), subColor: subColor(for: code))
                        }
                    }
                    .frame(width: 84, height: 84)
                    VStack(alignment: .leading, spacing: 3) {
                        if let selection, let code = currentCode {
                            Eyebrow(text: L("Seçili tuş · %@", "\(describe(selection))"))
                            if let binding = model.binding(forUsage: code) {
                                Text(binding.defaultAction?.summary ?? binding.name).font(.system(size: 17, weight: .semibold)).lineLimit(2)
                                Button(L("Aksiyonu düzenle"), action: editAction)
                                    .buttonStyle(SecondaryButtonStyle(height: 26))
                            } else {
                                Text(state.keycodes.title(for: code)).font(.system(size: 17, weight: .semibold)).lineLimit(2)
                                Text(state.keycodes.name(for: code)).font(Theme.mono(12)).foregroundStyle(Theme.textTertiary).textSelection(.enabled)
                            }
                        } else {
                            Eyebrow(text: L("Seçili tuş"))
                            Text(L("Klavyeden bir tuş seçin")).font(.system(size: 17, weight: .semibold))
                            Text(L("Sonra paletten yeni işlevini seçin.")).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                        }
                    }
                }

                if let code = currentCode {
                    Text(model.actionDetailsByUsage[code] ?? state.keycodes.explanation(for: code))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(hoveredHold ?? L("Basılı tutunca"))
                        .font(.system(size: 12))
                        .foregroundStyle(hoveredHold == nil ? Theme.textSecondary : Theme.accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    holdChips
                }

                HStack(spacing: 8) {
                    TextField("LT(1, KC_SPC)", text: $expression)
                        .textFieldStyle(.plain)
                        .font(Theme.mono(13))
                        .foregroundStyle(state.keycodes.parse(expression) == nil && !expression.isEmpty ? Theme.error : Theme.text)
                        .padding(.horizontal, 12)
                        .frame(height: 36)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.ground))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
                        .onSubmit(assignExpression)
                        .accessibilityLabel(L("Keycode ifadesi"))
                    Button(L("Ata"), action: assignExpression)
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(selection == nil || state.keycodes.parse(expression) == nil)
                }
            }
        }
        .frame(height: 380, alignment: .top)
    }

    /// Hold actions (mod-tap / layer-tap) wrapping the selected key's tap keycode.
    private var holdChips: some View {
        let code = currentCode ?? 0
        let decoded = state.keycodes.decode(code)
        let tap: UInt16? = {
            switch decoded {
            case let .modTap(_, kc), let .layerTap(_, kc): return kc
            case let .named(c) where c <= 0xFF: return c
            case let .raw(c) where c <= 0xFF: return c
            default: return nil
            }
        }()
        // (chip legend, hover explanation, keycode to assign, is current)
        var options: [(String, String, UInt16?, Bool)] = []
        if let tap {
            let plain: Bool = { if case .named = decoded { return true }; if case .raw = decoded { return true }; return false }()
            options.append((L("Yok"), L("Basılı tutma işlevi yok; tuş yalnızca dokununca çalışır."), tap, plain))
            for (mods, symbol) in [(UInt8(0x01), "⌃"), (0x02, "⇧"), (0x04, "⌥"), (0x08, "⌘"), (0x07, "Meh"), (0x0F, "Hyper")] {
                let isOn: Bool = { if case let .modTap(m, _) = decoded { return m == mods }; return false }()
                let value = state.keycodes.encode(.modTap(mods, tap))
                options.append((symbol, value.map { state.keycodes.explanation(for: $0) } ?? symbol, value, isOn))
            }
            for target in 1..<min(max(state.layerCount, 2), 5) {
                let isOn: Bool = { if case let .layerTap(l, _) = decoded { return l == target }; return false }()
                let value = state.keycodes.encode(.layerTap(target, tap))
                options.append(("L\(target)", value.map { state.keycodes.explanation(for: $0) } ?? L("Katman %@", "\(target)"), value, isOn))
            }
        }
        return FlowLayout(spacing: 6) {
            if options.isEmpty {
                Text(selection == nil ? "—" : L("Bu tuşa basılı tutma işlevi eklenemez"))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
            }
            ForEach(options, id: \.0) { option in
                Button(option.0) { if let value = option.2 { assign(value) } }
                    .buttonStyle(PillButtonStyle(isOn: option.3, height: 32))
                    .onHover { inside in
                        if inside { hoveredHold = option.1 } else if hoveredHold == option.1 { hoveredHold = nil }
                    }
                    .help(option.1)
                    .accessibilityLabel(option.1)
            }
        }
    }

    // MARK: Behaviour

    private var currentCode: UInt16? {
        selection.flatMap { state.keymap.keycode(layer: layer, slot: $0) }
    }

    private func select(_ slot: KeySlot) {
        selection = slot
        expression = currentCode.map { state.keycodes.name(for: $0) } ?? ""
    }

    private func describe(_ slot: KeySlot) -> String {
        switch slot {
        case let .matrix(row, col): return L("K%@ · R%@ C%@", "\(layer)", "\(row)", "\(col)")
        case let .encoder(index, clockwise): return L("K%@ · Encoder %@ %@", "\(layer)", "\(index)", "\(clockwise ? "↻" : "↺")")
        }
    }

    private func assignExpression() {
        guard let code = state.keycodes.parse(expression) else { return }
        assign(code)
    }

    private func assign(_ code: UInt16) {
        guard let selection else { return }
        expression = state.keycodes.name(for: code)
        Task { await model.assign(code, device: device, layer: layer, slot: selection) }
    }

    private func subColor(for code: UInt16) -> Color {
        if case .layerTap = state.keycodes.decode(code) { return Theme.layerText }
        return Theme.accent
    }

    /// Opens the action editor for the selected key (palette "Uygulama ve aksiyon" buttons).
    private func startAction(_ kind: KeyAction.Kind) {
        guard selection != nil else {
            model.errorMessage = L("Klavyeden bir tuş seçin")
            return
        }
        if let code = currentCode, let binding = model.binding(forUsage: code) {
            actionTarget = .init(bindingID: binding.id, app: nil, initial: nil, kind: kind, title: L("Tuşa aksiyon ata"))
        } else {
            actionTarget = .init(bindingID: nil, app: nil, initial: nil, kind: kind, title: L("Tuşa aksiyon ata"))
        }
    }

    private func editAction() {
        guard let code = currentCode, let binding = model.binding(forUsage: code) else { return }
        actionTarget = .init(bindingID: binding.id, app: nil, initial: binding.defaultAction, title: L("Aksiyonu düzenle"))
    }

    private func cap(for key: LayoutKey) -> KeyCapModel {
        guard let code = state.keymap.keycode(layer: layer, slot: key.slot) else {
            return KeyCapModel(label: KeyLabel(main: ""), kind: .empty)
        }
        if let app { return model.appCap(code: code, app: app, keycodes: state.keycodes) }
        if let actionCap = model.actionCap(code: code) { return actionCap }
        var label = state.keycodes.label(for: code)
        if let action = model.actionNamesByUsage[code] { label.sub = action }
        return KeyCapModel(
            label: label,
            kind: CapKind.of(code, keycodes: state.keycodes),
            subColor: subColor(for: code),
            tooltip: "\(state.keycodes.title(for: code))\n\(model.actionDetailsByUsage[code] ?? state.keycodes.explanation(for: code))"
        )
    }
}

struct KnobIcon: View {
    var body: some View {
        ZStack(alignment: .top) {
            Circle().fill(Theme.raised).overlay(Circle().strokeBorder(Theme.line, lineWidth: 1.5))
            Capsule().fill(Theme.accent).frame(width: 2, height: 5).padding(.top, 3)
        }
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
    }
}

/// Left-to-right wrapping layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(maxX, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Vial unlock

/// Vial unlock: the user holds the unlock keys while we poll the keyboard.
private struct UnlockSheet: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "lock.open").font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.accent)
                Text(L("Vial kilidini aç")).font(.system(size: 18, weight: .semibold))
            }
            Text(L("QK_BOOT gibi korumalı tuşları atamak için klavyenin kilidinin açılması gerekiyor. Başlat'a basın ve aşağıdaki tuşları sayaç bitene kadar basılı tutun."))
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let flow = model.unlock {
                HStack(spacing: 6) {
                    ForEach(Array(flow.keys.enumerated()), id: \.offset) { _, key in
                        Chip(text: "R\(key.row) C\(key.col)", foreground: Theme.accent, background: Theme.accentTint, border: Theme.accent,
                             font: Theme.mono(12))
                    }
                }
                if let counter = flow.counter {
                    ProgressView(value: max(0, 50 - Double(counter)), total: 50) {
                        Text(L("Basılı tutun… %@", "\(counter)")).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                    }
                    .tint(Theme.accent)
                }
                HStack {
                    Spacer()
                    Button(L("Vazgeç")) { model.unlock = nil }
                        .buttonStyle(SecondaryButtonStyle())
                        .keyboardShortcut(.cancelAction)
                    Button(L("Başlat")) { Task { await model.runUnlock() } }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(flow.running)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(22)
        .frame(width: 440)
        .foregroundStyle(Theme.text)
    }
}
