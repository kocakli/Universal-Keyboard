import Foundation

/// Ready made per-app shortcuts, in the spirit of Logitech Options+ app-specific presets.
/// Titles are Turkish source strings (translated with `L` where shown); shortcuts use
/// `ShortcutNotation` ("⌘⇧T", "Esc", "↩" …).
public enum ActionPresets {
    public struct AppPreset: Identifiable, Sendable {
        public let bundleID: String
        public let appName: String
        public let shortcuts: [(title: String, combo: KeyCombo)]
        public var id: String { bundleID }

        init(_ bundleID: String, _ appName: String, _ items: [(String, String)]) {
            self.bundleID = bundleID
            self.appName = appName
            self.shortcuts = items.compactMap { title, notation in ShortcutNotation.parse(notation).map { (title, $0) } }
            assert(shortcuts.count == items.count, "unparsable shortcut in \(appName)")
        }
    }

    public static func preset(for bundleID: String) -> AppPreset? {
        apps.first { $0.bundleID == bundleID }
    }

    // MARK: Shared groups

    /// Answering Claude Code in a terminal. Enter takes the highlighted option ("Yes" is first),
    /// Esc declines. Shift+Tab is left out on purpose: it approves plans / allows for the session.
    static let claudeCode: [(String, String)] = [
        (LK("Claude: onayla"), "↩"),
        (LK("Claude: reddet / durdur"), "Esc"),
        (LK("Claude: yanıta not ekle"), "⇥"),
        (LK("Claude: işlemi kes"), "⌃C"),
    ]

    static let terminal: [(String, String)] = claudeCode + [
        (LK("Yeni sekme"), "⌘T"),
        (LK("Sekmeyi kapat"), "⌘W"),
        (LK("Ekranı temizle"), "⌘K"),
    ]

    static let browserTabs: [(String, String)] = [
        (LK("Yeni sekme"), "⌘T"),
        (LK("Sekmeyi kapat"), "⌘W"),
        (LK("Kapatılan sekmeyi geri aç"), "⌘⇧T"),
        (LK("Sayfayı yenile"), "⌘R"),
        (LK("Adres çubuğu"), "⌘L"),
        (LK("Geri"), "⌘["),
        (LK("İleri"), "⌘]"),
    ]

    static let chromiumTabs: [(String, String)] = browserTabs + [
        (LK("Önceki sekme"), "⌘⌥←"),
        (LK("Sonraki sekme"), "⌘⌥→"),
    ]

    static let vsCode: [(String, String)] = [
        (LK("Komut paleti"), "⌘⇧P"),
        (LK("Dosyaya git"), "⌘P"),
        (LK("Terminali aç/kapat"), "⌃`"),
        (LK("Satırı yorum yap"), "⌘/"),
    ]

    // MARK: Catalogue
    // Shortcuts were checked against each vendor's documentation or the app's own menus
    // (November 2026). Keys that depend on the keyboard layout (` \ / [ ]) follow the US positions.

