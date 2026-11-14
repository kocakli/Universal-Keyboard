import KeyMapperCore
import SwiftUI

/// Main window: keyboards on the left, layout editor on the right.
struct EditorWindow: View {
    static let id = "editor"
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(selection: $model.selectedDeviceID) {
                Section("Bağlı klavyeler") {
                    ForEach(model.devices) { device in
                        DeviceRow(device: device).tag(device.id)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 250)
            .safeAreaInset(edge: .bottom) { SupportFooter() }
        } detail: {
            if let device = model.selectedDevice {
                DeviceDetail(device: device)
                    .id(device.id)
            } else {
                ContentUnavailableView("Klavye seçin", systemImage: "keyboard",
                                       description: Text("USB veya Bluetooth ile bağlı bir klavye seçin."))
            }
        }
        .sheet(item: $model.unlock) { _ in UnlockSheet() }
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
        .onDisappear { NSApp.setActivationPolicy(.accessory) }
    }
}

private struct DeviceRow: View {
    @Environment(AppModel.self) private var model
    let device: KeyboardDevice

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(device.displayName).lineLimit(1)
                Spacer()
                CapabilityBadge(capability: device.capability)
            }
            Text("\(device.brand.name) · \(device.transportLabel)")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let profile = model.assignedProfile(for: device) {
                Label(profile.name, systemImage: "square.grid.3x3").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct SupportFooter: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Destek").font(.caption.weight(.semibold))
            Text("Vial ve VIA/QMK klavyeler (Keychron, Corne, Cornix, NuPhy, KBDfans, Keebio…) firmware seviyesinde; diğer tüm klavyeler (Logitech, Apple, Razer, Corsair…) macOS seviyesinde düzenlenir.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
    }
}

/// Detail pane for one keyboard.
struct DeviceDetail: View {
    @Environment(AppModel.self) private var model
    let device: KeyboardDevice

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DeviceHeader(device: device)
                .padding([.horizontal, .top], 16)
                .padding(.bottom, 10)
            Divider()
            Group {
                if device.capability == .osRemap {
                    RemapEditor(device: device)
                } else {
                    switch model.phase(for: device) {
                    case .idle, .loading:
                        ProgressView("Klavye okunuyor…").frame(maxWidth: .infinity, maxHeight: .infinity)
                    case let .failed(message):
                        FailureView(device: device, message: message)
                    case .loaded:
                        if let state = model.states[device.id] {
                            FirmwareEditor(device: device, state: state)
                        }
                    }
                }
            }
            .padding(16)
            StatusBanner().padding([.horizontal, .bottom], 12)
        }
        .task { await model.ensureLoaded(device) }
    }
}

private struct FailureView: View {
    @Environment(AppModel.self) private var model
    let device: KeyboardDevice
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label("Klavye okunamadı", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            HStack {
                Button("Tekrar dene") { Task { await model.ensureLoaded(device, force: true) } }
                if device.capability == .via {
                    Button("VIA tanım dosyası yükle…") { model.importDefinition(for: device) }
                }
            }
        }
    }
}

