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
            Rectangle().fill(Color(hex: 0x1F2127)).frame(width: 1)
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
        .preferredColorScheme(.dark)
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
                    Text("KeyMapper").font(.system(size: 15, weight: .bold)).tracking(-0.2)
                    Text("Evrensel klavye eşleyici").font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                }
            }
            .padding(.horizontal, 6)

            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(text: "Bağlı klavyeler · \(model.devices.count)").padding(.horizontal, 8)
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(model.devices) { device in
                            DeviceCard(device: device, isSelected: !model.showingActions && model.selectedDeviceID == device.id) {
                                model.selectedDeviceID = device.id
                                model.showingActions = false
                            }
                        }
                        if model.devices.isEmpty {
                            Text("Bağlı klavye yok. Bluetooth klavyeyi bir tuşa basarak uyandırın.")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textSecondary)
                                .padding(12)
                        }
                    }
                }
                .scrollIndicators(.never)
            }

            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(text: "Otomasyon").padding(.horizontal, 8)
                ActionsNavCard(isSelected: model.showingActions) { model.showingActions = true }
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 10) {
                Text("Desteklenenler").font(.system(size: 12, weight: .semibold))
                Text("Vial ve VIA/QMK klavyeler firmware'de, diğer tüm klavyeler macOS seviyesinde düzenlenir.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle(isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) })) {
                    Text("Girişte başlat").font(.system(size: 12)).foregroundStyle(Theme.textMuted)
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(Theme.signal)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(hex: 0x17191D)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.lineSoft, lineWidth: 1))
        }
        .padding(EdgeInsets(top: 46, leading: 14, bottom: 16, trailing: 14))
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.sidebar)
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
                                       color: isSelected ? Theme.signal : Color(hex: 0x5B5F6B))
                        .frame(width: 40, height: 22)
                    Spacer()
                    CapabilityBadge(capability: device.capability)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.displayName).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    Text("\(device.brand.name) · \(device.transportLabel)").font(.system(size: 12)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                }
                HStack(spacing: 6) {
                    if let profile = model.assignedProfile(for: device) {
                        Circle().fill(Theme.signal).frame(width: 6, height: 6)
                        Text("Layout: \(profile.name)").foregroundStyle(Theme.textMuted)
                    } else {
                        Text(device.capability == .osRemap ? "Eşleme yok" : "Profil atanmadı").foregroundStyle(Theme.textTertiary)
                    }
                }
                .font(.system(size: 12))
                .lineLimit(1)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(isSelected ? Theme.raised : .clear))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(isSelected ? Color(hex: 0x30343D) : .clear, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct EmptyDetail: View {
    var body: some View {
        VStack(spacing: 14) {
            AppMark(size: 56)
            Text("Klavye seçin").font(.system(size: 20, weight: .semibold))
            Text("USB veya Bluetooth ile bağlı bir klavye seçin.").foregroundStyle(Theme.textSecondary)
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
                        Text(model.selectedApp[device.id].map { "\($0.name) için atamalar" } ?? "Tüm uygulamalar")
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
                ProgressView().controlSize(.large).tint(Theme.signal)
                Text("Klavye okunuyor…").foregroundStyle(Theme.textSecondary)
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
                Image(systemName: "exclamationmark.triangle").font(.system(size: 30)).foregroundStyle(Theme.signal)
                Text("Klavye okunamadı").font(.system(size: 17, weight: .semibold))
                Text(message).font(.system(size: 13)).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center).frame(maxWidth: 460)
                HStack {
                    Button("Tekrar dene") { Task { await model.ensureLoaded(device, force: true) } }
                        .buttonStyle(PrimaryButtonStyle())
                    if device.capability == .via {
                        Button("VIA tanım dosyası yükle…") { model.importDefinition(for: device) }
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
                Eyebrow(text: "\(device.capability.title) · \(device.transportLabel) · \(device.deviceKey)".uppercased(), color: Theme.signal)
                Text(device.displayName).font(.system(size: 30, weight: .bold)).tracking(-0.6).lineLimit(1)
                HStack(spacing: 6) {
                    ForEach(chips, id: \.self) { Chip(text: $0) }
                    FirmwareChip(device: device)
                    if let activity = model.activity[device.id] {
                        ProgressView().controlSize(.small).tint(Theme.signal)
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
                    .help("Klavyeden yeniden oku")
                    .accessibilityLabel("Klavyeden yeniden oku")
                }
                Button("Profil olarak kaydet") { savingName = "Profil \(model.profiles(for: device).count + 1)" }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!isLoaded)
            }
        }
        .alert("Layout'u profil olarak kaydet", isPresented: Binding(get: { savingName != nil }, set: { if !$0 { savingName = nil } })) {
            TextField("Profil adı", text: Binding(get: { savingName ?? "" }, set: { savingName = $0 }))
            Button("Kaydet") {
                let name = (savingName ?? "").trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { model.saveCurrentLayout(of: device, name: name) }
                savingName = nil
            }
            Button("Vazgeç", role: .cancel) { savingName = nil }
        } message: {
            Text("Klavyedeki mevcut düzen kaydedilir; daha sonra menü çubuğundan tek tıkla geri yükleyebilirsiniz.")
        }
    }

    private var isLoaded: Bool { device.capability == .osRemap || model.states[device.id] != nil }

    private var chips: [String] {
        if device.capability == .osRemap {
            let count = model.currentRemaps(device).count
            return ["macOS eşlemesi", count == 0 ? "Eşleme yok" : "\(count) eşleme", device.brand.name]
        }
        guard let state = model.states[device.id] else { return [device.brand.name] }
        var list = ["\(state.layerCount) katman", "\(state.definition.rows)×\(state.definition.cols) matris"]
        if state.definition.encoderCount > 0 { list.append("\(state.definition.encoderCount) encoder") }
        list.append("Tanım: \(state.definition.source.title.lowercased(with: Locale(identifier: "tr_TR")))")
        return list
    }

    private var profileMenu: some View {
        let profiles = model.profiles(for: device)
        return Menu {
            Section("Profil uygula") {
                if profiles.isEmpty { Text("Kayıtlı profil yok") }
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
            Button("Dosyadan içe aktar (.vil / VIA .json)…") { model.importLayoutFile(for: device) }
            if device.capability != .osRemap {
                Menu("Dışa aktar") {
                    Button("Vial (.vil)") { model.export(device, format: .vial) }
                    Button("VIA (.json)") { model.export(device, format: .via) }
                    Button("KeyMapper profili (.json)") { model.export(device, format: .profile) }
                }
                .disabled(!isLoaded)
            }
            if device.capability == .via {
                Button("VIA tanım dosyası yükle…") { model.importDefinition(for: device) }
            }
            if !profiles.isEmpty {
                Menu("Profil sil") {
                    ForEach(profiles) { profile in
                        Button(profile.name, role: .destructive) { model.delete(profile) }
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text("Profil").foregroundStyle(Theme.textTertiary)
                Text(model.assignedProfile(for: device)?.name ?? "Seç").fontWeight(.semibold)
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
    @State private var alphaSource = AlphaLayout.qwerty
    @State private var alphaTarget = AlphaLayout.colemakDH
    /// Explanation of the hold chip under the pointer.
    @State private var hoveredHold: String?

    var body: some View {
        let keys = state.definition.visibleKeys(options: state.layoutOptions).filter { !$0.isEncoder }
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                layerPills
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
                                      annotations: model.actionNamesByUsage, details: model.actionDetailsByUsage) { assign($0) }
                            // Stays hoverable without a selection so descriptions can be read first.
                            .opacity(selection == nil ? 0.6 : 1)
                    }
                    .frame(height: 380)
                }
            }
        }
        .onChange(of: layer) { _, _ in expression = currentCode.map { state.keycodes.name(for: $0) } ?? "" }
    }

    private var app: AppChoice? { model.selectedApp[device.id] }

    // MARK: Pieces

    private var layerPills: some View {
        HStack(spacing: 4) {
            ForEach(0..<state.layerCount, id: \.self) { index in
                Button("\(index)") { layer = index }
                    .buttonStyle(PillButtonStyle(isOn: layer == index, style: .plain))
                    .accessibilityLabel("Katman \(index)")
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.lineSoft, lineWidth: 1))
    }

    private var alphaControls: some View {
        HStack(spacing: 8) {
            Text("Alfabe").font(.system(size: 13)).foregroundStyle(Theme.textTertiary)
            layoutMenu(selection: $alphaSource)
            Image(systemName: "arrow.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.textTertiary)
            layoutMenu(selection: $alphaTarget)
            Button("Katman \(layer)'a uygula") {
                Task { await model.convertAlpha(device: device, layer: layer, from: alphaSource, to: alphaTarget) }
            }
            .buttonStyle(SecondaryButtonStyle(height: 32, emphasized: true))
            .disabled(alphaSource == alphaTarget)
            .help("Harf tuşlarını seçilen düzene çevirir; home-row mod ve layer-tap gibi basılı tutma işlevleri korunur.")
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
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color(hex: 0x17191D)))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color(hex: 0x262930), lineWidth: 1))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var encoderRow: some View {
        HStack(spacing: 10) {
            ForEach(0..<state.definition.encoderCount, id: \.self) { index in
                HStack(spacing: 10) {
                    KnobIcon()
                    Text("Encoder \(index)").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                    ForEach([false, true], id: \.self) { clockwise in
                        let slot = KeySlot.encoder(index: index, clockwise: clockwise)
                        let code = state.keymap.keycode(layer: layer, slot: slot) ?? 0
                        let legend = app.map { model.appCap(code: code, app: $0, keycodes: state.keycodes).label.main } ?? state.keycodes.shortLabel(code)
                        Button("\(clockwise ? "↻" : "↺") \(legend)") { select(slot) }
                            .buttonStyle(PillButtonStyle(isOn: selection == slot, height: 26))
                    }
                }
                .padding(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 8))
                .background(Capsule().fill(Theme.surface))
                .overlay(Capsule().strokeBorder(Color(hex: 0x23262D), lineWidth: 1))
            }
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
                            Eyebrow(text: "Seçili tuş · \(describe(selection))")
                            Text(state.keycodes.title(for: code)).font(.system(size: 17, weight: .semibold)).lineLimit(2)
                            Text(state.keycodes.name(for: code)).font(Theme.mono(12)).foregroundStyle(Theme.textTertiary).textSelection(.enabled)
                        } else {
                            Eyebrow(text: "Seçili tuş")
                            Text("Klavyeden bir tuş seçin").font(.system(size: 17, weight: .semibold))
                            Text("Sonra paletten yeni işlevini seçin.").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
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
                    Text(hoveredHold ?? "Basılı tutunca")
                        .font(.system(size: 12))
                        .foregroundStyle(hoveredHold == nil ? Theme.textSecondary : Theme.signalSoft)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    holdChips
                }

                HStack(spacing: 8) {
                    TextField("LT(1, KC_SPC)", text: $expression)
                        .textFieldStyle(.plain)
                        .font(Theme.mono(13))
                        .foregroundStyle(state.keycodes.parse(expression) == nil && !expression.isEmpty ? Color(hex: 0xFF8E8E) : Theme.text)
                        .padding(.horizontal, 12)
                        .frame(height: 36)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.ground))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
                        .onSubmit(assignExpression)
                        .accessibilityLabel("Keycode ifadesi")
                    Button("Ata", action: assignExpression)
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
            options.append(("Yok", "Basılı tutma işlevi yok; tuş yalnızca dokununca çalışır.", tap, plain))
            for (mods, symbol) in [(UInt8(0x01), "⌃"), (0x02, "⇧"), (0x04, "⌥"), (0x08, "⌘"), (0x07, "Meh"), (0x0F, "Hyper")] {
                let isOn: Bool = { if case let .modTap(m, _) = decoded { return m == mods }; return false }()
                let value = state.keycodes.encode(.modTap(mods, tap))
                options.append((symbol, value.map { state.keycodes.explanation(for: $0) } ?? symbol, value, isOn))
            }
            for target in 1..<min(max(state.layerCount, 2), 5) {
                let isOn: Bool = { if case let .layerTap(l, _) = decoded { return l == target }; return false }()
                let value = state.keycodes.encode(.layerTap(target, tap))
                options.append(("L\(target)", value.map { state.keycodes.explanation(for: $0) } ?? "Katman \(target)", value, isOn))
            }
        }
        return FlowLayout(spacing: 6) {
            if options.isEmpty {
                Text(selection == nil ? "—" : "Bu tuşa basılı tutma işlevi eklenemez")
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
        case let .matrix(row, col): return "K\(layer) · R\(row) C\(col)"
        case let .encoder(index, clockwise): return "K\(layer) · Encoder \(index) \(clockwise ? "↻" : "↺")"
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
        if case .layerTap = state.keycodes.decode(code) { return Theme.cobaltText }
        return Theme.signal
    }

    private func cap(for key: LayoutKey) -> KeyCapModel {
        guard let code = state.keymap.keycode(layer: layer, slot: key.slot) else {
            return KeyCapModel(label: KeyLabel(main: ""), kind: .empty)
        }
        if let app { return model.appCap(code: code, app: app, keycodes: state.keycodes) }
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
            Circle().fill(Theme.raised).overlay(Circle().strokeBorder(Color(hex: 0x3A3E48), lineWidth: 1.5))
            Capsule().fill(Theme.signal).frame(width: 2, height: 5).padding(.top, 3)
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
                Image(systemName: "lock.open").font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.signal)
                Text("Vial kilidini aç").font(.system(size: 18, weight: .semibold))
            }
            Text("QK_BOOT gibi korumalı tuşları atamak için klavyenin kilidinin açılması gerekiyor. Başlat'a basın ve aşağıdaki tuşları sayaç bitene kadar basılı tutun.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let flow = model.unlock {
                HStack(spacing: 6) {
                    ForEach(Array(flow.keys.enumerated()), id: \.offset) { _, key in
                        Chip(text: "R\(key.row) C\(key.col)", foreground: Theme.signalSoft, background: Theme.signalTint, border: Theme.signal,
                             font: Theme.mono(12))
                    }
                }
                if let counter = flow.counter {
                    ProgressView(value: max(0, 50 - Double(counter)), total: 50) {
                        Text("Basılı tutun… \(counter)").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                    }
                    .tint(Theme.signal)
                }
                HStack {
                    Spacer()
                    Button("Vazgeç") { model.unlock = nil }
                        .buttonStyle(SecondaryButtonStyle())
                        .keyboardShortcut(.cancelAction)
                    Button("Başlat") { Task { await model.runUnlock() } }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(flow.running)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(22)
        .frame(width: 440)
        .background(Theme.surface)
        .foregroundStyle(Theme.text)
        .preferredColorScheme(.dark)
    }
}
