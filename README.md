# KeyMapper

macOS menü çubuğundan erişilen evrensel klavye eşleme aracı. Bağlı klavyeyi seçip ona layout (keymap) atarsınız; klavyenin markasına ve firmware'ine göre en uygun yöntem otomatik seçilir.

| Klavye türü | Örnekler | Nasıl düzenlenir |
|---|---|---|
| **Vial** | Cornix, Corne (crkbd), Lily58, Sofle ve vial.rocks ile çalışan tüm klavyeler | Tanım doğrudan klavyeden okunur (USB veya Bluetooth), keymap firmware'e yazılır |
| **VIA / QMK** | Keychron (Q/V/K Pro…), NuPhy, KBDfans, Keebio, DZTech, Glorious GMMK Pro… | Tanım VIA deposundan (usevia.app) otomatik indirilir veya JSON olarak yüklenir, keymap firmware'e yazılır |
| **Diğer tüm klavyeler** | Logitech, Apple Magic Keyboard, Razer, Corsair, SteelSeries, HyperX… | macOS seviyesinde, **yalnızca o klavyeye** özel tuş eşleme (`hidutil`); klavye her bağlandığında otomatik yeniden uygulanır |

Yöntem markaya göre değil, cihazın sunduğu arayüze göre seçilir: QMK raw HID arayüzü (usage page `0xFF60`) olan her klavye VIA/Vial ile, olmayan her klavye macOS eşlemesiyle düzenlenir. Bu yüzden listede olmayan bir marka da çalışır.

## Özellikler

