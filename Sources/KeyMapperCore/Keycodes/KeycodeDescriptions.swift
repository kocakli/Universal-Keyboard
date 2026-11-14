import Foundation

/// Short Turkish explanations of what a keycode does, shown when hovering over it.
extension KeycodeSet {
    /// One or two sentences describing the keycode's effect (never just its QMK name).
    public func explanation(for code: UInt16) -> String {
        switch decode(code) {
        case let .named(c):
            return namedExplanation(c)
        case let .raw(c):
            return String(format: "Bu klavyenin tanımadığı bir kod (0x%04X).", c)
        case let .mods(mods, kc):
            return "Tek tuşla \(modSymbol(mods))\(tapLegend(kc)) kısayolunu gönderir."
        case let .modTap(mods, kc):
            return "Dokununca \(tapLegend(kc)), basılı tutunca \(KeycodeDescriptions.modWords(mods))."
        case let .layerTap(layer, kc):
            return "Dokununca \(tapLegend(kc)), basılı tutunca \(layer). katman."
        case let .layerMod(layer, mods):
            return "Basılı tutunca \(layer). katman ve \(KeycodeDescriptions.modWords(mods)) birlikte etkin olur."
        case let .layer(function, layer):
            return KeycodeDescriptions.layer(function, layer)
        case let .oneShotMod(mods):
            return "Sonra basılan tek tuşa \(KeycodeDescriptions.modWords(mods)) uygular; basılı tutmak gerekmez."
        case let .tapDance(index):
            return "Tap dance \(index): kaç kez dokunduğuna göre farklı iş yapar (Vial'da tanımlanır)."
        case let .macro(index):
            return "Makro \(index): klavyede kayıtlı tuş dizisini çalıştırır."
        case let .custom(index):
            if index < customKeycodes.count {
                let custom = customKeycodes[index]
                return custom.title ?? custom.name
            }
            return "Klavyeye özel işlev \(index)."
        }
    }

    private func tapLegend(_ code: UInt16) -> String {
        let legend = shortLabel(code)
        return legend.isEmpty ? name(for: code) : legend
    }

    private func namedExplanation(_ code: UInt16) -> String {
        guard let entry = entry(for: code) else { return name(for: code) }
        if let text = KeycodeDescriptions.named[entry.name] { return text }
        let label = label(for: code)
        switch code {
        case 0x04...0x1D:
            return "\(label.main) harfi."
        case 0x1E...0x27:
            return "\(label.main) rakamı; Shift ile \(label.top ?? "")."
        case 0x3A...0x45:
            return "\(label.main) fonksiyon tuşu."
        case 0x68...0x73:
            return KeycodeDescriptions.highFunctionKey(Int(code) - 0x68 + 13)
        case 0x59...0x62:
            return "Numpad'deki \(label.main)."
        case 0x74...0x7E:
            return "\(entry.title == entry.name ? label.main : entry.title): eski klavye tuşu, çoğu macOS uygulaması tanımaz."
        case 0x87...0x98:
            return "Uluslararası klavye tuşu (\(label.main)); Japonca/Korece düzenlerde kullanılır."
        default:
            if entry.title != entry.name { return entry.title }
            return "\(label.main) tuşu."
        }
    }
}

enum KeycodeDescriptions {
    static func modWords(_ mods: UInt8) -> String {
        switch mods & 0x0F {
        case 0x0F: return "Hyper (⌃⌥⇧⌘)"
        case 0x07: return "Meh (⌃⌥⇧)"
        default: break
        }
        var parts: [String] = []
        if mods & 0x01 != 0 { parts.append("⌃ Control") }
        if mods & 0x02 != 0 { parts.append("⇧ Shift") }
        if mods & 0x04 != 0 { parts.append("⌥ Option") }
        if mods & 0x08 != 0 { parts.append("⌘ Command") }
        let joined = parts.joined(separator: " + ")
        return mods & 0x10 != 0 ? "sağ \(joined)" : joined
    }

    static func layer(_ function: LayerFunction, _ layer: Int) -> String {
        switch function {
        case .MO: return "Basılı tuttuğun sürece \(layer). katman etkin olur."
        case .TG: return "\(layer). katmanı açar veya kapatır."
        case .TO: return "\(layer). katmana geçer ve orada kalır."
        case .TT: return "Basılı tutunca geçici olarak, art arda dokununca kalıcı olarak \(layer). katmanı açar."
        case .OSL: return "Yalnızca sonraki tek tuş için \(layer). katmanı açar."
        case .DF: return "Varsayılan katmanı \(layer). katman yapar (klavye yeniden başlayınca sıfırlanır)."
        case .PDF: return "Varsayılan katmanı kalıcı olarak \(layer). katman yapar."
        }
    }

