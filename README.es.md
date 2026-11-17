# KeyMapper

[English](README.md) · [Türkçe](README.tr.md) · **Español** · [日本語](README.ja.md) · [简体中文](README.zh-Hans.md)

Un reasignador de teclas universal para macOS que vive en la barra de menús. Elige un teclado conectado y asígnale una distribución (keymap); KeyMapper decide la forma adecuada de editarlo según el firmware del teclado.

## Descarga

**[Descargar KeyMapper para Mac (.dmg)](https://github.com/kocakli/Universal-Keyboard/releases/latest/download/KeyMapper.dmg)** · [todas las versiones](https://github.com/kocakli/Universal-Keyboard/releases)

Requiere un Mac con Apple silicon y macOS 15 o posterior.

1. Abre la imagen de disco descargada y arrastra **KeyMapper** al acceso directo **Applications** (Aplicaciones).
2. Abre KeyMapper desde Aplicaciones. Está firmado y notarizado por Apple, así que se abre sin ningún aviso de seguridad.
3. KeyMapper vive en la barra de menús (icono de teclado) y no tiene icono en el Dock; si vuelves a abrirlo desde el Finder o Spotlight, aparece el editor.

macOS pide permiso de **Bluetooth** la primera vez que se conecta un teclado Bluetooth LE (solo se usa para leer su nivel de batería) y de **Accesibilidad** solo cuando usas una acción que envía una combinación de teclas o escribe texto, o una tecla de letra. Para mostrar el uso de Claude o Cursor hay que aprobar una única vez el acceso al **Llavero**, y solo se solicita después de que hagas clic en **Permitir acceso al llavero** (consulta [Privacidad](#teclados-con-pantalla-leobog-amg65)).

Si prefieres compilarlo tú mismo, consulta [Instalación](#instalación).

| Tipo de teclado | Ejemplos | Cómo se edita |
|---|---|---|
| **Vial** | Cornix, Corne (crkbd), Lily58, Sofle y cualquier teclado que funcione con vial.rocks | La definición se lee del propio teclado (USB o Bluetooth) y el mapa de teclas se escribe en el firmware |
| **VIA / QMK** | Keychron (Q/V/K Pro…), NuPhy, KBDfans, Keebio, DZTech, Glorious GMMK Pro… | La definición se descarga del repositorio de VIA (usevia.app) o de Keychron Launcher, o se carga desde un archivo JSON; el mapa de teclas se escribe en el firmware |
| **Cualquier otro teclado** | Logitech, Apple Magic Keyboard, Razer, Corsair, SteelSeries, HyperX… | Reasignación de teclas a nivel de macOS (`hidutil`) que se aplica **solo a ese teclado** y se vuelve a aplicar cada vez que se conecta |

El método se elige según la interfaz que expone el dispositivo, no según su marca: cualquier teclado con una interfaz raw HID de QMK (usage page `0xFF60`) se edita mediante VIA/Vial, y cualquiera que no la tenga, mediante la reasignación de macOS. Por eso también funcionan marcas que no aparecen en la lista.

## Funciones

- **Barra de menús**: los teclados conectados con su tipo de conexión (USB / Bluetooth / Bluetooth LE), su nivel de batería y su tipo de compatibilidad, y asignación de distribución (perfil) con un clic.
- **Editor**: la distribución física real del teclado (incluidas las teclas de pulgar giradas, los encoders y las opciones de distribución), las capas y la asignación de una nueva función a cualquier tecla.
- **Keycodes**: teclas básicas, modificadores, multimedia, ratón, teclas de capa (`MO`, `TG`, `TO`, `TT`, `OSL`, `DF`), mod-tap / home row mods (`LSFT_T(KC_A)`), layer-tap (`LT(1, KC_SPC)`), combinaciones (`LCTL(KC_C)`), macros y keycodes propios de cada teclado (p. ej., `BT0` y `NEXT_BT` del Cornix). La numeración de keycodes antigua (QMK < 0.19) y la actual se detectan automáticamente.
- **Menú "Al mantener"**: añade mod-tap o layer-tap a la tecla seleccionada con un clic.
- **Conversión de alfabeto**: QWERTY ⇄ Colemak / Colemak-DH / Dvorak / Workman, conservando los home row mods y los layer-taps. KeyMapper recuerda el alfabeto actual de cada capa, así que una capa no se puede convertir dos veces por error, y la última conversión se puede deshacer. También está disponible como reasignación predefinida para los teclados que se reasignan a nivel de macOS.
- **Perfiles**: guarda la distribución actual como perfil y restáurala desde la barra de menús. Solo se escriben las teclas que difieren.
- **Importar / exportar**: `.vil` de Vial (archivos guardados desde vial.rocks), archivos de distribución `.json` de VIA y perfiles de KeyMapper.
- **Desbloqueo de Vial**: el proceso de desbloqueo de Vial para teclas protegidas como `QK_BOOT`.
- **Acciones** (como los ajustes por app de Logitech Options+): haz que una tecla abra una app, abra una URL o un archivo, ejecute un Atajo, envíe una combinación de teclas o escriba texto. La misma tecla puede hacer cosas distintas según la app que esté en primer plano (p. ej., una pestaña nueva en Safari, la paleta de comandos en VS Code y Spotlight en cualquier otro sitio). Los atajos predefinidos cubren unas 30 apps, entre ellas Claude (aprobar / denegar), ChatGPT, Terminal, iTerm2, Warp, Ghostty, Safari, Chrome, Brave, Arc, Firefox, Finder, Mail, Music, VS Code, Cursor, Xcode, Zoom, Teams, Slack, Discord, Notion, Obsidian, Word, Excel, PowerPoint, Photoshop, Final Cut Pro y Spotify. Un atajo como ⌥0 también puede iniciar una acción, desde cualquier teclado.
- **Teclas de letra**: haz que una tecla escriba una letra que la distribución de teclado del Mac no tiene, como las turcas ç ğ ı İ ö ş ü, o ñ, é y ß. Mayús o Bloq Mayús escribe la mayúscula (ı → I, i → İ). Consulta [Teclas de letra](#teclas-de-letra).
- **Nivel de batería**: la carga de los teclados conectados aparece en la barra de menús, en la barra lateral y en la cabecera del editor, en rojo al 20 % o menos. Los teclados de Apple se leen a través de macOS, y los Bluetooth LE (p. ej., el Cornix), mediante el Battery Service estándar de Bluetooth, que pide permiso de Bluetooth la primera vez. En los teclados partidos se muestra la mitad con menos batería. El protocolo raw HID de Keychron no tiene ningún comando de batería, así que un Keychron conectado por USB no muestra la batería.
- **Retroiluminación**: los teclados VIA / Vial que informan de retroiluminación, luz RGB o matriz RGB / LED reciben un botón **Iluminación** con efecto, brillo, velocidad y color, detectados automáticamente. Aún no se ha probado en hardware.
- **Teclados con pantalla**: consulta [más abajo](#teclados-con-pantalla-leobog-amg65).
- Opción **Abrir al iniciar sesión**.
- **Idiomas**: Türkçe, English, Español, 日本語 y 简体中文. De forma predeterminada, la app sigue el idioma de macOS, y puedes cambiarlo al instante desde la barra de menús o desde la barra lateral del editor. `kmctl` usa el mismo ajuste (puedes cambiarlo para un solo comando con `KEYMAPPER_LANG=ja kmctl list`).

## Teclados con pantalla (LEOBOG AMG65)

KeyMapper detecta el LEOBOG AMG65 por su cable USB o por su receptor de 2,4 GHz y muestra una sección **Pantalla e iluminación** encima del mapa de teclas. Sustituye a la app independiente AMG65 Studio: todo funciona dentro de KeyMapper, sin Python, libusb, servidor local ni ningún auxiliar adicional que instalar. El protocolo del teclado se ha portado desde AMG65 Studio (consulta `THIRD_PARTY_NOTICES.md`).

| Grupo | Pestaña | Qué hace | Conexión |
|---|---|---|---|
| Pantalla | IA | La cuota restante de Claude, Codex y Cursor, cada uno activable por separado, leída de las sesiones que ya tienes iniciadas en este Mac (en el caso de Claude, la sesión de la app de escritorio si la hay; si no, la de Claude Code). El seguimiento de actividad opcional muestra qué herramienta se está ejecutando o está esperando aprobación. | — |
| | Pantalla LED | Transmite el uso (resumen, rotativo o tu propio texto, con efectos) a la matriz LED de 63 × 5, con vista previa en directo. | Cable |
| | LCD y reloj | Carga una imagen o un GIF (hasta 130 fotogramas) en la LCD de 240 × 135, mantiene el reloj sincronizado y carga la animación propia de la matriz LED o la animación de arranque. | Cable |
| Iluminación | Efectos | Los 20 efectos integrados de la retroiluminación, con color, brillo, velocidad y dirección. | Cable o 2,4 GHz |
| | Colores de teclas | Pinta las teclas una a una (haz clic o arrastra sobre ellas). | Cable o 2,4 GHz |
| Teclado | Asignación de teclas | La tabla de teclas propia del teclado: teclas con modificadores, teclas multimedia y botones del ratón. Funciona en cualquier ordenador. | Cable o 2,4 GHz |
| | Ajustes | Brillo de la pantalla LED, reposo, activación/desactivación de Fn y modo juego. | Cable |

- **Confirmado en el teclado** (en KeyMapper, o antes en AMG65 Studio): la sincronización del reloj, los efectos Fija y Respiración, la transmisión a la matriz LED y el brillo de la pantalla LED. Los demás efectos, los colores de teclas, las asignaciones multimedia y de ratón, el reposo, la activación/desactivación de Fn, el modo juego y las dos cargas aún no se han probado, y la app lo indica junto a cada uno.
- **Memoria flash**: la imagen de la LCD, la animación LED y la tabla de teclas se escriben en la memoria permanente del teclado, y la app lo indica antes de enviarlas. La primera tabla de teclas que envíes sustituye cualquier asignación guardada por otro software.
- **Seguridad**: si el teclado rechaza un comando o no lo confirma, KeyMapper deja de escribir en él hasta que se desconecta y se vuelve a conectar. **¿Por qué?**, junto al aviso, muestra el paso que falló, la respuesta del teclado y la hora. Mientras AMG65 Studio tiene ocupado el teclado, KeyMapper espera y ofrece **Reintentar**.
- **Privacidad**: el uso solo se lee de las herramientas que actives, en un auxiliar de corta duración (`keymapper-usage`), desde endpoints HTTPS fijos; no se guarda nada salvo las últimas cifras, y nunca se renueva ni se reescribe ninguna sesión. Leer la sesión de la app de escritorio de Claude o de Cursor requiere aprobar una única vez el acceso al Llavero ("Claude Safe Storage", "Cursor Safe Storage"), que solo se solicita cuando haces clic en **Permitir acceso al llavero**. El seguimiento de actividad está desactivado de forma predeterminada. Cuando está activado, lee los eventos de los hooks y los registros de sesión de Codex solo en este Mac. Conectar los hooks de una herramienta escribe en su archivo de configuración (`~/.claude/settings.json`, `~/.codex/hooks.json` o `~/.cursor/hooks.json`) solo cuando haces clic en **Conectar hooks**, guarda una copia de seguridad del archivo anterior y, en el mismo paso, puede tomar el relevo de los hooks de AMG65 Studio.

## Cómo funcionan las acciones

1. Cada acción usa una tecla de activación: primero F16–F20, después F13 y, por último, F14/F15 (macOS usa F14/F15 para el brillo de la pantalla). Los teclados normales no tienen estas teclas, así que no entran en conflicto con nada.
2. En el editor del teclado, selecciona una tecla y elige **Abrir app**, **Abrir dirección / archivo**, **Ejecutar Atajo**, **Enviar combinación de teclas**, **Escribir texto** o **Tecla multimedia / del sistema** directamente en la pestaña **Apps y acciones** de la paleta. KeyMapper reserva una tecla de activación libre, le vincula la acción y la escribe en la tecla (en el firmware en VIA/Vial, como reasignación de macOS en los demás teclados). Las teclas que abren una app muestran su icono; para cambiar la acción de una tecla, usa **Editar acción** en la tarjeta de la tecla seleccionada.
3. KeyMapper captura la tecla de activación mediante la API de atajos globales de macOS (Carbon `RegisterEventHotKey`), así que la tecla nunca llega a la app en primer plano. Si la app en primer plano tiene una regla, se ejecuta esa regla; si no, se ejecuta la acción predeterminada.
4. Una acción también puede iniciarse con un atajo pulsado en cualquier teclado, por ejemplo ⌥0 para **Volumen −** y ⌥9 para **Volumen +**. En **Acciones**, haz clic en la tecla de activación de la acción, elige **Grabar atajo…** y pulsa el atajo. Debe incluir ⌘, ⌥ o ⌃, y la app en primer plano deja de recibirlo (⌥0 ya no escribe º). Si mantienes pulsado un atajo de volumen o brillo, sigue avanzando paso a paso, como las teclas reales. No se escribe nada en el teclado, así que también funciona con el Magic Keyboard; KeyMapper tiene que estar abierto.

### Pestañas por app (como en Logi Options+)

En la parte superior derecha de la vista del teclado aparecen **Todas las apps** y los iconos de las apps; añade una app con **+**. Con una app seleccionada, cada tecla muestra lo que hace en esa app. Si haces clic en una tecla y eliges uno de los atajos predefinidos de esa app (p. ej., Deshacer en Photoshop o Cambiar de pestaña en Chrome) o una acción personalizada, la tecla se convierte en una **tecla inteligente**: se escribe una tecla de activación en el firmware (o en la reasignación de macOS), la nueva función se ejecuta en la app seleccionada y, en todas las demás apps, KeyMapper envía sin cambios la función anterior de la tecla (una letra, un atajo o una tecla de volumen/multimedia). Las teclas modificadoras y de capa deben poder mantenerse pulsadas, así que nunca se convierten en teclas inteligentes.

Permisos: abrir apps, URL y Atajos **no requiere ningún permiso**. Enviar combinaciones de teclas y escribir texto requiere el permiso de **Accesibilidad** de macOS; KeyMapper lo pide solo cuando se usa una acción de ese tipo. Con compilaciones firmadas ad hoc, macOS puede restablecer este permiso tras cada recompilación; si ocurre, quita KeyMapper en Ajustes del Sistema › Privacidad y seguridad › Accesibilidad y vuelve a añadirlo.

## Teclas de letra

En la distribución U.S. ninguna tecla escribe ğ, ş, ö, ü ni İ, y un teclado solo puede enviar teclas, no letras. Para esas letras, KeyMapper escribe la letra por sí mismo:

1. En el editor del teclado, selecciona una tecla y abre la pestaña **Letras** de la paleta. Elige una letra (primero las turcas, luego las de otros idiomas) o escribe cualquier otra y haz clic en **Asignar**. Las letras en uso aparecen al final de la pestaña; quitar una libera su hueco.
2. KeyMapper escribe en la tecla un código reservado: F13 o F16–F20 con ⌃⌥⌘ o ⌃⌥, 12 letras en total. Cuando el teclado envía ese código, KeyMapper lo descarta y escribe la letra en el mismo punto, así que al escribir rápido se mantiene el orden. Mayús o Bloq Mayús escribe la mayúscula, y mantener pulsada la tecla repite la letra.
3. Las teclas de letra necesitan el permiso de **Accesibilidad** (si falta, la pestaña **Letras** ofrece **Dar permiso**) y que KeyMapper esté abierto. Solo funcionan en teclados VIA y Vial, porque la reasignación a nivel de macOS no puede enviar una tecla con modificadores, y no escriben nada en los campos de contraseña, donde macOS oculta las pulsaciones a otras apps.

## Instalación

Requisitos: macOS 15+, Xcode 16+ (toolchain de Swift 6).

```bash
scripts/build-app.sh --install
```

Esto compila `build/KeyMapper.app` y lo copia en `/Applications`. Ejecútalo sin `--install` si solo quieres compilar.

Para generar un paquete instalable (imagen de disco):

```bash
scripts/make-dmg.sh
```

Esto crea `build/KeyMapper-<version>.dmg`; ábrelo y arrastra KeyMapper al acceso directo Aplicaciones. Con `--install`, la app de la imagen de disco se instala directamente en `/Applications` (si hay una copia en ejecución, primero se cierra).

De forma predeterminada, la compilación se firma ad hoc: funciona en el Mac que la compiló, pero macOS bloquea la primera apertura en otro Mac (permítela con **Abrir igualmente** en **Ajustes del Sistema → Privacidad y seguridad**). Para obtener un paquete que se abra en cualquier Mac, fírmalo con un Developer ID y haz que Apple lo notarice:

```bash
xcrun notarytool store-credentials KeyMapper-notary --apple-id "<Apple ID>" --team-id <TEAMID>
```

```bash
SIGN_IDENTITY="Developer ID Application: <Name> (<TEAMID>)" NOTARY_PROFILE=KeyMapper-notary scripts/make-dmg.sh
```

El primer comando solo hace falta una vez; pide una contraseña específica para apps de account.apple.com y la guarda en el llavero. El segundo firma la app, `kmctl` y el auxiliar `keymapper-usage` con el hardened runtime y una marca de tiempo segura, firma la imagen de disco, la envía al servicio de notarización de Apple, espera el resultado (normalmente unos minutos) y adjunta (staple) el ticket a la imagen de disco. Si Apple la rechaza, el script muestra el registro de notarización y se detiene. Una firma Developer ID también conserva los permisos de Accesibilidad, Bluetooth y Llavero entre compilaciones.

La app no aparece en el Dock; usa el icono de teclado de la barra de menús. Si vuelves a abrir la app desde el Finder o Spotlight, aparece la ventana del editor.

Durante el desarrollo:

```bash
swift run KeyMapper -- --editor
```

```bash
swift test
```

## Línea de comandos (`kmctl`)

```bash
swift run kmctl list
```

| Comando | Descripción |
|---|---|
| `kmctl list` | Teclados conectados, con el nivel de batería cuando macOS lo proporciona |
| `kmctl dump <n> [layer]` | Muestra el mapa de teclas (y, en Keychron, la capa en la que está escribiendo el teclado) |
| `kmctl export <n> <file.vil\|file.json>` | Guarda el mapa de teclas en formato Vial o VIA |
| `kmctl apply <n> <file>` | Escribe en el teclado un archivo `.vil` / `.json` de VIA / de perfil (solo las teclas que difieren) |
| `kmctl remap <n> [preset\|clear]` | Aplica o quita una reasignación predefinida a nivel de macOS |
| `kmctl firmware <n>` | Versión de firmware instalada y comprobación de actualizaciones (Keychron) |

## Traer una distribución desde vial.rocks

1. Abre tu teclado en vial.rocks y descarga el archivo `.vil` con **Save current layout**.
2. En el menú de KeyMapper, en la fila **Distribución** del teclado, haz clic en **+** y elige **Importar desde archivo (.vil / .json de VIA)…**. El archivo se guarda como perfil.
3. Selecciona el perfil en esa misma fila para escribirlo en el teclado.

## Keychron: definiciones automáticas, capas y actualizaciones de firmware

Los modelos más recientes de Keychron (p. ej., el trackball Nape Pro y las series V/Q/K Max) no están en el repositorio público de VIA; sus definiciones las distribuye Keychron Launcher. Para los dispositivos Keychron, KeyMapper descarga automáticamente la definición del servidor de Keychron Launcher y la guarda en caché. También se pueden editar dispositivos sin matriz de teclas, como trackballs y ratones, incluidos sus botones y su perilla.

Capas: KeyMapper lee el protocolo de Launcher de Keychron (tanto en la familia de firmware QMK como en la ZMK) para saber en qué capa está escribiendo el teclado, sigue los cambios de capa que notifica el teclado y abre el editor en esa capa. Esto es importante porque una tecla escrita en otra capa parece no hacer nada; el Nape Pro, por ejemplo, escribe en la capa 1.

Firmware: KeyMapper lee la versión instalada del dispositivo (con el comando `0xA1` de Keychron o el campo de versión USB) y obtiene de Keychron la última versión y sus notas de la versión. Cuando hay una actualización disponible, aparece un aviso naranja en la cabecera del dispositivo y en la barra de menús. Las actualizaciones se instalan con Keychron Launcher; KeyMapper nunca escribe firmware. No hay ninguna fuente pública de actualizaciones para los teclados VIA/QMK y Vial genéricos.

Estos endpoints de Keychron no están documentados y pueden cambiar; si cambian, KeyMapper recurre discretamente al repositorio de VIA y a las definiciones cargadas manualmente.

## Si no se encuentra ninguna definición

Algunos modelos de otras marcas (o teclados conectados mediante un receptor de 2,4 GHz) figuran en el repositorio de VIA con otro ID de producto. Descarga el archivo JSON de VIA de tu modelo desde la web del fabricante y añádelo en el editor con **Perfil → Cargar archivo de definición de VIA…**.

## Limitaciones conocidas

- Los teclados que solo hablan el protocolo de ZMK Studio todavía no son compatibles a nivel de firmware; se pueden editar con la reasignación de macOS. (El firmware ZMK de Keychron habla VIA y sí es compatible.)
- Las macros, el tap dance y los combos aún no se pueden editar (los existentes se conservan).
- Las asignaciones de teclas hechas con software de otras marcas (p. ej., Logi Options+) funcionan por separado; KeyMapper reasigna por encima de ellas a nivel de macOS.
- El teclado integrado del MacBook no aparece en la lista.

## Arquitectura

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
    Actions/            Trigger keys, action bindings, letter keys and per-app presets
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

El icono se genera a partir de `Resources/AppIcon.icon` con `actool` durante la compilación: `Assets.car` para macOS 26 y posteriores (el sistema deriva automáticamente los estilos de icono claro, oscuro, tintado y transparente) y `AppIcon.icns` para versiones anteriores de macOS. El documento se puede abrir y editar en Icon Composer, que se incluye con Xcode.

Las traducciones están en `Sources/KeyMapperCore/Localization/`: en el código fuente, los textos de la interfaz se escriben en turco y se marcan con `L("…")`, y el diccionario de cada idioma usa esos textos en turco como claves. Los tests comprueban que cada texto marcado esté traducido en todos los idiomas con los mismos marcadores de posición (`%@`). Este README se traduce de la misma manera: `README.tr.md`, `README.es.md`, `README.ja.md` y `README.zh-Hans.md` siguen sección por sección el README en inglés, así que cualquier cambio en él se traslada a los cinco.

Los datos se guardan en `~/Library/Application Support/KeyMapper/` (perfiles, la caché de definiciones de VIA y las definiciones del usuario).

## Licencia

KeyMapper se publica bajo la [licencia MIT](LICENSE). El código en el que se basa figura, con sus propias licencias, en [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