- **Menü çubuğu**: bağlı klavyeler, bağlantı türü (USB / Bluetooth / BLE), destek türü ve tek tıkla layout (profil) atama.
- **Editör**: klavyenin gerçek fiziksel düzeni (döndürülmüş başparmak tuşları, encoder'lar, layout seçenekleri dahil), katmanlar, tuş seçip yeni işlev atama.
- **Keycode desteği**: temel tuşlar, değiştiriciler, medya, fare, katman tuşları (`MO`, `TG`, `TO`, `TT`, `OSL`, `DF`), mod-tap / home row mod (`LSFT_T(KC_A)`), layer-tap (`LT(1, KC_SPC)`), kombinasyonlar (`LCTL(KC_C)`), makrolar, klavyeye özel keycode'lar (ör. Cornix'in `BT0`, `NEXT_BT`). Eski (QMK < 0.19) ve yeni keycode numaralandırması otomatik algılanır.
- **"Basılı tut" menüsü**: seçili tuşa tek tıkla mod-tap veya layer-tap ekleme.
- **Alfabe düzeni dönüştürme**: QWERTY ⇄ Colemak / Colemak-DH / Dvorak / Workman; home row mod ve layer-tap'ler korunur. macOS seviyesindeki klavyelerde de hazır eşleme olarak kullanılabilir.
- **Profiller**: mevcut düzeni profil olarak kaydedin, menü çubuğundan geri yükleyin. Uygularken yalnızca değişen tuşlar yazılır.
- **İçe / dışa aktarma**: Vial `.vil` (vial.rocks'tan kaydedilen dosyalar), VIA `.json` layout dosyaları ve KeyMapper profilleri.
- **Vial kilidi**: `QK_BOOT` gibi korumalı tuşlar için Vial kilit açma akışı.
- **Aksiyonlar** (Logitech Options+'taki uygulamaya özel ayarlar gibi): bir tuşa uygulama açma, adres/dosya açma, Kestirmeler çalıştırma, kısayol gönderme veya metin yazma atanır; aynı tuş öndeki uygulamaya göre farklı iş yapabilir (ör. Safari'de yeni sekme, VS Code'da komut paleti, diğer her yerde Spotlight). Safari, Chrome, Finder, VS Code, Zoom, Slack ve Photoshop için hazır kısayollar vardır.
- **Girişte başlat** seçeneği.

## Aksiyonlar nasıl çalışır

1. Her aksiyon bir tetik tuşu kullanır: önce F16–F20, sonra F13, en son F14/F15 (macOS F14/F15'i ekran parlaklığı için kullanır). Bu tuşlar normal klavyelerde olmadığı için hiçbir şeyle çakışmaz.
2. Klavye editöründe paletin **Aksiyon** sekmesinden tetik tuşunu fiziksel bir tuşa atayın. VIA/Vial klavyelerde bu firmware'e yazılır; diğer klavyelerde macOS eşlemesi olarak (ör. Caps Lock → F16) uygulanır.
3. KeyMapper tetik tuşunu macOS'un global kısayol API'siyle (Carbon `RegisterEventHotKey`) yakalar; tuş öndeki uygulamaya ulaşmaz. O anda öndeki uygulamanın kuralı varsa o, yoksa varsayılan işlem çalışır.

### Uygulama sekmeleri (Logi Options+ gibi)

Klavye ekranının sağ üstünde **Tüm uygulamalar** ve uygulama simgeleri bulunur; **+** ile uygulama eklenir. Bir uygulama seçiliyken tuşların üstünde o uygulamadaki işlev yazar. Bir tuşa tıklayıp o uygulamanın hazır kısayollarından birini (ör. Photoshop'ta Geri al, Chrome'da Sekme değiştir) veya özel bir aksiyon seçtiğinizde tuş **akıllı tuşa** çevrilir: firmware'e (ya da macOS eşlemesine) bir tetik tuşu yazılır, seçilen uygulamada yeni işlev çalışır, diğer uygulamalarda tuşun eski işlevi (harf, kısayol veya ses/medya tuşu) KeyMapper tarafından aynen gönderilir. Değiştirici ve katman tuşları basılı tutulabilmesi gerektiği için akıllı tuşa çevrilmez.

İzinler: uygulama, adres ve Kestirme açmak **izin gerektirmez**. Kısayol gönderme ve metin yazma macOS **Erişilebilirlik** izni ister; KeyMapper bunu yalnızca bu tür bir aksiyon kullanıldığında sorar. Ad-hoc imzalı derlemelerde macOS bu izni her yeniden derlemede sıfırlayabilir; böyle olursa Sistem Ayarları › Gizlilik ve Güvenlik › Erişilebilirlik'te KeyMapper'ı kaldırıp yeniden ekleyin.

## Kurulum

Gereksinim: macOS 15+, Xcode 16+ (Swift 6 araç zinciri).

```bash
scripts/build-app.sh --install
```

Bu komut `build/KeyMapper.app` dosyasını oluşturur ve `/Applications` içine kopyalar. Sadece derlemek için `--install` olmadan çalıştırın. Uygulama Dock'ta görünmez; menü çubuğundaki klavye simgesinden erişilir. Uygulamayı Finder veya Spotlight'tan tekrar açmak editör penceresini getirir.

Geliştirme sırasında:

```bash
swift run KeyMapper -- --editor
```

```bash
swift test
```

## Komut satırı (`kmctl`)

```bash
swift run kmctl list
```

| Komut | Açıklama |
|---|---|
| `kmctl list` | Bağlı klavyeler |
| `kmctl dump <n> [katman]` | Keymap'i yazdırır |
| `kmctl export <n> <dosya.vil\|dosya.json>` | Vial veya VIA formatında kaydeder |
| `kmctl apply <n> <dosya>` | `.vil` / VIA `.json` / profil dosyasını klavyeye yazar (yalnızca değişen tuşlar) |
| `kmctl remap <n> [hazır\|clear]` | macOS seviyesinde hazır eşleme uygular / kaldırır |
| `kmctl firmware <n>` | Yüklü firmware sürümü ve güncelleme kontrolü (Keychron) |

## vial.rocks'tan layout taşıma

1. vial.rocks'ta klavyenizi açın, **Save current layout** ile `.vil` dosyasını indirin.
2. KeyMapper menüsünde klavyenin altındaki **Layout ata → Dosyadan içe aktar…** ile dosyayı seçin. Dosya profil olarak kaydedilir.
3. Aynı menüden profili seçerek klavyeye yazın.

## Keychron: otomatik tanım ve firmware güncellemeleri

Keychron'un yeni modelleri (ör. Nape Pro trackball, V/Q/K Max serisi) herkese açık VIA deposunda yer almaz; tanımlarını Keychron Launcher dağıtır. KeyMapper Keychron cihazları için tanımı otomatik olarak Keychron Launcher'ın sunucusundan indirir ve önbelleğe alır. Trackball ve fare gibi tuş matrisi olmayan cihazlar da tuşları ve döner düğmesiyle düzenlenebilir.

Firmware: KeyMapper yüklü sürümü cihazdan okur (Keychron'un `0xA1` komutu, yoksa USB sürüm alanı), en yeni sürümü ve sürüm notlarını Keychron'dan alır. Güncelleme varsa cihaz başlığında ve menü çubuğunda turuncu bir uyarı görünür. Yükleme Keychron Launcher ile yapılır; KeyMapper firmware yazmaz. Genel VIA/QMK ve Vial klavyeleri için herkese açık bir güncelleme kaynağı yoktur.

Bu Keychron uç noktaları belgelenmemiştir ve değişebilir; KeyMapper bu durumda sessizce VIA deposuna ve elle tanım yüklemeye geri döner.

## Tanım bulunamazsa

Diğer markaların bazı modelleri (veya 2.4 GHz alıcı üzerinden bağlanan klavyeler) VIA deposunda farklı bir ürün kimliğiyle yer alır. Üreticinin sitesinden modelinize ait VIA JSON dosyasını indirip editörde **Profil → VIA tanım dosyası yükle…** ile ekleyin.

## Bilinen sınırlamalar

- ZMK klavyeler (ZMK Studio protokolü) henüz firmware seviyesinde desteklenmiyor; macOS eşlemesiyle düzenlenebilirler.
- Makro, tap dance, combo ve RGB ayarlarının düzenlenmesi henüz yok (mevcut olanlar korunur).
- Logitech, Razer gibi markaların kendi yazılımlarındaki tuş atamaları (ör. Logi Options+) ayrı çalışır; KeyMapper bunların üzerine macOS seviyesinde eşleme yapar.
- Dahili MacBook klavyesi listelenmez.

## Mimari

```
Sources/
  KeyMapperCore/        Platformdan bağımsız çekirdek (testli)
    HID/                IOHIDManager ile cihaz keşfi, raw HID bağlantısı
    Protocol/           VIA komutları + Vial uzantıları, LZMA (xz) tanım açma
    Definitions/        VIA/Vial tanım ayrıştırma (KLE + derlenmiş VIA), VIA deposu önbelleği
    Keycodes/           QMK keycode tabloları (v5/v6), ifade ayrıştırma/biçimlendirme
    Keymap/             Keymap modeli, klavye oturumu (okuma / fark yazma)
    Profiles/           Profiller, .vil / VIA içe-dışa aktarma, alfabe düzenleri
    OSRemap/            hidutil tabanlı cihaz bazlı macOS eşlemesi
    Brands/             Üretici (VID) veritabanı
  KeyMapper/            SwiftUI menü çubuğu uygulaması + editör
  kmctl/                Komut satırı aracı
```

Veriler `~/Library/Application Support/KeyMapper/` altında tutulur (profiller, VIA tanım önbelleği, kullanıcı tanımları).