private struct DeviceHeader: View {
    @Environment(AppModel.self) private var model
    let device: KeyboardDevice
    @State private var savingName: String?

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(device.displayName).font(.title2.weight(.semibold))
                    CapabilityBadge(capability: device.capability)
                }
                Text(details).font(.callout).foregroundStyle(.secondary)
                if let activity = model.activity[device.id] {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text(activity).font(.caption)
                    }
                }
            }
            Spacer()
            profileMenu
            if device.capability != .osRemap {
                Button {
                    Task { await model.ensureLoaded(device, force: true) }
                } label: {
                    Label("Yeniden oku", systemImage: "arrow.clockwise")
                }
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

    private var details: String {
        var parts = [device.brand.name, device.transportLabel, device.deviceKey]
        if let state = model.states[device.id] {
            parts.append("VIA v\(state.viaProtocol)")
            if let vial = state.vialProtocol { parts.append("Vial v\(vial)") }
            parts.append("Tanım: \(state.definition.source.title)")
        }
        return parts.joined(separator: " · ")
    }

    private var profileMenu: some View {
        let profiles = model.profiles(for: device)
        let loaded = device.capability == .osRemap || model.states[device.id] != nil
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
            Button("Mevcut düzeni profil olarak kaydet…") { savingName = "Profil \(profiles.count + 1)" }
                .disabled(!loaded)
            Button("Dosyadan içe aktar (.vil / VIA .json)…") { model.importLayoutFile(for: device) }
            if device.capability != .osRemap {
                Menu("Dışa aktar") {
                    Button("Vial (.vil)") { model.export(device, format: .vial) }
                    Button("VIA (.json)") { model.export(device, format: .via) }
                    Button("KeyMapper profili (.json)") { model.export(device, format: .profile) }
                }
                .disabled(!loaded)
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
            Label("Profil", systemImage: "square.grid.3x3")
        }
        .fixedSize()
    }
}

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

    var body: some View {
        let keys = state.definition.visibleKeys(options: state.layoutOptions)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("Katman", selection: $layer) {
                    ForEach(0..<state.layerCount, id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: CGFloat(state.layerCount) * 44)
                Spacer()
                alphaControls
            }

            KeyboardCanvas(keys: keys, selected: selection, cap: cap(for:)) { key in
                selection = key.slot
                expression = currentCode.map { state.keycodes.name(for: $0) } ?? ""
            }
            .frame(minHeight: 160)

            if !knobs.isEmpty { knobRow }

            selectionBar

            KeycodePicker(keycodes: state.keycodes, layerCount: state.layerCount, categories: PickerCategory.allCases) { code in
                assign(code)
            }
            .disabled(selection == nil)
            .opacity(selection == nil ? 0.5 : 1)
        }
        .onChange(of: layer) { _, _ in expression = currentCode.map { state.keycodes.name(for: $0) } ?? "" }
    }

    // VIA style knobs (encoder attached to a matrix key) are edited here; Vial encoders appear on the canvas.
    private var knobs: [Int] {
        guard !state.definition.keys.contains(where: \.isEncoder) else { return [] }
        return Array(0..<state.definition.encoderCount)
    }

    private var knobRow: some View {
        HStack(spacing: 10) {
            Text("Döner düğme").font(.caption).foregroundStyle(.secondary)
            ForEach(knobs, id: \.self) { index in
                ForEach([false, true], id: \.self) { clockwise in
                    let slot = KeySlot.encoder(index: index, clockwise: clockwise)
                    let code = state.keymap.keycode(layer: layer, slot: slot) ?? 0
                    Button {
                        selection = slot
                        expression = state.keycodes.name(for: code)
                    } label: {
                        Text("\(index) \(clockwise ? "↻" : "↺")  \(state.keycodes.shortLabel(code))")
                    }
                    .buttonStyle(.bordered)
                    .tint(selection == slot ? .accentColor : nil)
                }
            }
        }
    }

    private var alphaControls: some View {
        HStack(spacing: 6) {
            Text("Alfabe").font(.caption).foregroundStyle(.secondary)
            Picker("Kaynak", selection: $alphaSource) {
                ForEach(AlphaLayout.all) { Text($0.name).tag($0) }
            }
            .labelsHidden()
            .frame(width: 120)
            Image(systemName: "arrow.right").foregroundStyle(.secondary)
            Picker("Hedef", selection: $alphaTarget) {
                ForEach(AlphaLayout.all) { Text($0.name).tag($0) }
            }
            .labelsHidden()
            .frame(width: 120)
            Button("Katman \(layer)'e uygula") {
                Task { await model.convertAlpha(device: device, layer: layer, from: alphaSource, to: alphaTarget) }
            }
            .disabled(alphaSource == alphaTarget)
            .help("Harf tuşlarını seçilen düzene çevirir; home-row mod ve layer-tap gibi basılı tutma işlevleri korunur.")
        }
    }

    private var currentCode: UInt16? {
        selection.flatMap { state.keymap.keycode(layer: layer, slot: $0) }
    }

    private var selectionBar: some View {
        HStack(spacing: 10) {
            if let selection, let code = currentCode {
                Text(describe(selection)).font(.callout.weight(.semibold))
                Text(state.keycodes.title(for: code)).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                holdMenu(code: code)
                TextField("Keycode (ör. LT(1, KC_SPC), LSFT_T(KC_A))", text: $expression)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 280)
                    .onSubmit(assignExpression)
                    .foregroundStyle(state.keycodes.parse(expression) == nil && !expression.isEmpty ? .red : .primary)
                Button("Ata", action: assignExpression)
                    .disabled(state.keycodes.parse(expression) == nil)
            } else {
                Text("Değiştirmek için klavyeden bir tuş seçin, sonra aşağıdan yeni işlevini seçin.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .frame(minHeight: 28)
    }

    /// Wraps the tap keycode of the selected key in a hold action (home row mods, layer tap).
    private func holdMenu(code: UInt16) -> some View {
        let tap: UInt16? = {
            switch state.keycodes.decode(code) {
            case let .modTap(_, kc), let .layerTap(_, kc): return kc
            case let .named(c) where c <= 0xFF: return c
            case let .raw(c) where c <= 0xFF: return c
            default: return nil
            }
        }()
        return Menu("Basılı tut") {
            if let tap {
                Button("Yok (sadece dokun)") { assign(tap) }
                Divider()
                ForEach([(UInt8(0x01), "⌃ Control"), (0x02, "⇧ Shift"), (0x04, "⌥ Option"), (0x08, "⌘ Command"), (0x07, "Meh"), (0x0F, "Hyper")], id: \.0) { mods, title in
                    Button(title) { if let value = state.keycodes.encode(.modTap(mods, tap)) { assign(value) } }
                }
                Divider()
                ForEach(1..<max(state.layerCount, 2), id: \.self) { target in
                    Button("Katman \(target)") { if let value = state.keycodes.encode(.layerTap(target, tap)) { assign(value) } }
                }
            } else {
                Text("Bu tuşa basılı tutma işlevi eklenemez")
            }
        }
        .fixedSize()
        .help("Dokununca tuş, basılı tutunca değiştirici veya katman (mod-tap / layer-tap)")
    }

    private func describe(_ slot: KeySlot) -> String {
        switch slot {
        case let .matrix(row, col): return "Katman \(layer) · R\(row) C\(col)"
        case let .encoder(index, clockwise): return "Katman \(layer) · Encoder \(index) \(clockwise ? "↻" : "↺")"
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

    private func cap(for key: LayoutKey) -> KeyCapModel {
        guard let code = state.keymap.keycode(layer: layer, slot: key.slot) else {
            return KeyCapModel(label: KeyLabel(main: "?"), style: .empty)
        }
        var label = state.keycodes.label(for: code)
        if key.isEncoder { label.sub = key.encoderDirection == 1 ? "↻" : "↺" }
        let style: KeyCapModel.Style
        switch state.keycodes.decode(code) {
        case .named(0x01): style = .transparent
        case .named(0x00): style = .empty
        case .layer, .layerTap, .layerMod: style = .layer
        default: style = .normal
        }
        return KeyCapModel(label: label, style: style, tooltip: "\(state.keycodes.title(for: code))\n\(state.keycodes.name(for: code))")
    }
}

/// Vial unlock: the user holds the unlock keys while we poll the keyboard.
private struct UnlockSheet: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Vial kilidini aç").font(.title3.weight(.semibold))
            Text("QK_BOOT gibi güvenlik gerektiren tuşları atamak için klavyenin kilidinin açılması gerekiyor. \"Başlat\"a basın ve aşağıdaki tuşları sayaç bitene kadar basılı tutun.")
                .fixedSize(horizontal: false, vertical: true)
            if let flow = model.unlock {
                Text("Tuşlar: " + flow.keys.map { "R\($0.row) C\($0.col)" }.joined(separator: ", "))
                    .font(.system(.body, design: .monospaced))
                if let counter = flow.counter {
                    ProgressView(value: max(0, 50 - Double(counter)), total: 50) { Text("Basılı tutun… \(counter)") }
                }
                HStack {
                    Spacer()
                    Button("Vazgeç", role: .cancel) { model.unlock = nil }
                    Button("Başlat") { Task { await model.runUnlock() } }
                        .disabled(flow.running)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
