# KeyMapper

[English](README.md) · [Türkçe](README.tr.md) · [Español](README.es.md) · [日本語](README.ja.md) · **简体中文**

一款常驻菜单栏的 macOS 通用键盘映射工具。选择一把已连接的键盘并为其分配布局（键位映射），KeyMapper 会根据键盘的固件选择合适的编辑方式。

## 下载

**[下载 Mac 版 KeyMapper (.dmg)](https://github.com/kocakli/Universal-Keyboard/releases/latest/download/KeyMapper.dmg)** · [所有版本](https://github.com/kocakli/Universal-Keyboard/releases)

需要搭载 Apple 芯片、运行 macOS 15 或更高版本的 Mac。

1. 打开下载的磁盘映像，将 **KeyMapper** 拖到 **Applications**（应用程序）快捷方式上。
2. 从“应用程序”文件夹打开 KeyMapper。它已签名并经过 Apple 公证，因此打开时不会出现安全警告。
3. KeyMapper 常驻菜单栏（键盘图标），没有程序坞图标；从访达或 Spotlight 再次打开它会调出编辑器。

首次连接 Bluetooth LE 键盘时，macOS 会请求**蓝牙**权限（仅用于读取其电量）；只有当你使用发送组合键或输入文本的操作或字母键时，才会请求**辅助功能**权限。显示 Claude 或 Cursor 的用量需要一次性的**钥匙串**授权，且只有在你点按**允许钥匙串访问**之后才会请求（参见[隐私](#带屏幕的键盘-leobog-amg65)）。

如果想自行构建，请参见[安装](#安装)。

| 键盘类型 | 示例 | 编辑方式 |
|---|---|---|
| **Vial** | Cornix、Corne (crkbd)、Lily58、Sofle，以及所有可在 vial.rocks 上使用的键盘 | 从键盘本身（USB 或蓝牙）读取定义，并将键位映射写入固件 |
| **VIA / QMK** | Keychron (Q/V/K Pro…)、NuPhy、KBDfans、Keebio、DZTech、Glorious GMMK Pro… | 从 VIA 仓库 (usevia.app) 或 Keychron Launcher 下载定义，或从 JSON 文件载入；键位映射写入固件 |
| **其他所有键盘** | Logitech、Apple Magic Keyboard、Razer、Corsair、SteelSeries、HyperX… | 在 macOS 层面进行按键重映射（`hidutil`），**仅对该键盘生效**，并在每次连接时重新应用 |

编辑方式取决于设备提供的接口，而不是品牌：凡是带有 QMK raw HID 接口（usage page `0xFF60`）的键盘都通过 VIA/Vial 编辑，没有该接口的键盘则通过 macOS 重映射编辑。因此，未列出的品牌同样可以使用。

## 功能

- **菜单栏**：显示已连接的键盘及其连接方式（USB / 蓝牙 / Bluetooth LE）、电量和支持类型，并可一键分配布局（配置文件）。
- **编辑器**：呈现键盘真实的物理布局（包括旋转的拇指键、旋钮和布局选项）和各个层，可为任意按键分配新功能。
- **键码**：基本按键、修饰键、媒体键、鼠标键、层键（`MO`、`TG`、`TO`、`TT`、`OSL`、`DF`）、mod-tap / home row mods（`LSFT_T(KC_A)`）、layer-tap（`LT(1, KC_SPC)`）、组合键（`LCTL(KC_C)`）、宏以及键盘专属键码（例如 Cornix 的 `BT0`、`NEXT_BT`）。旧版（QMK < 0.19）和当前的键码编号均可自动识别。
- **“按住时”菜单**：一键为所选按键添加 mod-tap 或 layer-tap。
- **字母布局转换**：QWERTY ⇄ Colemak / Colemak-DH / Dvorak / Workman，转换时保留 home row mods 和 layer-tap。KeyMapper 会记住每一层当前的字母布局，因此不会误将同一层转换两次，并且可以撤销上一次转换。对于通过 macOS 重映射的键盘，也提供对应的现成重映射。
- **配置文件**：将当前布局保存为配置文件，并可从菜单栏恢复。只写入有差异的按键。
- **导入 / 导出**：支持 Vial `.vil`（从 vial.rocks 保存的文件）、VIA `.json` 布局文件以及 KeyMapper 配置文件。
- **Vial 解锁**：针对 `QK_BOOT` 等受保护按键的 Vial 解锁流程。
- **操作**（类似 Logitech Options+ 中按 App 区分的设置）：可将按键设为打开 App、打开网址或文件、运行快捷指令、发送组合键或输入文本。同一个按键可以根据前台 App 执行不同的操作（例如在 Safari 中新建标签页，在 VS Code 中打开命令面板，在其他任何地方打开 Spotlight）。现成的快捷键覆盖约 30 款 App，包括 Claude（批准 / 拒绝）、ChatGPT、Terminal、iTerm2、Warp、Ghostty、Safari、Chrome、Brave、Arc、Firefox、Finder、Mail、Music、VS Code、Cursor、Xcode、Zoom、Teams、Slack、Discord、Notion、Obsidian、Word、Excel、PowerPoint、Photoshop、Final Cut Pro 和 Spotify。
- **字母键**：让某个按键输入 Mac 键盘布局中没有的字母，例如土耳其语的 ç ğ ı İ ö ş ü，或 ñ、é 和 ß。按 Shift 或大写锁定输入大写字母（ı → I，i → İ）。参见[字母键](#字母键)。
- **电量**：已连接键盘的电量会显示在菜单栏、边栏和编辑器顶部，电量在 20% 及以下时显示为红色。Apple 键盘的电量通过 macOS 读取，Bluetooth LE 键盘（例如 Cornix）则通过标准的蓝牙电池服务（Battery Service）读取，首次读取时会请求蓝牙权限。分体键盘显示两半中较低的电量。Keychron 的 raw HID 协议没有电量命令，因此通过 USB 连接的 Keychron 不显示电量。
- **背光**：对于报告了背光、RGB 灯光或 RGB / LED 矩阵的 VIA / Vial 键盘，KeyMapper 会自动识别并提供**灯光**按钮，可调节效果、亮度、速度和颜色。尚未在实际硬件上测试。
- **带屏幕的键盘**：参见[下文](#带屏幕的键盘-leobog-amg65)。
- **登录时启动**选项。
- **语言**：Türkçe、English、Español、日本語、简体中文。App 默认跟随 macOS 的语言，也可以在菜单栏或编辑器边栏中即时切换。`kmctl` 使用相同的设置（可用 `KEYMAPPER_LANG=ja kmctl list` 为单条命令临时覆盖）。

## 带屏幕的键盘 (LEOBOG AMG65)

KeyMapper 可通过 USB 线缆或 2.4 GHz 接收器识别 LEOBOG AMG65，并在键位映射上方显示**屏幕和灯光**部分。它取代了独立的 AMG65 Studio App：一切都在 KeyMapper 内完成，无需安装 Python、libusb、本地服务器或其他辅助程序。该键盘的协议移植自 AMG65 Studio（参见 `THIRD_PARTY_NOTICES.md`）。

| 分组 | 标签页 | 功能 | 连接方式 |
|---|---|---|---|
| 屏幕 | AI | Claude、Codex 和 Cursor 的剩余额度，可分别开启，从你在这台 Mac 上已登录的会话中读取（对于 Claude，若桌面应用已登录则使用其登录信息，否则使用 Claude Code 的登录信息）。可选的动态追踪会显示哪个工具正在运行或正在等待批准。 | — |
| | LED 屏幕 | 将用量（概览、轮播或自定义文本，可加效果）持续推送到 63 × 5 的 LED 矩阵，并提供实时预览。 | 有线 |
| | LCD 和时钟 | 将图片或 GIF（最多 130 帧）上传到 240 × 135 的 LCD，保持时钟同步，并上传 LED 矩阵自身的动画或开机动画。 | 有线 |
| 灯光 | 效果 | 背光的 20 种内置效果，可调节颜色、亮度、速度和方向。 | 有线或 2.4 GHz |
| | 按键颜色 | 逐个为按键上色（点按或在按键上拖动）。 | 有线或 2.4 GHz |
| 键盘 | 按键分配 | 键盘自身的按键表：带修饰键的按键、媒体键和鼠标按钮。在任何电脑上都有效。 | 有线或 2.4 GHz |
| | 设置 | LED 屏幕亮度、休眠、Fn 切换和游戏模式。 | 有线 |

- **已在键盘上确认可用**（在 KeyMapper 中，或此前在 AMG65 Studio 中）：时钟同步、常亮和呼吸效果、LED 矩阵推送以及 LED 屏幕亮度。其他效果、按键颜色、媒体键和鼠标按钮分配、休眠、Fn 切换、游戏模式以及两种上传功能尚未测试，App 会在每一项旁边注明。
- **闪存**：LCD 图片、LED 动画和按键表会写入键盘的永久存储，发送前 App 会予以提示。首次发送的按键表会替换其他软件保存的所有按键分配。
- **安全**：如果键盘拒绝或未确认某条命令，KeyMapper 会停止向其写入，直到重新拔插键盘为止。警告旁的**原因**会显示失败的步骤、键盘的回复和时间。当 AMG65 Studio 占用键盘时，KeyMapper 会等待并提供**重试**。
- **隐私**：只读取你已开启的工具的用量，由一个短暂运行的辅助程序（`keymapper-usage`）从固定的 HTTPS 端点读取；除最新的数字外不保存任何内容，也绝不会续期或回写任何登录信息。读取 Claude 桌面应用或 Cursor 的登录信息需要一次性的钥匙串授权（“Claude Safe Storage”“Cursor Safe Storage”），且只有你点按**允许钥匙串访问**时才会请求。动态追踪默认关闭。开启后，它仅在这台 Mac 上读取钩子事件和 Codex 的会话记录。连接工具的钩子时，只有在你点按**连接钩子**后才会写入其配置文件（`~/.claude/settings.json`、`~/.codex/hooks.json` 或 `~/.cursor/hooks.json`），同时保留原文件的备份，并可在同一步中接管 AMG65 Studio 的钩子。

## 操作的工作原理

1. 每个操作都使用一个触发键：优先使用 F16–F20，其次是 F13，最后才是 F14/F15（macOS 将 F14/F15 用于屏幕亮度）。普通键盘没有这些按键，因此不会与任何功能冲突。
2. 在键盘编辑器中选择一个按键，然后直接在面板的 **App 与操作**标签页中选择**打开 App**、**打开网址 / 文件**、**运行快捷指令**、**发送组合键**、**输入文本**或**媒体 / 系统按键**。KeyMapper 会预留一个空闲的触发键，将操作绑定到该触发键，并将其写入按键（VIA/Vial 键盘写入固件，其他键盘则作为 macOS 重映射）。用于打开 App 的按键会显示该 App 的图标；要更改按键的操作，请在所选按键的卡片上使用**编辑操作**。
3. KeyMapper 通过 macOS 全局热键 API（Carbon `RegisterEventHotKey`）捕获触发键，因此该按键永远不会传到前台 App。如果前台 App 有对应的规则，就执行该规则；否则执行默认操作。

### App 标签页 (类似 Logi Options+)

键盘视图的右上角会显示**所有 App** 以及各个 App 的图标；点按 **+** 可添加 App。选中某个 App 后，每个按键都会显示它在该 App 中的功能。点按一个按键并选择该 App 的某个现成快捷键（例如 Photoshop 中的“撤销”、Chrome 中的“切换标签页”）或自定义操作，即可将该按键变为**智能按键**：触发键会写入固件（或 macOS 重映射），新功能在所选 App 中执行，而在其他所有 App 中，KeyMapper 会原样发送该按键之前的功能（字母、快捷键或音量 / 媒体键）。修饰键和层键必须能够按住，因此永远不会被转换为智能按键。

权限：打开 App、网址和快捷指令**无需任何权限**。发送组合键和输入文本需要 macOS 的**辅助功能**权限；只有在使用此类操作时，KeyMapper 才会请求该权限。对于 ad-hoc 签名的构建，macOS 可能会在每次重新构建后重置此权限；如果出现这种情况，请在“系统设置 › 隐私与安全性 › 辅助功能”中移除 KeyMapper，然后重新添加。

## 字母键

U.S. 布局中没有能输入 ğ、ş、ö、ü 或 İ 的按键，而键盘只能发送按键，不能发送字母。对于这些字母，KeyMapper 会自己输入：

1. 在键盘编辑器中选择一个按键，打开面板的**字母**标签页。选择一个字母（土耳其语在前，其后是其他语言），或输入任意其他字母并点按**分配**。已使用的字母列在该标签页底部；移除某个字母即可释放其位置。
2. KeyMapper 会向该按键写入一个保留代码：带 ⌃⌥⌘ 或 ⌃⌥ 的 F13 或 F16–F20，共 12 个字母。键盘发送该代码时，KeyMapper 会将其丢弃，并在同一位置输入字母，因此快速打字时顺序不会乱。按 Shift 或大写锁定输入大写字母，按住该键会重复输入字母。
3. 字母键需要**辅助功能**权限（缺少时，**字母**标签页会提供**授予权限**按钮），并且 KeyMapper 需要保持运行。它们仅适用于 VIA 和 Vial 键盘，因为 macOS 层面的重映射无法发送带修饰键的按键；在密码栏中它们不会输入任何内容，因为 macOS 会对其他 App 隐藏那里的按键。

## 安装

要求：macOS 15+、Xcode 16+（Swift 6 工具链）。

```bash
scripts/build-app.sh --install
```

该命令会构建 `build/KeyMapper.app` 并将其复制到 `/Applications`。如果只想构建，运行时去掉 `--install` 即可。

构建可安装的安装包（磁盘映像）：

```bash
scripts/make-dmg.sh
```

这会生成 `build/KeyMapper-<version>.dmg`；打开它，将 KeyMapper 拖到“应用程序”快捷方式上即可。加上 `--install` 时，磁盘映像中的 App 会直接安装到 `/Applications`（会先退出正在运行的副本）。

默认情况下，构建产物采用 ad-hoc 签名：它可以在构建它的 Mac 上运行，但在其他 Mac 上首次启动时会被 macOS 阻止（可在**系统设置 → 隐私与安全性**中点按**仍要打开**来允许）。如果需要一个在任何 Mac 上都能打开的安装包，请使用 Developer ID 签名并交由 Apple 公证：

```bash
xcrun notarytool store-credentials KeyMapper-notary --apple-id "<Apple ID>" --team-id <TEAMID>
```

```bash
SIGN_IDENTITY="Developer ID Application: <Name> (<TEAMID>)" NOTARY_PROFILE=KeyMapper-notary scripts/make-dmg.sh
```

第一条命令只需运行一次；它会要求输入在 account.apple.com 生成的 App 专用密码，并将其存储在钥匙串中。第二条命令会使用强化运行时（hardened runtime）和安全时间戳为 App、`kmctl` 和 `keymapper-usage` 辅助程序签名，为磁盘映像签名，将其提交到 Apple 的公证服务，等待结果（通常需要几分钟），然后将公证票据装订（staple）到磁盘映像上。如果 Apple 拒绝，脚本会打印公证日志并停止。使用 Developer ID 签名还能在重新构建后保留辅助功能、蓝牙和钥匙串权限。

App 不会出现在程序坞中；请使用菜单栏中的键盘图标。从访达或 Spotlight 再次打开 App 会调出编辑器窗口。

开发期间：

```bash
swift run KeyMapper -- --editor
```

```bash
swift test
```

## 命令行 (`kmctl`)

```bash
swift run kmctl list
```

| 命令 | 说明 |
|---|---|
| `kmctl list` | 列出已连接的键盘；如果 macOS 报告了电量，也会一并显示 |
| `kmctl dump <n> [layer]` | 打印键位映射（对于 Keychron，还会打印键盘当前输入所用的层） |
| `kmctl export <n> <file.vil\|file.json>` | 以 Vial 或 VIA 格式保存键位映射 |
| `kmctl apply <n> <file>` | 将 `.vil` / VIA `.json` / 配置文件写入键盘（只写入有差异的按键） |
| `kmctl remap <n> [preset\|clear]` | 应用或移除现成的 macOS 层面重映射 |
| `kmctl firmware <n>` | 显示已安装的固件版本并检查更新（Keychron） |

## 从 vial.rocks 迁移布局

1. 在 vial.rocks 上打开你的键盘，通过 **Save current layout**（保存当前布局）下载 `.vil` 文件。
2. 在 KeyMapper 菜单中，于该键盘的**布局**一行点按 **+**，然后选择**从文件导入（.vil / VIA .json）…**。该文件会保存为配置文件。
3. 在同一行中选择该配置文件，即可将其写入键盘。

## Keychron 定义的自动获取以及层和固件更新

较新的 Keychron 型号（例如 Nape Pro 轨迹球和 V/Q/K Max 系列）不在公开的 VIA 仓库中，它们的定义由 Keychron Launcher 分发。对于 Keychron 设备，KeyMapper 会自动从 Keychron Launcher 的服务器下载定义并缓存。没有按键矩阵的设备（如轨迹球和鼠标）也可以编辑，包括按钮和旋钮。

层：KeyMapper 通过 Keychron 的 Launcher 协议（QMK 和 ZMK 两个固件系列均适用）获知键盘当前输入所用的层，跟随键盘报告的层切换，并在该层上打开编辑器。这一点很重要，因为写入其他层的按键看起来会毫无作用；例如 Nape Pro 就是在层 1 上输入的。

固件：KeyMapper 从设备读取已安装的版本（Keychron 的 `0xA1` 命令或 USB 版本字段），并从 Keychron 获取最新版本及其发行说明。有可用更新时，设备标题栏和菜单栏中会出现橙色提示。更新需通过 Keychron Launcher 安装；KeyMapper 从不写入固件。通用的 VIA/QMK 和 Vial 键盘没有公开的更新来源。

这些 Keychron 端点没有公开文档，随时可能变化；一旦发生变化，KeyMapper 会静默回退到 VIA 仓库和手动载入的定义。

## 找不到定义时

其他品牌的部分型号（或通过 2.4 GHz 接收器连接的键盘）在 VIA 仓库中以不同的产品 ID 列出。请从制造商网站下载适用于你的型号的 VIA JSON 文件，然后在编辑器中选择**配置文件 → 载入 VIA 定义文件…**，将其添加进来。

## 已知限制

- 仅支持 ZMK Studio 协议的键盘暂不支持固件层面的编辑，但可以通过 macOS 重映射进行编辑。（Keychron 的 ZMK 固件支持 VIA 协议，因此受支持。）
- 宏、tap dance 和 combo 暂时无法编辑（已有的会被保留）。
- 在其他品牌软件（例如 Logi Options+）中设置的按键分配独立生效；KeyMapper 会在 macOS 层面在其基础上再做重映射。
- MacBook 内置键盘不会被列出。

## 架构

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

图标在构建时由 `actool` 从 `Resources/AppIcon.icon` 生成：macOS 26 及更高版本使用 `Assets.car`（系统会自动派生浅色、深色、着色和透明图标样式），较旧的 macOS 使用 `AppIcon.icns`。该文档可以用 Xcode 自带的 Icon Composer 打开和编辑。

翻译位于 `Sources/KeyMapperCore/Localization/`：界面字符串在源码中以土耳其语编写并用 `L("…")` 标记，每种语言的字典都以这些土耳其语字符串作为键。测试会检查每个被标记的字符串是否已在所有语言中翻译，且占位符（`%@`）一致。本 README 也采用同样的方式翻译：`README.tr.md`、`README.es.md`、`README.ja.md` 和 `README.zh-Hans.md` 逐节对应英文版 README，因此英文版的改动需要同步到全部五个文件中。

数据存储在 `~/Library/Application Support/KeyMapper/` 中（配置文件、VIA 定义缓存和用户定义）。

## 许可证

KeyMapper 基于 [MIT 许可证](LICENSE)发布。它所依赖的代码及其各自的许可证列于 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) 中。
