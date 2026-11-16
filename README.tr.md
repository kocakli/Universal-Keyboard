# KeyMapper

[English](README.md) · **Türkçe** · [Español](README.es.md) · [日本語](README.ja.md) · [简体中文](README.zh-Hans.md)

macOS için menü çubuğunda çalışan evrensel bir klavye eşleme aracı. Bağlı bir klavyeyi seçip ona bir layout (keymap) atayın; KeyMapper, klavyeyi düzenlemenin doğru yolunu firmware'ine bakarak seçer.

## İndirme

**[KeyMapper'ı Mac için indirin (.dmg)](https://github.com/kocakli/Universal-Keyboard/releases/latest/download/KeyMapper.dmg)** · [tüm sürümler](https://github.com/kocakli/Universal-Keyboard/releases)

Apple silicon işlemcili bir Mac ve macOS 15 ya da üstü gerekir.

1. İndirilen disk görüntüsünü açın ve **KeyMapper** uygulamasını **Applications** (Uygulamalar) kısayolunun üzerine sürükleyin.
2. KeyMapper'ı Uygulamalar klasöründen açın. Apple tarafından imzalanmış ve onaylanmış (notarize) olduğu için güvenlik uyarısı olmadan açılır.
3. KeyMapper menü çubuğunda (klavye simgesi) çalışır ve Dock'ta simgesi yoktur; Finder'dan ya da Spotlight'tan yeniden açtığınızda editör açılır.

macOS, bir Bluetooth LE klavye ilk kez bağlandığında **Bluetooth** izni (yalnızca pil seviyesini okumak için kullanılır), yalnızca tuş kombinasyonu gönderen ya da metin yazan bir aksiyon kullandığınızda da **Erişilebilirlik** izni ister. Claude veya Cursor kullanımını göstermek için bir kerelik **Anahtar Zinciri** onayı gerekir; bu onay yalnızca **Anahtar Zinciri'ne izin ver** düğmesine tıkladıktan sonra istenir (bkz. [Gizlilik](#ekranlı-klavyeler-leobog-amg65)).

Uygulamayı kendiniz derlemek isterseniz [Kurulum](#kurulum) bölümüne bakın.

| Klavye türü | Örnekler | Nasıl düzenlenir |
|---|---|---|
| **Vial** | Cornix, Corne (crkbd), Lily58, Sofle ve vial.rocks ile çalışan tüm klavyeler | Tanım klavyenin kendisinden okunur (USB veya Bluetooth), keymap firmware'e yazılır |
| **VIA / QMK** | Keychron (Q/V/K Pro…), NuPhy, KBDfans, Keebio, DZTech, Glorious GMMK Pro… | Tanım VIA deposundan (usevia.app) ya da Keychron Launcher'dan indirilir veya bir JSON dosyasından yüklenir; keymap firmware'e yazılır |
| **Diğer tüm klavyeler** | Logitech, Apple Magic Keyboard, Razer, Corsair, SteelSeries, HyperX… | macOS seviyesinde (`hidutil`) tuş eşleme; **yalnızca o klavyeye** uygulanır ve klavye her bağlandığında yeniden uygulanır |

Yöntem markaya göre değil, cihazın sunduğu arayüze göre seçilir: QMK raw HID arayüzü (usage page `0xFF60`) olan her klavye VIA/Vial üzerinden, olmayan her klavye ise macOS eşlemesiyle düzenlenir. Listede olmayan markaların da çalışmasının nedeni budur.

## Özellikler

- **Menü çubuğu**: bağlantı türü (USB / Bluetooth / Bluetooth LE), pil seviyesi ve destek türüyle birlikte bağlı klavyeler; tek tıkla layout (profil) atama.
- **Editör**: klavyenin gerçek fiziksel düzeni (döndürülmüş başparmak tuşları, encoder'lar ve layout seçenekleri dahil), katmanlar ve herhangi bir tuşa yeni bir işlev atama.
- **Keycode'lar**: temel tuşlar, değiştiriciler, medya, fare, katman tuşları (`MO`, `TG`, `TO`, `TT`, `OSL`, `DF`), mod-tap / home-row mod'lar (`LSFT_T(KC_A)`), layer-tap (`LT(1, KC_SPC)`), kombinasyonlar (`LCTL(KC_C)`), makrolar ve klavyeye özel keycode'lar (ör. Cornix'teki `BT0`, `NEXT_BT`). Eski (QMK < 0.19) ve güncel keycode numaralandırması otomatik olarak algılanır.
- **"Basılı tutunca" menüsü**: seçili tuşa tek tıkla mod-tap veya layer-tap ekleyin.
- **Alfabe dönüşümü**: QWERTY ⇄ Colemak / Colemak-DH / Dvorak / Workman; home-row mod'lar ve layer-tap'ler korunur. KeyMapper her katmanın mevcut alfabesini hatırlar; böylece bir katman yanlışlıkla iki kez dönüştürülemez ve son dönüşüm geri alınabilir. macOS seviyesinde düzenlenen klavyeler için hazır bir eşleme olarak da sunulur.
- **Profiller**: mevcut layout'u profil olarak kaydedin ve menü çubuğundan geri yükleyin. Yalnızca farklı olan tuşlar yazılır.
- **İçe / dışa aktarma**: Vial `.vil` (vial.rocks'tan kaydedilen dosyalar), VIA `.json` layout dosyaları ve KeyMapper profilleri.
- **Vial kilidini açma**: `QK_BOOT` gibi korumalı tuşlar için Vial'in kilit açma akışı.
- **Aksiyonlar** (Logitech Options+'taki uygulamaya özel ayarlar gibi): bir tuşa uygulama açma, adres ya da dosya açma, kestirme çalıştırma, tuş kombinasyonu gönderme veya metin yazma görevi atayın. Aynı tuş, öndeki uygulamaya göre farklı işler yapabilir (ör. Safari'de yeni sekme, VS Code'da komut paleti, diğer her yerde Spotlight). Hazır kısayollar, aralarında Claude (onayla / reddet), ChatGPT, Terminal, iTerm2, Warp, Ghostty, Safari, Chrome, Brave, Arc, Firefox, Finder, Mail, Music, VS Code, Cursor, Xcode, Zoom, Teams, Slack, Discord, Notion, Obsidian, Word, Excel, PowerPoint, Photoshop, Final Cut Pro ve Spotify'ın da bulunduğu yaklaşık 30 uygulamayı kapsar.
- **Pil seviyesi**: bağlı klavyelerin şarjı menü çubuğunda, kenar çubuğunda ve editör başlığında görünür; %20 ve altında kırmızıyla gösterilir. Apple klavyeleri macOS üzerinden, Bluetooth LE klavyeler (ör. Cornix) ise standart Bluetooth Battery Service üzerinden okunur; bu, ilk seferde Bluetooth izni ister. Split klavyelerde şarjı daha düşük olan yarı gösterilir. Keychron'un raw HID protokolünde pil komutu olmadığından USB ile bağlı bir Keychron'da pil seviyesi görünmez.
- **Arka ışık**: arka ışık, RGB ışık ya da RGB / LED matris bildiren VIA / Vial klavyelerde efekt, parlaklık, hız ve renk ayarlarını içeren bir **Işıklar** düğmesi çıkar; ışık desteği otomatik olarak algılanır. Henüz donanımda denenmedi.
- **Ekranlı klavyeler**: [aşağıya](#ekranlı-klavyeler-leobog-amg65) bakın.
- **Girişte başlat** seçeneği.
- **Diller**: Türkçe, English, Español, 日本語 ve 简体中文. Uygulama varsayılan olarak macOS dilini izler; dil, menü çubuğundan ya da editörün kenar çubuğundan anında değiştirilebilir. `kmctl` de aynı ayarı kullanır (tek bir komut için `KEYMAPPER_LANG=ja kmctl list` ile geçersiz kılabilirsiniz).

## Ekranlı klavyeler (LEOBOG AMG65)

KeyMapper, LEOBOG AMG65'i USB kablosu ya da 2.4 GHz alıcısı üzerinden algılar ve keymap'in üstünde bir **Ekran ve ışık** bölümü gösterir. Ayrı AMG65 Studio uygulamasının yerini alır: her şey KeyMapper içinde çalışır; Python, libusb, yerel sunucu ya da ek bir yardımcı program kurmanız gerekmez. Klavyenin protokolü AMG65 Studio'dan aktarıldı (bkz. `THIRD_PARTY_NOTICES.md`).

| Grup | Sekme | Ne yapar | Bağlantı |
|---|---|---|---|
| Ekran | Yapay zekâ | Claude, Codex ve Cursor'da kalan kullanım hakkı; her biri ayrı ayrı açılır ve bu Mac'te zaten açık olan oturumlarınızdan okunur (Claude için, varsa masaüstü uygulamasının oturumu, yoksa Claude Code'unki). İsteğe bağlı etkinlik takibi, hangi aracın çalıştığını ya da onay beklediğini gösterir. | — |
| | LED ekran | Kullanımı (genel bakış, dönüşümlü gösterim ya da kendi metniniz; efektlerle) 63 × 5 LED matrise sürekli olarak gönderir; canlı önizlemesi de vardır. | Kablo |
| | LCD ve saat | 240 × 135 LCD'ye resim ya da GIF (en çok 130 kare) yükler, saati eşitlenmiş tutar ve LED matrisin kendi animasyonunu ya da açılış animasyonunu yükler. | Kablo |
| Işık | Efektler | Arka ışığın renk, parlaklık, hız ve yön ayarlı 20 yerleşik efekti. | Kablo veya 2.4 GHz |
| | Tuş renkleri | Tuşları tek tek boyar (tıklayın ya da tuşların üzerinde sürükleyin). | Kablo veya 2.4 GHz |
| Klavye | Tuş atamaları | Klavyenin kendi tuş tablosu: değiştiricili tuşlar, medya tuşları ve fare düğmeleri. Her bilgisayarda çalışır. | Kablo veya 2.4 GHz |
| | Ayarlar | LED ekran parlaklığı, uyku, Fn aç/kapa ve oyun modu. | Kablo |

- **Klavyede çalıştığı doğrulananlar** (KeyMapper'da ya da daha önce AMG65 Studio'da): saat eşitleme, Sabit ve Nefes efektleri, LED matris akışı ve LED ekran parlaklığı. Diğer efektler, tuş renkleri, medya ve fare atamaları, uyku, Fn aç/kapa, oyun modu ve iki yükleme de henüz denenmedi; uygulama bunu her birinin yanında belirtir.
- **Flash bellek**: LCD resmi, LED animasyonu ve tuş tablosu klavyenin kalıcı belleğine yazılır ve uygulama bunu siz göndermeden önce belirtir. Gönderilen ilk tuş tablosu, başka yazılımlarla kaydedilmiş atamaların yerini alır.
- **Güvenlik**: klavye bir komutu reddederse ya da onaylamazsa KeyMapper, klavye çıkarılıp yeniden takılana kadar ona yazmayı durdurur. Uyarının yanındaki **Neden?** başarısız adımı, klavyenin yanıtını ve zamanı gösterir. Klavye AMG65 Studio tarafından kullanılırken KeyMapper bekler ve **Tekrar dene** seçeneğini sunar.
- **Gizlilik**: kullanım yalnızca açtığınız araçlar için, kısa ömürlü bir yardımcı programda (`keymapper-usage`), sabit HTTPS uç noktalarından okunur; en son sayılar dışında hiçbir şey saklanmaz ve hiçbir oturum yenilenmez ya da geri yazılmaz. Claude masaüstü uygulamasının ya da Cursor'ın oturumunu okumak için bir kerelik Anahtar Zinciri onayı ("Claude Safe Storage", "Cursor Safe Storage") gerekir ve bu onay yalnızca siz **Anahtar Zinciri'ne izin ver** düğmesine tıkladığınızda istenir. Etkinlik takibi varsayılan olarak kapalıdır. Açıkken kanca olaylarını ve Codex'in oturum kayıtlarını yalnızca bu Mac'te okur. Bir aracın kancalarını bağlamak, aracın ayar dosyasına (`~/.claude/settings.json`, `~/.codex/hooks.json` veya `~/.cursor/hooks.json`) yalnızca **Kancaları bağla** düğmesine tıkladığınızda yazar, önceki dosyanın yedeğini alır ve aynı adımda AMG65 Studio'nun kancalarını devralabilir.

## Aksiyonlar nasıl çalışır

1. Her aksiyon bir tetik tuşu kullanır: önce F16–F20, sonra F13, en son da F14/F15 (macOS, F14/F15'i ekran parlaklığı için kullanır). Normal klavyelerde bu tuşlar olmadığından hiçbir şeyle çakışmazlar.
2. Klavye editöründe bir tuş seçin ve paletin **Uygulama ve aksiyon** sekmesinden doğrudan **Uygulama aç**, **Adres / dosya aç**, **Kestirme çalıştır**, **Tuş kombinasyonu gönder**, **Metin yaz** ya da **Medya / sistem tuşu** seçeneğini seçin. KeyMapper boş bir tetik tuşu ayırır, aksiyonu ona bağlar ve tuşa yazar (VIA/Vial'de firmware'e, diğer klavyelerde macOS eşlemesi olarak). Uygulama açan tuşlarda uygulamanın simgesi görünür; bir tuşun aksiyonunu, seçili tuşun kartındaki **Aksiyonu düzenle** ile değiştirebilirsiniz.
3. KeyMapper tetik tuşunu macOS'un global kısayol tuşu API'siyle (Carbon `RegisterEventHotKey`) yakalar; böylece tuş öndeki uygulamaya hiç ulaşmaz. Öndeki uygulama için bir kural varsa o kural, yoksa varsayılan aksiyon çalışır.

### Uygulama sekmeleri (Logi Options+ gibi)

Klavye görünümünün sağ üstünde **Tüm uygulamalar** ve uygulama simgeleri yer alır; **+** ile uygulama ekleyin. Bir uygulama seçiliyken her tuş, o uygulamada ne yaptığını gösterir. Bir tuşa tıklayıp o uygulamanın hazır kısayollarından birini (ör. Photoshop'ta Geri al, Chrome'da Sekme değiştir) ya da özel bir aksiyonu seçtiğinizde tuş bir **akıllı tuş** hâline gelir: firmware'e (ya da macOS eşlemesine) bir tetik tuşu yazılır, yeni işlev seçili uygulamada çalışır, diğer tüm uygulamalarda ise KeyMapper tuşun önceki işlevini (bir harf, bir kısayol ya da bir ses/medya tuşu) olduğu gibi gönderir. Değiştirici ve katman tuşlarının basılı tutulabilmesi gerektiği için bunlar hiçbir zaman akıllı tuşa çevrilmez.

İzinler: uygulama ve adres açmak ya da kestirme çalıştırmak **izin gerektirmez**. Tuş kombinasyonu göndermek ve metin yazmak macOS'un **Erişilebilirlik** iznini gerektirir; KeyMapper bu izni yalnızca böyle bir aksiyon kullanıldığında ister. Ad-hoc imzalı derlemelerde macOS bu izni her yeniden derlemeden sonra sıfırlayabilir; böyle olursa KeyMapper'ı Sistem Ayarları › Gizlilik ve Güvenlik › Erişilebilirlik'ten kaldırıp yeniden ekleyin.

## Kurulum

Gereksinimler: macOS 15+, Xcode 16+ (Swift 6 araç zinciri).

```bash
scripts/build-app.sh --install
```

Bu komut `build/KeyMapper.app` uygulamasını derler ve `/Applications` klasörüne kopyalar. Yalnızca derlemek için `--install` olmadan çalıştırın.

Kurulabilir bir paket (disk görüntüsü) oluşturmak için:

```bash
scripts/make-dmg.sh
```

Bu komut `build/KeyMapper-<version>.dmg` dosyasını oluşturur; dosyayı açıp KeyMapper'ı Uygulamalar kısayolunun üzerine sürükleyin. `--install` ile disk görüntüsündeki uygulama doğrudan `/Applications` klasörüne kurulur (çalışan bir kopya varsa önce kapatılır).

Varsayılan olarak derleme ad-hoc imzalanır: derlendiği Mac'te çalışır, ancak başka bir Mac'te macOS ilk açılışı engeller (**Sistem Ayarları → Gizlilik ve Güvenlik** bölümündeki **Yine de Aç** ile izin verin). Her yerde açılan bir paket için uygulamayı Developer ID ile imzalayıp Apple'a onaylatın (notarize):

```bash
xcrun notarytool store-credentials KeyMapper-notary --apple-id "<Apple ID>" --team-id <TEAMID>
```

```bash
SIGN_IDENTITY="Developer ID Application: <Name> (<TEAMID>)" NOTARY_PROFILE=KeyMapper-notary scripts/make-dmg.sh
```

İlk komut yalnızca bir kez gerekir; account.apple.com'dan alınan uygulamaya özel bir parolayı ister ve anahtar zincirine kaydeder. İkincisi uygulamayı, `kmctl` aracını ve `keymapper-usage` yardımcı programını hardened runtime ve güvenli zaman damgasıyla imzalar, disk görüntüsünü imzalar, Apple'ın onay (notary) servisine gönderir, sonucu bekler (genellikle birkaç dakika) ve onay biletini disk görüntüsüne iliştirir (staple). Apple reddederse betik notary günlüğünü yazdırır ve durur. Developer ID imzası ayrıca Erişilebilirlik, Bluetooth ve Anahtar Zinciri izinlerinin yeniden derlemelerde korunmasını sağlar.

Uygulama Dock'ta görünmez; menü çubuğundaki klavye simgesini kullanın. Uygulamayı Finder'dan ya da Spotlight'tan yeniden açtığınızda editör penceresi açılır.

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
| `kmctl list` | Bağlı klavyeler; macOS bildiriyorsa pil seviyesiyle birlikte |
| `kmctl dump <n> [layer]` | Keymap'i yazdırır (Keychron'da klavyenin o an yazdığı katmanı da) |
| `kmctl export <n> <file.vil\|file.json>` | Keymap'i Vial veya VIA biçiminde kaydeder |
| `kmctl apply <n> <file>` | Bir `.vil` / VIA `.json` / profil dosyasını klavyeye yazar (yalnızca farklı olan tuşları) |
| `kmctl remap <n> [preset\|clear]` | Hazır bir macOS seviyesi eşlemeyi uygular ya da kaldırır |
| `kmctl firmware <n>` | Yüklü firmware sürümü ve güncelleme denetimi (Keychron) |

## Layout'u vial.rocks'tan taşıma

1. Klavyenizi vial.rocks'ta açın ve **Save current layout** ile `.vil` dosyasını indirin.
2. KeyMapper menüsünde, klavyenin **Layout** satırında **+** düğmesine tıklayın ve **Dosyadan içe aktar (.vil / VIA .json)…** seçeneğini seçin. Dosya bir profil olarak kaydedilir.
3. Profili klavyeye yazmak için aynı satırda onu seçin.

## Keychron: otomatik tanımlar, katmanlar ve firmware güncellemeleri

Yeni Keychron modelleri (ör. Nape Pro trackball ve V/Q/K Max serisi) herkese açık VIA deposunda yer almaz; tanımlarını Keychron Launcher dağıtır. KeyMapper, Keychron cihazlarının tanımını Keychron Launcher'ın sunucusundan otomatik olarak indirir ve önbelleğe alır. Trackball ve fare gibi tuş matrisi olmayan cihazlar da düğmeleri ve döner düğmesi dahil düzenlenebilir.

Katmanlar: KeyMapper, klavyenin hangi katmanda yazdığını öğrenmek için Keychron'un Launcher protokolünü (hem QMK hem ZMK firmware aileleri) okur, klavyenin bildirdiği katman değişikliklerini izler ve editörü o katmanda açar. Bu önemlidir, çünkü başka bir katmana yazılan tuş hiçbir şey yapmıyormuş gibi görünür; örneğin Nape Pro 1. katmanda yazar.

Firmware: KeyMapper yüklü sürümü cihazdan (Keychron'un `0xA1` komutuyla ya da USB sürüm alanından) okur, en son sürümü ve sürüm notlarını Keychron'dan alır. Güncelleme varsa cihaz başlığında ve menü çubuğunda turuncu bir uyarı görünür. Güncellemeler Keychron Launcher ile yüklenir; KeyMapper hiçbir zaman firmware yazmaz. Genel VIA/QMK ve Vial klavyeler için herkese açık bir güncelleme kaynağı yoktur.

Bu Keychron uç noktaları belgelenmemiştir ve değişebilir; değişirlerse KeyMapper sessizce VIA deposuna ve elle yüklenen tanımlara geri döner.

## Tanım bulunamazsa

Diğer markaların bazı modelleri (ya da 2.4 GHz alıcıyla bağlanan klavyeler) VIA deposunda farklı bir ürün kimliğiyle (product ID) listelenir. Modelinizin VIA JSON dosyasını üreticinin sitesinden indirin ve editörde **Profil → VIA tanım dosyası yükle…** ile ekleyin.

## Bilinen sınırlamalar

- Yalnızca ZMK Studio protokolünü kullanan klavyeler henüz firmware seviyesinde desteklenmiyor; bunlar macOS eşlemesiyle düzenlenebilir. (Keychron'un ZMK firmware'i VIA protokolünü kullanır ve desteklenir.)
- Makrolar, tap dance ve combo'lar henüz düzenlenemiyor (mevcut olanlar korunur).
- Diğer markaların yazılımlarında (ör. Logi Options+) yapılan tuş atamaları ayrı çalışır; KeyMapper bunların üzerine macOS seviyesinde eşleme yapar.
- MacBook'un dahili klavyesi listelenmez.

## Mimari

```
Sources/
  KeyMapperCore/        Platform-independent core (tested)
    HID/                Device discovery with IOHIDManager, raw HID connection, battery levels
    Protocol/           VIA commands + Vial extensions, Keychron Launcher protocol, LZMA (xz) definition decoding
    Definitions/        VIA/Vial definition parsing (KLE + compiled VIA), VIA repository cache
    Keycodes/           QMK keycode tables (v5/v6), expression parsing/formatting
    Keymap/             Keymap model, keyboard session (read / write differences)
    Profiles/           Profiles, .vil / VIA import-export, alphabet layouts
    OSRemap/            Per-device macOS remapping based on hidutil
    Brands/             Manufacturer (VID) database
    Actions/            Trigger keys, action bindings and per-app presets
    Localization/       UI translations
    Lighting/           VIA / Vial backlight and RGB lighting
    ScreenKeyboards/    LEOBOG AMG65: protocol, uploads (IOUSBHost), key layout, LED matrix renderer
  KeyMapperUsage/       AI tool usage and activity (providers, hook config, Codex log reader)
  KeyMapper/            SwiftUI menu bar app + editor
  keymapper-usage/      Helper that reads usage and receives tool hooks
  kmctl/                Command line tool
Resources/
  AppIcon.icon/         App icon (Icon Composer document; Liquid Glass)
  Glyph.png             Transparent glyph: in-app logo and menu bar icon
```

Simge, derleme sırasında `actool` ile `Resources/AppIcon.icon` dosyasından üretilir: macOS 26 ve sonrası için `Assets.car` (sistem açık, koyu, renklendirilmiş ve şeffaf simge stillerini otomatik olarak türetir), daha eski macOS sürümleri için `AppIcon.icns`. Belge, Xcode ile birlikte gelen Icon Composer'da açılıp düzenlenebilir.

Çeviriler `Sources/KeyMapperCore/Localization/` altındadır: arayüz metinleri kaynak kodda Türkçe yazılır ve `L("…")` ile işaretlenir; her dilin sözlüğü bu Türkçe metinleri anahtar olarak kullanır. Testler, işaretlenen her metnin her dilde aynı yer tutucularla (`%@`) çevrildiğini denetler. Bu README de aynı şekilde çevrilir: `README.tr.md`, `README.es.md`, `README.ja.md` ve `README.zh-Hans.md`, İngilizce README'yi bölüm bölüm izler; bu yüzden oradaki bir değişiklik beş dosyanın hepsine işlenir.

Veriler `~/Library/Application Support/KeyMapper/` klasöründe saklanır (profiller, VIA tanım önbelleği ve kullanıcı tanımları).

## Lisans

KeyMapper [MIT Lisansı](LICENSE) ile yayımlanmaktadır. Üzerine kurulduğu kodlar, kendi lisanslarıyla birlikte [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) dosyasında listelenir.