    public static let apps: [AppPreset] = [
        // AI assistants
        AppPreset("com.anthropic.claudefordesktop", "Claude", [
            (LK("Claude: onayla"), "↩"),
            (LK("Claude: reddet / durdur"), "Esc"),
            (LK("Yeni oturum"), "⌘N"),
            (LK("İzin modu menüsü"), "⌘⇧M"),
            (LK("Değişiklikler (diff) paneli"), "⌘⇧D"),
            (LK("Kısayolları göster"), "⌘/"),
        ]),
        AppPreset("com.openai.codex", "ChatGPT", [
            (LK("Yeni sohbet"), "⌘N"),
            (LK("Geçici sohbet"), "⌘⇧N"),
            (LK("Kenar çubuğu"), "⌘⇧S"),
            (LK("Önceki sekme"), "⌘⇧["),
            (LK("Sonraki sekme"), "⌘⇧]"),
            (LK("Kısayolları göster"), "⌘/"),
        ]),
        AppPreset("com.openai.chat", "ChatGPT", [
            (LK("Yeni sohbet"), "⌘N"),
        ]),

        // Terminals (Claude Code runs here)
        AppPreset("com.apple.Terminal", "Terminal", terminal),
        AppPreset("com.googlecode.iterm2", "iTerm2", terminal),
        AppPreset("dev.warp.Warp-Stable", "Warp", terminal),
        AppPreset("com.mitchellh.ghostty", "Ghostty", terminal),

        // Browsers
        AppPreset("com.apple.Safari", "Safari", browserTabs + [
            (LK("Önceki sekme"), "⌘⇧["),
            (LK("Sonraki sekme"), "⌘⇧]"),
            (LK("Özel pencere"), "⌘⇧N"),
            (LK("Sekme genel görünümü"), "⌘⇧\\"),
            (LK("Web denetçisi"), "⌥⌘I"),
        ]),
        AppPreset("com.google.Chrome", "Google Chrome", chromiumTabs + [
            (LK("İndirilenler"), "⌘⇧J"),
            (LK("Yer imi ekle"), "⌘D"),
        ]),
        AppPreset("com.brave.Browser", "Brave", chromiumTabs),
        AppPreset("company.thebrowser.Browser", "Arc", [
            (LK("Yeni sekme"), "⌘T"),
            (LK("Sekmeyi kapat"), "⌘W"),
            (LK("Kapatılan sekmeyi geri aç"), "⌘⇧T"),
        ]),
        AppPreset("org.mozilla.firefox", "Firefox", browserTabs + [
            (LK("Özel pencere"), "⌘⇧P"),
            (LK("Geliştirici araçları"), "⌥⌘I"),
        ]),

        // System apps
        AppPreset("com.apple.finder", "Finder", [
            (LK("Yeni klasör"), "⌘⇧N"),
            (LK("Yeni pencere"), "⌘N"),
            (LK("Klasöre git"), "⌘⇧G"),
            (LK("İndirilenler"), "⌥⌘L"),
            (LK("Uygulamalar"), "⌘⇧A"),
            (LK("Çoğalt"), "⌘D"),
            (LK("Çöp sepetine taşı"), "⌘⌫"),
            (LK("Bilgi al"), "⌘I"),
            (LK("Gizli dosyaları göster"), "⌘⇧."),
        ]),
        AppPreset("com.apple.mail", "Mail", [
            (LK("Yeni ileti"), "⌘N"),
            (LK("Yanıtla"), "⌘R"),
            (LK("Tümünü yanıtla"), "⌘⇧R"),
            (LK("İlet"), "⌘⇧F"),
            (LK("Yeni postaları al"), "⌘⇧N"),
            (LK("Okundu / okunmadı"), "⌘⇧U"),
            (LK("Gereksiz olarak işaretle"), "⌘⇧J"),
        ]),
        AppPreset("com.apple.Music", "Music", [
            (LK("Oynat / duraklat"), "Space"),
            (LK("Sesi aç"), "⌘↑"),
            (LK("Sesi kıs"), "⌘↓"),
            (LK("Çalan şarkıya git"), "⌘L"),
            (LK("Mini oynatıcı"), "⌥⌘M"),
            (LK("Ara"), "⌘F"),
        ]),

        // Developer tools
        AppPreset("com.microsoft.VSCode", "Visual Studio Code", vsCode + [
            (LK("Sembole git"), "⌘⇧O"),
            (LK("Tanıma git"), "F12"),
            (LK("Sembolü yeniden adlandır"), "F2"),
            (LK("Düzenleyiciyi böl"), "⌘\\"),
        ]),
        AppPreset("com.todesktop.230313mzl4w4u92", "Cursor", vsCode + [
            (LK("AI paneli"), "⌘L"),
            (LK("Yan paneli aç/kapat"), "⌘I"),
            (LK("Seçimi sohbete ekle"), "⌘⇧L"),
        ]),
        AppPreset("com.apple.dt.Xcode", "Xcode", [
            (LK("Derle"), "⌘B"),
            (LK("Çalıştır"), "⌘R"),
            (LK("Durdur"), "⌘."),
            (LK("Testleri çalıştır"), "⌘U"),
            (LK("Hızlı aç"), "⌘⇧O"),
            (LK("Hata ayıklama alanı"), "⌘⇧Y"),
            (LK("Derleme klasörünü temizle"), "⌘⇧K"),
        ]),

        // Meetings and chat
        AppPreset("us.zoom.xos", "zoom.us", [
            (LK("Mikrofonu aç/kapat"), "⌘⇧A"),
            (LK("Kamerayı aç/kapat"), "⌘⇧V"),
            (LK("Ekran paylaş"), "⌘⇧S"),
            (LK("Sohbet paneli"), "⌘⇧H"),
            (LK("Galeri / konuşmacı görünümü"), "⌘⇧W"),
            (LK("Kaydı başlat/durdur"), "⌘⇧R"),
        ]),
        AppPreset("com.microsoft.teams2", "Microsoft Teams", [
            (LK("Mikrofonu aç/kapat"), "⌘⇧M"),
            (LK("Kamerayı aç/kapat"), "⌘⇧O"),
            (LK("El kaldır"), "⌘⇧K"),
            (LK("Görüşmeden ayrıl"), "⌘⇧H"),
            (LK("Ara"), "⌘E"),
        ]),
        AppPreset("com.tinyspeck.slackmacgap", "Slack", [
            (LK("Hızlı geçiş"), "⌘K"),
            (LK("Ara"), "⌘G"),
            (LK("Okunmamışlar"), "⌘⇧A"),
            (LK("Thread'ler"), "⌘⇧T"),
            (LK("Etkinlik"), "⌘⇧M"),
            (LK("Huddle başlat/katıl"), "⌘⇧H"),
            (LK("Huddle'da mikrofonu aç/kapat"), "⌘⇧Space"),
        ]),
        AppPreset("com.hnc.Discord", "Discord", [
            (LK("Mikrofonu aç/kapat"), "⌘⇧M"),
            (LK("Sesi kapat (sağırlaştır)"), "⌘⇧D"),
            (LK("Hızlı geçiş"), "⌘K"),
        ]),

        // Notes and documents
        AppPreset("notion.id", "Notion", [
            (LK("Yeni sayfa"), "⌘N"),
            (LK("Ara"), "⌘P"),
            (LK("Kenar çubuğu"), "⌘\\"),
            (LK("Geri"), "⌘["),
            (LK("İleri"), "⌘]"),
            (LK("Bağlantıyı kopyala"), "⌘L"),
            (LK("Yorum ekle"), "⌘⇧M"),
        ]),
        AppPreset("md.obsidian", "Obsidian", [
            (LK("Komut paleti"), "⌘P"),
            (LK("Hızlı geçiş"), "⌘O"),
            (LK("Düzenleme / okuma görünümü"), "⌘E"),
            (LK("Tüm notlarda ara"), "⌘⇧F"),
        ]),
        AppPreset("com.microsoft.Word", "Microsoft Word", [
            (LK("Kalın"), "⌘B"),
            (LK("İtalik"), "⌘I"),
            (LK("Altı çizili"), "⌘U"),
            (LK("Üstü çizili"), "⌘⇧X"),
            (LK("Başlık 1"), "⌥⌘1"),
            (LK("Değişiklikleri izle"), "⌘⇧E"),
        ]),
        AppPreset("com.microsoft.Excel", "Microsoft Excel", [
            (LK("Otomatik toplam"), "⌘⇧T"),
            (LK("Hücreleri biçimlendir"), "⌘1"),
            (LK("Filtre"), "⌘⇧F"),
            (LK("Mutlak başvuru"), "⌘T"),
        ]),
        AppPreset("com.microsoft.Powerpoint", "Microsoft PowerPoint", [
            (LK("Bu slayttan sun"), "⌘⇧↩"),
            (LK("Sunucu görünümü"), "⌥↩"),
            (LK("Yeni slayt"), "⌘⇧N"),
            (LK("Slaytı çoğalt"), "⌘⇧D"),
        ]),

        // Creative
        AppPreset("com.adobe.Photoshop", "Adobe Photoshop", [
            (LK("Geri al"), "⌘Z"),
            (LK("Yeni katman"), "⌘⇧N"),
            (LK("Katmanı çoğalt"), "⌘J"),
            (LK("Aşağı birleştir"), "⌘E"),
            (LK("Serbest dönüştür"), "⌘T"),
            (LK("Ekrana sığdır"), "⌘0"),
            (LK("Farklı dışa aktar"), "⌥⇧⌘W"),
            (LK("Fırça"), "B"),
        ]),
        AppPreset("com.apple.FinalCut", "Final Cut Pro", [
            (LK("Oynatma başlığında kes"), "⌘B"),
            (LK("Sona ekle"), "E"),
            (LK("Bağla"), "Q"),
        ]),
        AppPreset("com.spotify.client", "Spotify", [
            (LK("Oynat / duraklat"), "Space"),
            (LK("Ara"), "⌘K"),
            (LK("Beğen"), "⌥⇧B"),
            (LK("Karıştır"), "⌥S"),
        ]),
    ]

    /// System wide suggestions for the default action.
    public static let system: [(title: String, combo: KeyCombo)] = [
        (LK("Ekran görüntüsü (alan)"), "⌘⇧4"),
        (LK("Spotlight"), "⌘Space"),
        (LK("Mission Control"), "⌃↑"),
        (LK("Masaüstü sola"), "⌃←"),
        (LK("Masaüstü sağa"), "⌃→"),
    ].compactMap { title, notation in ShortcutNotation.parse(notation).map { (title, $0) } }
}
