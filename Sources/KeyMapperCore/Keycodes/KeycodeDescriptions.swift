import Foundation

/// Short explanations of what a keycode does, shown when hovering over it (translated with `L`).
extension KeycodeSet {
    /// One or two sentences describing the keycode's effect (never just its QMK name).
    public func explanation(for code: UInt16) -> String {
        switch decode(code) {
        case let .named(c):
            return namedExplanation(c)
        case let .raw(c):
            return String(format: L("Bu klavyenin tanımadığı bir kod (0x%04X)."), c)
        case let .mods(mods, kc):
            return L("Tek tuşla %@%@ kısayolunu gönderir.", "\(modSymbol(mods))", "\(tapLegend(kc))")
        case let .modTap(mods, kc):
            return L("Dokununca %@, basılı tutunca %@.", "\(tapLegend(kc))", "\(KeycodeDescriptions.modWords(mods))")
        case let .layerTap(layer, kc):
            return L("Dokununca %@, basılı tutunca %@. katman.", "\(tapLegend(kc))", "\(layer)")
        case let .layerMod(layer, mods):
            return L("Basılı tutunca %@. katman ve %@ birlikte etkin olur.", "\(layer)", "\(KeycodeDescriptions.modWords(mods))")
        case let .layer(function, layer):
            return KeycodeDescriptions.layer(function, layer)
        case let .oneShotMod(mods):
            return L("Sonra basılan tek tuşa %@ uygular; basılı tutmak gerekmez.", "\(KeycodeDescriptions.modWords(mods))")
        case let .tapDance(index):
            return L("Tap dance %@: kaç kez dokunduğuna göre farklı iş yapar (Vial'da tanımlanır).", "\(index)")
        case let .macro(index):
            return L("Makro %@: klavyede kayıtlı tuş dizisini çalıştırır.", "\(index)")
        case let .custom(index):
            if index < customKeycodes.count {
                let custom = customKeycodes[index]
                return custom.title ?? custom.name
            }
            return L("Klavyeye özel işlev %@.", "\(index)")
        }
    }

    private func tapLegend(_ code: UInt16) -> String {
        let legend = shortLabel(code)
        return legend.isEmpty ? name(for: code) : legend
    }

    private func namedExplanation(_ code: UInt16) -> String {
        guard let entry = entry(for: code) else { return name(for: code) }
        if let text = KeycodeDescriptions.named[entry.name] { return L(text) }
        let label = label(for: code)
        switch code {
        case 0x04...0x1D:
            return L("%@ harfi.", label.main)
        case 0x1E...0x27:
            return L("%@ rakamı; Shift ile %@.", "\(label.main)", "\(label.top ?? "")")
        case 0x3A...0x45:
            return L("%@ fonksiyon tuşu.", "\(label.main)")
        case 0x68...0x73:
            return KeycodeDescriptions.highFunctionKey(Int(code) - 0x68 + 13)
        case 0x59...0x62:
            return L("Numpad'deki %@.", "\(label.main)")
        case 0x74...0x7E:
            return L("%@: eski klavye tuşu, çoğu macOS uygulaması tanımaz.", "\(entry.title == entry.name ? label.main : L(entry.title))")
        case 0x87...0x98:
            return L("Uluslararası klavye tuşu (%@); Japonca/Korece düzenlerde kullanılır.", "\(label.main)")
        default:
            if entry.title != entry.name { return L(entry.title) }
            return L("%@ tuşu.", "\(label.main)")
        }
    }
}

enum KeycodeDescriptions {
    static func modWords(_ mods: UInt8) -> String {
        switch mods & 0x0F {
        case 0x0F: return L("Hyper (⌃⌥⇧⌘)")
        case 0x07: return L("Meh (⌃⌥⇧)")
        default: break
        }
        var parts: [String] = []
        if mods & 0x01 != 0 { parts.append(L("⌃ Control")) }
        if mods & 0x02 != 0 { parts.append(L("⇧ Shift")) }
        if mods & 0x04 != 0 { parts.append(L("⌥ Option")) }
        if mods & 0x08 != 0 { parts.append(L("⌘ Command")) }
        let joined = parts.joined(separator: " + ")
        return mods & 0x10 != 0 ? L("sağ %@", "\(joined)") : joined
    }

