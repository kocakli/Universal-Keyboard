import AppKit
import KeyMapperCore
import SwiftUI

/// "About KeyMapper": the standard macOS about panel with the author and links.
enum About {
    static let author = "Oğuzhan Koçaklı"
    static let profile = URL(string: "https://github.com/kocakli")!
    static let repository = URL(string: "https://github.com/kocakli/Universal-Keyboard")!

    @MainActor
    static func show() {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.paragraphSpacing = 4
        let body: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph,
        ]
        func link(_ title: String, _ url: URL) -> NSAttributedString {
            NSAttributedString(string: title, attributes: body.merging([.link: url]) { _, new in new })
        }

        let credits = NSMutableAttributedString(string: L("Geliştiren: %@", author) + "\n", attributes: body)
        credits.append(link("github.com/kocakli", profile))
        credits.append(NSAttributedString(string: "\n", attributes: body))
        credits.append(link(L("Kaynak kodu"), repository))

        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "KeyMapper",
            .credits: credits,
            NSApplication.AboutPanelOptionKey(rawValue: "Copyright"): "© 2026 \(author)",
        ])
    }
}

/// Small "About" row for the sidebar and the menu bar popover.
struct AboutButton: View {
    var body: some View {
        Button(L("KeyMapper hakkında")) { About.show() }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(Theme.textSecondary)
            .help(L("Sürüm, geliştirici ve GitHub bağlantısı"))
    }
}
