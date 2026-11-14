import AppKit
import SwiftUI

@main
struct KeyMapperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent()
                .environment(model)
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)

        Window("KeyMapper", id: EditorWindow.id) {
            EditorWindow()
                .environment(model)
        }
        .defaultSize(width: 1180, height: 780)
        .defaultLaunchBehavior(.suppressed)
    }
}

extension Notification.Name {
    static let openEditor = Notification.Name("KeyMapper.openEditor")
}

/// The status item icon. It is always alive, so it also opens the editor on request
/// (re-launching the app from Finder / Spotlight, or `--editor`).
private struct MenuBarLabel: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: "keyboard.badge.ellipsis")
            .onReceive(NotificationCenter.default.publisher(for: .openEditor)) { _ in
                openWindow(id: EditorWindow.id)
                NSApp.activate(ignoringOtherApps: true)
            }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar app: no Dock icon until the editor window is opened.
        NSApp.setActivationPolicy(.accessory)
        if CommandLine.arguments.contains("--editor") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NotificationCenter.default.post(name: .openEditor, object: nil)
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        NotificationCenter.default.post(name: .openEditor, object: nil)
        return true
    }
}