    static func highFunctionKey(_ number: Int) -> String {
        switch number {
        case 13: return "F13: macOS'ta bir işi yok; Aksiyonlar'da tetik tuşu olarak kullanılabilir."
        case 14: return "F14: bazı Mac'lerde ekran parlaklığını azaltır; aksiyon tetiği de olabilir."
        case 15: return "F15: bazı Mac'lerde ekran parlaklığını artırır; aksiyon tetiği de olabilir."
        case 16...20: return "F\(number): macOS'ta bir işi yok; Aksiyonlar'da uygulama açma veya kısayol için tetik tuşu olarak kullanılır."
        default: return "F\(number): macOS bu tuşu tanımaz."
        }
    }

    /// Explanations keyed by the QMK short name of a keycode (v5 and v6 spellings).
    static let named: [String: String] = [
        "KC_NO": "Boş: hiçbir şey yapmaz.",
        "KC_TRNS": "Şeffaf: alttaki katmanda bu konumdaki tuş çalışır.",
        "KC_ENT": "Enter / Return: satır sonu veya onay.",
        "KC_ESC": "Escape: iptal eder, menüleri ve pencereleri kapatır.",
        "KC_BSPC": "İmlecin solundaki karakteri siler.",
        "KC_TAB": "Sekme; alanlar arasında ilerler.",
        "KC_SPC": "Boşluk.",
        "KC_MINS": "Eksi (-); Shift ile alt çizgi (_).",
        "KC_EQL": "Eşittir (=); Shift ile artı (+).",
        "KC_LBRC": "Sol köşeli parantez ([); Shift ile {.",
        "KC_RBRC": "Sağ köşeli parantez (]); Shift ile }.",
        "KC_BSLS": "Ters eğik çizgi (\\); Shift ile |.",
        "KC_NUHS": "ISO klavyelerde Enter'ın yanındaki # tuşu.",
        "KC_SCLN": "Noktalı virgül (;); Shift ile iki nokta (:).",
        "KC_QUOT": "Tek tırnak ('); Shift ile çift tırnak (\").",
        "KC_GRV": "Ters tırnak (`); Shift ile ~.",
        "KC_COMM": "Virgül (,); Shift ile <.",
        "KC_DOT": "Nokta (.); Shift ile >.",
        "KC_SLSH": "Eğik çizgi (/); Shift ile ?.",
        "KC_CAPS": "Büyük harf kilidini açar veya kapatır.",
        "KC_PSCR": "Print Screen; macOS'ta F13 gibi davranır.",
        "KC_SCRL": "Scroll Lock; macOS'ta F14 gibi davranır (ekran parlaklığı −).",
        "KC_PAUS": "Pause; macOS'ta F15 gibi davranır (ekran parlaklığı +).",
        "KC_INS": "Insert; macOS'ta Yardım (Help) tuşu.",
        "KC_HOME": "Satırın veya belgenin başına gider.",
        "KC_PGUP": "Bir sayfa yukarı kaydırır.",
        "KC_DEL": "İmlecin sağındaki karakteri siler.",
        "KC_END": "Satırın veya belgenin sonuna gider.",
        "KC_PGDN": "Bir sayfa aşağı kaydırır.",
        "KC_RGHT": "İmleci sağa taşır.",
        "KC_LEFT": "İmleci sola taşır.",
        "KC_DOWN": "İmleci aşağı taşır.",
        "KC_UP": "İmleci yukarı taşır.",
        "KC_NUM": "Num Lock; macOS'ta Clear tuşu.",
        "KC_PSLS": "Numpad bölü (/).",
        "KC_PAST": "Numpad çarpı (*).",
        "KC_PMNS": "Numpad eksi (-).",
        "KC_PPLS": "Numpad artı (+).",
        "KC_PENT": "Numpad Enter.",
        "KC_PDOT": "Numpad nokta (.).",
        "KC_PEQL": "Numpad eşittir (=).",
        "KC_PCMM": "Numpad virgül (,).",
        "KC_NUBS": "ISO klavyelerde sol Shift'in yanındaki < > tuşu.",
        "KC_APP": "Bağlam menüsü tuşu (Windows); macOS'ta işlevi yok.",
        "KC_KB_POWER": "Güç tuşu.",
        "KC_KB_MUTE": "Sesi kapatır (eski kod; çoğu durumda Sessiz tuşunu kullanın).",
        "KC_KB_VOLUME_UP": "Sesi açar (eski kod; çoğu durumda Ses + tuşunu kullanın).",
        "KC_KB_VOLUME_DOWN": "Sesi kısar (eski kod; çoğu durumda Ses − tuşunu kullanın).",
        "KC_PWR": "Bilgisayarın güç düğmesi.",
        "KC_SLEP": "Bilgisayarı uyku moduna alır.",
        "KC_WAKE": "Bilgisayarı uykudan uyandırır.",
        "KC_MUTE": "Sesi kapatır veya açar.",
        "KC_VOLU": "Sesi açar.",
        "KC_VOLD": "Sesi kısar.",
        "KC_MNXT": "Sonraki parçaya geçer.",
        "KC_MPRV": "Önceki parçaya döner.",
        "KC_MSTP": "Çalmayı durdurur.",
        "KC_MPLY": "Müziği veya videoyu oynatır / duraklatır.",
        "KC_MSEL": "Medya uygulamasını seçer.",
        "KC_EJCT": "Diski veya sürücüyü çıkarır.",
        "KC_MAIL": "E-posta uygulamasını açar.",
        "KC_CALC": "Hesap Makinesi'ni açar.",
        "KC_MYCM": "Bilgisayarım / dosya yöneticisini açar.",
        "KC_WSCH": "Web aramasını açar.",
        "KC_WHOM": "Tarayıcının ana sayfasını açar.",
        "KC_WBAK": "Tarayıcıda bir sayfa geri gider.",
        "KC_WFWD": "Tarayıcıda bir sayfa ileri gider.",
        "KC_WSTP": "Sayfanın yüklenmesini durdurur.",
        "KC_WREF": "Sayfayı yeniler.",
        "KC_WFAV": "Yer imlerini açar.",
        "KC_MFFD": "İleri sarar.",
        "KC_MRWD": "Geri sarar.",
        "KC_BRIU": "Ekran parlaklığını artırır.",
        "KC_BRID": "Ekran parlaklığını azaltır.",
        "KC_CPNL": "Sistem Ayarları'nı / denetim masasını açar.",
        "KC_ASST": "Asistanı (Siri) açar.",
        "KC_MCTL": "Mission Control: açık tüm pencereleri gösterir.",
        "KC_LPAD": "Launchpad'i açar.",
        "KC_LCTL": "Sol Control (⌃): basılı tutup başka bir tuşla kısayol yapılır.",
        "KC_LSFT": "Sol Shift (⇧): büyük harf ve üst semboller için basılı tutulur.",
        "KC_LALT": "Sol Option (⌥); Windows'ta Alt.",
        "KC_LGUI": "Sol Command (⌘); Windows'ta Windows tuşu.",
        "KC_RCTL": "Sağ Control (⌃).",
        "KC_RSFT": "Sağ Shift (⇧).",
        "KC_RALT": "Sağ Option (⌥); Windows'ta AltGr.",
        "KC_RGUI": "Sağ Command (⌘); Windows'ta Windows tuşu.",

        "MS_UP": "Fare imlecini yukarı taşır.", "KC_MS_U": "Fare imlecini yukarı taşır.",
        "MS_DOWN": "Fare imlecini aşağı taşır.", "KC_MS_D": "Fare imlecini aşağı taşır.",
        "MS_LEFT": "Fare imlecini sola taşır.", "KC_MS_L": "Fare imlecini sola taşır.",
        "MS_RGHT": "Fare imlecini sağa taşır.", "KC_MS_R": "Fare imlecini sağa taşır.",
        "MS_BTN1": "Farenin sol tıkı.", "KC_BTN1": "Farenin sol tıkı.",
        "MS_BTN2": "Farenin sağ tıkı.", "KC_BTN2": "Farenin sağ tıkı.",
        "MS_BTN3": "Farenin orta tıkı.", "KC_BTN3": "Farenin orta tıkı.",
        "MS_BTN4": "Fare geri tuşu (tarayıcıda geri).", "KC_BTN4": "Fare geri tuşu (tarayıcıda geri).",
        "MS_BTN5": "Fare ileri tuşu (tarayıcıda ileri).", "KC_BTN5": "Fare ileri tuşu (tarayıcıda ileri).",
        "MS_WHLU": "Sayfayı yukarı kaydırır.", "KC_WH_U": "Sayfayı yukarı kaydırır.",
        "MS_WHLD": "Sayfayı aşağı kaydırır.", "KC_WH_D": "Sayfayı aşağı kaydırır.",
        "MS_WHLL": "Sayfayı sola kaydırır.", "KC_WH_L": "Sayfayı sola kaydırır.",
        "MS_WHLR": "Sayfayı sağa kaydırır.", "KC_WH_R": "Sayfayı sağa kaydırır.",
        "MS_ACL0": "Klavyeyle fare hızı: yavaş.", "KC_ACL0": "Klavyeyle fare hızı: yavaş.",
        "MS_ACL1": "Klavyeyle fare hızı: orta.", "KC_ACL1": "Klavyeyle fare hızı: orta.",
        "MS_ACL2": "Klavyeyle fare hızı: hızlı.", "KC_ACL2": "Klavyeyle fare hızı: hızlı.",

        "QK_BOOT": "Klavyeyi firmware yükleme (bootloader) moduna alır; klavye o sırada yazmaz.",
        "RESET": "Klavyeyi firmware yükleme (bootloader) moduna alır; klavye o sırada yazmaz.",
        "QK_RBT": "Klavyeyi yeniden başlatır.",
        "DB_TOGG": "Hata ayıklama modunu açar veya kapatır.", "DEBUG": "Hata ayıklama modunu açar veya kapatır.",
        "EE_CLR": "Klavyede kayıtlı ayarları fabrika değerlerine döndürür.",
        "AS_DOWN": "Auto Shift bekleme süresini kısaltır.",
        "AS_UP": "Auto Shift bekleme süresini uzatır.",
        "AS_RPT": "Auto Shift bekleme süresini yazı olarak yazar.",
        "AS_ON": "Auto Shift'i açar: tuşa uzun basınca büyük harf / üst sembol yazar.",
        "AS_OFF": "Auto Shift'i kapatır.",
        "AS_TOGG": "Auto Shift'i açar veya kapatır.",
        "QK_GESC": "Escape; Shift veya ⌘ ile birlikte ` yazar.", "KC_GESC": "Escape; Shift veya ⌘ ile birlikte ` yazar.",
        "SC_LCPO": "Dokununca (, basılı tutunca sol Control.",
        "SC_RCPC": "Dokununca ), basılı tutunca sağ Control.",
        "SC_LSPO": "Dokununca (, basılı tutunca sol Shift.", "KC_LSPO": "Dokununca (, basılı tutunca sol Shift.",
        "SC_RSPC": "Dokununca ), basılı tutunca sağ Shift.", "KC_RSPC": "Dokununca ), basılı tutunca sağ Shift.",
        "SC_LAPO": "Dokununca (, basılı tutunca sol Option.",
        "SC_RAPC": "Dokununca ), basılı tutunca sağ Option.",
        "SC_SENT": "Dokununca Enter, basılı tutunca sağ Shift.", "KC_SFTENT": "Dokununca Enter, basılı tutunca sağ Shift.",
        "CW_TOGG": "Caps Word: bir sonraki kelimeyi büyük harfle yazar, boşlukta kapanır.",
        "QK_REP": "Son basılan tuşu tekrarlar.",
        "QK_AREP": "Son tuşun tersini yapar (ör. sol ok → sağ ok).",

        "BL_ON": "Tuş ışığını açar.",
        "BL_OFF": "Tuş ışığını kapatır.",
        "BL_TOGG": "Tuş ışığını açar veya kapatır.",
        "BL_DOWN": "Tuş ışığını azaltır.", "BL_DEC": "Tuş ışığını azaltır.",
        "BL_UP": "Tuş ışığını artırır.", "BL_INC": "Tuş ışığını artırır.",
        "BL_STEP": "Tuş ışığı seviyesini sırayla değiştirir.",
        "BL_BRTG": "Tuş ışığında nefes efektini açar veya kapatır.",
        "RGB_TOG": "RGB ışığı açar veya kapatır.",
        "RGB_MOD": "Sonraki RGB efektine geçer.",
        "RGB_RMOD": "Önceki RGB efektine döner.",
        "RGB_HUI": "RGB renk tonunu ileri kaydırır.",
        "RGB_HUD": "RGB renk tonunu geri kaydırır.",
        "RGB_SAI": "RGB renk doygunluğunu artırır.",
        "RGB_SAD": "RGB renk doygunluğunu azaltır.",
        "RGB_VAI": "RGB parlaklığını artırır.",
        "RGB_VAD": "RGB parlaklığını azaltır.",
        "RGB_SPI": "RGB efekt hızını artırır.",
        "RGB_SPD": "RGB efekt hızını azaltır.",
    ]
}