    static func layer(_ function: LayerFunction, _ layer: Int) -> String {
        switch function {
        case .MO: return L("Basılı tuttuğun sürece %@. katman etkin olur.", "\(layer)")
        case .TG: return L("%@. katmanı açar veya kapatır.", "\(layer)")
        case .TO: return L("%@. katmana geçer ve orada kalır.", "\(layer)")
        case .TT: return L("Basılı tutunca geçici olarak, art arda dokununca kalıcı olarak %@. katmanı açar.", "\(layer)")
        case .OSL: return L("Yalnızca sonraki tek tuş için %@. katmanı açar.", "\(layer)")
        case .DF: return L("Varsayılan katmanı %@. katman yapar (klavye yeniden başlayınca sıfırlanır).", "\(layer)")
        case .PDF: return L("Varsayılan katmanı kalıcı olarak %@. katman yapar.", "\(layer)")
        }
    }

    static func highFunctionKey(_ number: Int) -> String {
        switch number {
        case 13: return L("F13: macOS'ta bir işi yok; Aksiyonlar'da tetik tuşu olarak kullanılabilir.")
        case 14: return L("F14: bazı Mac'lerde ekran parlaklığını azaltır; aksiyon tetiği de olabilir.")
        case 15: return L("F15: bazı Mac'lerde ekran parlaklığını artırır; aksiyon tetiği de olabilir.")
        case 16...20: return L("F%@: macOS'ta bir işi yok; Aksiyonlar'da uygulama açma veya kısayol için tetik tuşu olarak kullanılır.", "\(number)")
        default: return L("F%@: macOS bu tuşu tanımaz.", "\(number)")
        }
    }

