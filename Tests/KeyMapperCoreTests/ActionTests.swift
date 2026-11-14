import Foundation
import Testing
@testable import KeyMapperCore

@Suite struct ActionTests {
    let safari = "com.apple.Safari"
    let code = "com.microsoft.VSCode"

    func sample() -> ActionBinding {
        ActionBinding(
            name: "Akıllı tuş",
            trigger: TriggerKey.all[0].combo,
            defaultAction: .keystroke(KeyCombo(keyCode: 0x31, modifiers: [.command], key: "Space")),
            appRules: [
                AppRule(bundleID: safari, appName: "Safari", action: .keystroke(KeyCombo(keyCode: 0x11, modifiers: [.command], key: "T"))),
                AppRule(bundleID: code, appName: "VS Code", action: .openURL("https://example.com")),
            ])
    }

    @Test func frontmostAppPicksItsRule() {
        let binding = sample()
        #expect(binding.action(frontmostBundleID: safari) == .keystroke(KeyCombo(keyCode: 0x11, modifiers: [.command], key: "T")))
        #expect(binding.action(frontmostBundleID: code) == .openURL("https://example.com"))
        #expect(binding.action(frontmostBundleID: "com.apple.finder") == binding.defaultAction)
        #expect(binding.action(frontmostBundleID: nil) == binding.defaultAction)
    }

    @Test func noDefaultMeansOnlyListedApps() {
        var binding = sample()
        binding.defaultAction = nil
        #expect(binding.action(frontmostBundleID: "com.apple.finder") == nil)
        #expect(binding.action(frontmostBundleID: safari) != nil)
    }

    @Test func accessibilityOnlyForSyntheticInput() {
        #expect(KeyAction.openApp(bundleID: safari, name: "Safari").needsAccessibility == false)
        #expect(KeyAction.runShortcut("x").needsAccessibility == false)
        #expect(KeyAction.typeText("x").needsAccessibility)
        #expect(sample().needsAccessibility)
    }

    @Test func triggerKeysAreDistinctAndPreferF16() {
        #expect(TriggerKey.all.first?.name == "F16")
        #expect(Set(TriggerKey.all.map(\.keyCode)).count == TriggerKey.all.count)
        #expect(Set(TriggerKey.all.map(\.usage)) == Set(0x68...0x6F))
        #expect(TriggerKey.forUsage(0x68)?.name == "F13")
        #expect(KeycodeSet.v6.name(for: TriggerKey.forUsage(0x6B)!.usage) == "KC_F16")
    }

    @Test func nextFreeTriggerSkipsUsedOnes() {
        let first = ActionBinding(name: "a", trigger: TriggerKey.all[0].combo)
        #expect(ActionStore.nextFreeTrigger(in: [first])?.name == TriggerKey.all[1].name)
        let all = TriggerKey.all.map { ActionBinding(name: $0.name, trigger: $0.combo) }
        #expect(ActionStore.nextFreeTrigger(in: all) == nil)
    }

    @Test func storeRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("km-actions-\(UUID().uuidString).json")
        let store = ActionStore(url: url)
        let binding = sample()
        try store.save([binding])
        #expect(store.load() == [binding])
        try? FileManager.default.removeItem(at: url)
    }

    @Test func presetsUseValidCombos() {
        for preset in ActionPresets.apps {
            #expect(!preset.shortcuts.isEmpty, "\(preset.appName)")
            for shortcut in preset.shortcuts { #expect(!shortcut.combo.display.isEmpty) }
        }
    }
}
