import KeyMapperCore
import SwiftUI

/// Language picker: follow macOS or one of the bundled languages. Takes effect immediately.
struct LanguageMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Menu {
            Button { model.setLanguage(nil) } label: {
                item(L("Sistem dili (%@)", AppLanguage.preferred().nativeName), isOn: model.languageOverride == nil)
            }
            Divider()
            ForEach(AppLanguage.allCases) { language in
                Button { model.setLanguage(language) } label: {
                    item(language.nativeName, isOn: model.languageOverride == language)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "globe")
                Text(model.language.nativeName)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }
            .font(.system(size: 12))
            .foregroundStyle(Theme.textSecondary)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(L("Arayüz dili"))
        .accessibilityLabel(L("Arayüz dili"))
    }

    @ViewBuilder
    private func item(_ title: String, isOn: Bool) -> some View {
        if isOn { Label(title, systemImage: "checkmark") } else { Text(title) }
    }
}