    /// Explanations keyed by the QMK short name of a keycode (v5 and v6 spellings).
    static let named: [String: String] = [
        "KC_NO": LK("Boş: hiçbir şey yapmaz."),
        "KC_TRNS": LK("Şeffaf: alttaki katmanda bu konumdaki tuş çalışır."),
        "KC_ENT": LK("Enter / Return: satır sonu veya onay."),
        "KC_ESC": LK("Escape: iptal eder, menüleri ve pencereleri kapatır."),
        "KC_BSPC": LK("İmlecin solundaki karakteri siler."),
        "KC_TAB": LK("Sekme; alanlar arasında ilerler."),
        "KC_SPC": LK("Boşluk."),
        "KC_MINS": LK("Eksi (-); Shift ile alt çizgi (_)."),
        "KC_EQL": LK("Eşittir (=); Shift ile artı (+)."),
        "KC_LBRC": LK("Sol köşeli parantez ([); Shift ile {."),
        "KC_RBRC": LK("Sağ köşeli parantez (]); Shift ile }."),
        "KC_BSLS": LK("Ters eğik çizgi (\\); Shift ile |."),
        "KC_NUHS": LK("ISO klavyelerde Enter'ın yanındaki # tuşu."),
        "KC_SCLN": LK("Noktalı virgül (;); Shift ile iki nokta (:)."),
        "KC_QUOT": LK("Tek tırnak ('); Shift ile çift tırnak (\")."),
        "KC_GRV": LK("Ters tırnak (`); Shift ile ~."),
        "KC_COMM": LK("Virgül (,); Shift ile <."),
        "KC_DOT": LK("Nokta (.); Shift ile >."),
        "KC_SLSH": LK("Eğik çizgi (/); Shift ile ?."),
        "KC_CAPS": LK("Büyük harf kilidini açar veya kapatır."),
        "KC_PSCR": LK("Print Screen; macOS'ta F13 gibi davranır."),
        "KC_SCRL": LK("Scroll Lock; macOS'ta F14 gibi davranır (ekran parlaklığı −)."),
        "KC_PAUS": LK("Pause; macOS'ta F15 gibi davranır (ekran parlaklığı +)."),
        "KC_INS": LK("Insert; macOS'ta Yardım (Help) tuşu."),
        "KC_HOME": LK("Satırın veya belgenin başına gider."),
        "KC_PGUP": LK("Bir sayfa yukarı kaydırır."),
        "KC_DEL": LK("İmlecin sağındaki karakteri siler."),
        "KC_END": LK("Satırın veya belgenin sonuna gider."),
        "KC_PGDN": LK("Bir sayfa aşağı kaydırır."),
        "KC_RGHT": LK("İmleci sağa taşır."),
        "KC_LEFT": LK("İmleci sola taşır."),
        "KC_DOWN": LK("İmleci aşağı taşır."),
        "KC_UP": LK("İmleci yukarı taşır."),
        "KC_NUM": LK("Num Lock; macOS'ta Clear tuşu."),
        "KC_PSLS": LK("Numpad bölü (/)."),
        "KC_PAST": LK("Numpad çarpı (*)."),
        "KC_PMNS": LK("Numpad eksi (-)."),
        "KC_PPLS": LK("Numpad artı (+)."),
        "KC_PENT": LK("Numpad Enter."),
        "KC_PDOT": LK("Numpad nokta (.)."),
        "KC_PEQL": LK("Numpad eşittir (=)."),
        "KC_PCMM": LK("Numpad virgül (,)."),
        "KC_NUBS": LK("ISO klavyelerde sol Shift'in yanındaki < > tuşu."),
        "KC_APP": LK("Bağlam menüsü tuşu (Windows); macOS'ta işlevi yok."),
        "KC_KB_POWER": LK("Güç tuşu."),
        "KC_KB_MUTE": LK("Sesi kapatır (eski kod; çoğu durumda Sessiz tuşunu kullanın)."),
        "KC_KB_VOLUME_UP": LK("Sesi açar (eski kod; çoğu durumda Ses + tuşunu kullanın)."),
        "KC_KB_VOLUME_DOWN": LK("Sesi kısar (eski kod; çoğu durumda Ses − tuşunu kullanın)."),
        "KC_PWR": LK("Bilgisayarın güç düğmesi."),
        "KC_SLEP": LK("Bilgisayarı uyku moduna alır."),
        "KC_WAKE": LK("Bilgisayarı uykudan uyandırır."),
        "KC_MUTE": LK("Sesi kapatır veya açar."),
        "KC_VOLU": LK("Sesi açar."),
        "KC_VOLD": LK("Sesi kısar."),
        "KC_MNXT": LK("Sonraki parçaya geçer."),
        "KC_MPRV": LK("Önceki parçaya döner."),
        "KC_MSTP": LK("Çalmayı durdurur."),
        "KC_MPLY": LK("Müziği veya videoyu oynatır / duraklatır."),
        "KC_MSEL": LK("Medya uygulamasını seçer."),
        "KC_EJCT": LK("Diski veya sürücüyü çıkarır."),
        "KC_MAIL": LK("E-posta uygulamasını açar."),
        "KC_CALC": LK("Hesap Makinesi'ni açar."),
        "KC_MYCM": LK("Bilgisayarım / dosya yöneticisini açar."),
        "KC_WSCH": LK("Web aramasını açar."),
        "KC_WHOM": LK("Tarayıcının ana sayfasını açar."),
        "KC_WBAK": LK("Tarayıcıda bir sayfa geri gider."),
        "KC_WFWD": LK("Tarayıcıda bir sayfa ileri gider."),
        "KC_WSTP": LK("Sayfanın yüklenmesini durdurur."),
        "KC_WREF": LK("Sayfayı yeniler."),
        "KC_WFAV": LK("Yer imlerini açar."),
        "KC_MFFD": LK("İleri sarar."),
        "KC_MRWD": LK("Geri sarar."),
        "KC_BRIU": LK("Ekran parlaklığını artırır."),
        "KC_BRID": LK("Ekran parlaklığını azaltır."),
        "KC_CPNL": LK("Sistem Ayarları'nı / denetim masasını açar."),
        "KC_ASST": LK("Asistanı (Siri) açar."),
        "KC_MCTL": LK("Mission Control: açık tüm pencereleri gösterir."),
        "KC_LPAD": LK("Launchpad'i açar."),
        "KC_LCTL": LK("Sol Control (⌃): basılı tutup başka bir tuşla kısayol yapılır."),
        "KC_LSFT": LK("Sol Shift (⇧): büyük harf ve üst semboller için basılı tutulur."),
        "KC_LALT": LK("Sol Option (⌥); Windows'ta Alt."),
        "KC_LGUI": LK("Sol Command (⌘); Windows'ta Windows tuşu."),
        "KC_RCTL": LK("Sağ Control (⌃)."),
        "KC_RSFT": LK("Sağ Shift (⇧)."),
        "KC_RALT": LK("Sağ Option (⌥); Windows'ta AltGr."),
        "KC_RGUI": LK("Sağ Command (⌘); Windows'ta Windows tuşu."),

        "MS_UP": LK("Fare imlecini yukarı taşır."), "KC_MS_U": LK("Fare imlecini yukarı taşır."),
        "MS_DOWN": LK("Fare imlecini aşağı taşır."), "KC_MS_D": LK("Fare imlecini aşağı taşır."),
        "MS_LEFT": LK("Fare imlecini sola taşır."), "KC_MS_L": LK("Fare imlecini sola taşır."),
        "MS_RGHT": LK("Fare imlecini sağa taşır."), "KC_MS_R": LK("Fare imlecini sağa taşır."),
        "MS_BTN1": LK("Farenin sol tıkı."), "KC_BTN1": LK("Farenin sol tıkı."),
        "MS_BTN2": LK("Farenin sağ tıkı."), "KC_BTN2": LK("Farenin sağ tıkı."),
        "MS_BTN3": LK("Farenin orta tıkı."), "KC_BTN3": LK("Farenin orta tıkı."),
        "MS_BTN4": LK("Fare geri tuşu (tarayıcıda geri)."), "KC_BTN4": LK("Fare geri tuşu (tarayıcıda geri)."),
        "MS_BTN5": LK("Fare ileri tuşu (tarayıcıda ileri)."), "KC_BTN5": LK("Fare ileri tuşu (tarayıcıda ileri)."),
        "MS_WHLU": LK("Sayfayı yukarı kaydırır."), "KC_WH_U": LK("Sayfayı yukarı kaydırır."),
        "MS_WHLD": LK("Sayfayı aşağı kaydırır."), "KC_WH_D": LK("Sayfayı aşağı kaydırır."),
        "MS_WHLL": LK("Sayfayı sola kaydırır."), "KC_WH_L": LK("Sayfayı sola kaydırır."),
        "MS_WHLR": LK("Sayfayı sağa kaydırır."), "KC_WH_R": LK("Sayfayı sağa kaydırır."),
        "MS_ACL0": LK("Klavyeyle fare hızı: yavaş."), "KC_ACL0": LK("Klavyeyle fare hızı: yavaş."),
        "MS_ACL1": LK("Klavyeyle fare hızı: orta."), "KC_ACL1": LK("Klavyeyle fare hızı: orta."),
        "MS_ACL2": LK("Klavyeyle fare hızı: hızlı."), "KC_ACL2": LK("Klavyeyle fare hızı: hızlı."),

        "QK_BOOT": LK("Klavyeyi firmware yükleme (bootloader) moduna alır; klavye o sırada yazmaz."),
        "RESET": LK("Klavyeyi firmware yükleme (bootloader) moduna alır; klavye o sırada yazmaz."),
        "QK_RBT": LK("Klavyeyi yeniden başlatır."),
        "DB_TOGG": LK("Hata ayıklama modunu açar veya kapatır."), "DEBUG": LK("Hata ayıklama modunu açar veya kapatır."),
        "EE_CLR": LK("Klavyede kayıtlı ayarları fabrika değerlerine döndürür."),
        "AS_DOWN": LK("Auto Shift bekleme süresini kısaltır."),
        "AS_UP": LK("Auto Shift bekleme süresini uzatır."),
        "AS_RPT": LK("Auto Shift bekleme süresini yazı olarak yazar."),
        "AS_ON": LK("Auto Shift'i açar: tuşa uzun basınca büyük harf / üst sembol yazar."),
        "AS_OFF": LK("Auto Shift'i kapatır."),
        "AS_TOGG": LK("Auto Shift'i açar veya kapatır."),
        "QK_GESC": LK("Escape; Shift veya ⌘ ile birlikte ` yazar."), "KC_GESC": LK("Escape; Shift veya ⌘ ile birlikte ` yazar."),
        "SC_LCPO": LK("Dokununca (, basılı tutunca sol Control."),
        "SC_RCPC": LK("Dokununca ), basılı tutunca sağ Control."),
        "SC_LSPO": LK("Dokununca (, basılı tutunca sol Shift."), "KC_LSPO": LK("Dokununca (, basılı tutunca sol Shift."),
        "SC_RSPC": LK("Dokununca ), basılı tutunca sağ Shift."), "KC_RSPC": LK("Dokununca ), basılı tutunca sağ Shift."),
        "SC_LAPO": LK("Dokununca (, basılı tutunca sol Option."),
        "SC_RAPC": LK("Dokununca ), basılı tutunca sağ Option."),
        "SC_SENT": LK("Dokununca Enter, basılı tutunca sağ Shift."), "KC_SFTENT": LK("Dokununca Enter, basılı tutunca sağ Shift."),
        "CW_TOGG": LK("Caps Word: bir sonraki kelimeyi büyük harfle yazar, boşlukta kapanır."),
        "QK_REP": LK("Son basılan tuşu tekrarlar."),
        "QK_AREP": LK("Son tuşun tersini yapar (ör. sol ok → sağ ok)."),

        "BL_ON": LK("Tuş ışığını açar."),
        "BL_OFF": LK("Tuş ışığını kapatır."),
        "BL_TOGG": LK("Tuş ışığını açar veya kapatır."),
        "BL_DOWN": LK("Tuş ışığını azaltır."), "BL_DEC": LK("Tuş ışığını azaltır."),
        "BL_UP": LK("Tuş ışığını artırır."), "BL_INC": LK("Tuş ışığını artırır."),
        "BL_STEP": LK("Tuş ışığı seviyesini sırayla değiştirir."),
        "BL_BRTG": LK("Tuş ışığında nefes efektini açar veya kapatır."),
        "RGB_TOG": LK("RGB ışığı açar veya kapatır."),
        "RGB_MOD": LK("Sonraki RGB efektine geçer."),
        "RGB_RMOD": LK("Önceki RGB efektine döner."),
        "RGB_HUI": LK("RGB renk tonunu ileri kaydırır."),
        "RGB_HUD": LK("RGB renk tonunu geri kaydırır."),
        "RGB_SAI": LK("RGB renk doygunluğunu artırır."),
        "RGB_SAD": LK("RGB renk doygunluğunu azaltır."),
        "RGB_VAI": LK("RGB parlaklığını artırır."),
        "RGB_VAD": LK("RGB parlaklığını azaltır."),
        "RGB_SPI": LK("RGB efekt hızını artırır."),
        "RGB_SPD": LK("RGB efekt hızını azaltır."),
    ]
}
