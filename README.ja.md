# KeyMapper

[English](README.md) · [Türkçe](README.tr.md) · [Español](README.es.md) · **日本語** · [简体中文](README.zh-Hans.md)

メニューバーに常駐する、macOS 用の汎用キーボードマッパーです。接続中のキーボードを選んでレイアウト（keymap）を割り当てると、KeyMapper がキーボードのファームウェアに応じて適切な編集方法を選びます。

## ダウンロード

**[Mac 版 KeyMapper をダウンロード（.dmg）](https://github.com/kocakli/Universal-Keyboard/releases/latest/download/KeyMapper.dmg)** · [すべてのリリース](https://github.com/kocakli/Universal-Keyboard/releases)

Apple シリコン搭載の Mac と macOS 15 以降が必要です。

1. ダウンロードしたディスクイメージを開き、**KeyMapper** を **Applications**（アプリケーション）のショートカットにドラッグします。
2. 「アプリケーション」から KeyMapper を開きます。Apple による署名と公証を受けているため、セキュリティ警告は表示されずに開きます。
3. KeyMapper はメニューバー（キーボードのアイコン）に常駐し、Dock にはアイコンを表示しません。Finder や Spotlight からもう一度開くと、エディタが表示されます。

macOS は、Bluetooth LE キーボードを初めて接続したときに **Bluetooth** の許可を求め（バッテリー残量の読み取りにのみ使用します）、キーの組み合わせの送信やテキストの入力を行うアクション、または文字キーを使ったときにだけ **アクセシビリティ** の許可を求めます。Claude や Cursor の使用状況を表示するには一度だけ **キーチェーン** の承認が必要ですが、この承認は **キーチェーンへのアクセスを許可** をクリックしたあとにしか求められません（[プライバシー](#ディスプレイ付きキーボード-leobog-amg65)を参照）。

自分でビルドする場合は、[インストール](#インストール)を参照してください。

| キーボードの種類 | 例 | 編集方法 |
|---|---|---|
| **Vial** | Cornix、Corne (crkbd)、Lily58、Sofle など、vial.rocks で使えるすべてのキーボード | 定義をキーボード本体から（USB または Bluetooth で）読み取り、keymap をファームウェアに書き込みます |
| **VIA / QMK** | Keychron (Q/V/K Pro…)、NuPhy、KBDfans、Keebio、DZTech、Glorious GMMK Pro… | 定義を VIA リポジトリ（usevia.app）や Keychron Launcher からダウンロードするか、JSON ファイルから読み込み、keymap をファームウェアに書き込みます |
| **その他すべてのキーボード** | Logitech、Apple Magic Keyboard、Razer、Corsair、SteelSeries、HyperX… | macOS レベルのキーリマップ（`hidutil`）です。**そのキーボードだけに**適用され、接続するたびに再適用されます |

編集方法はブランドではなく、デバイスが公開しているインターフェイスによって決まります。QMK の raw HID インターフェイス（usage page `0xFF60`）を持つキーボードはすべて VIA/Vial で、持たないキーボードはすべて macOS のリマップで編集します。そのため、一覧にないブランドでも使えます。

## 機能

- **メニューバー**：接続中のキーボードを、接続方式（USB / Bluetooth / Bluetooth LE）、バッテリー残量、サポートの種類とともに表示し、レイアウト（プロファイル）をワンクリックで割り当てられます。
- **エディタ**：キーボードの実際の物理レイアウト（回転した親指キー、エンコーダー、レイアウトオプションを含む）とレイヤーを表示し、どのキーにも新しい機能を割り当てられます。
- **キーコード**：基本キー、修飾キー、メディア、マウス、レイヤーキー（`MO`、`TG`、`TO`、`TT`、`OSL`、`DF`）、mod-tap / home row mods（`LSFT_T(KC_A)`）、layer-tap（`LT(1, KC_SPC)`）、組み合わせ（`LCTL(KC_C)`）、マクロ、キーボード固有のキーコード（例：Cornix の `BT0`、`NEXT_BT`）。旧方式（QMK < 0.19）と現行方式のキーコード番号体系は自動的に判別されます。
- **「長押しで」メニュー**：選択中のキーに mod-tap や layer-tap をワンクリックで追加できます。
- **アルファベット配列の変換**：QWERTY ⇄ Colemak / Colemak-DH / Dvorak / Workman。home row mods と layer-tap は維持されます。KeyMapper は各レイヤーの現在の配列を記憶しているため、同じレイヤーを誤って 2 回変換することはなく、直前の変換は取り消せます。macOS レベルのキーボード向けには、プリセットのリマップとしても用意されています。
- **プロファイル**：現在のレイアウトをプロファイルとして保存し、メニューバーから復元できます。書き込まれるのは差分のあるキーだけです。
- **読み込み / 書き出し**：Vial の `.vil`（vial.rocks で保存したファイル）、VIA の `.json` レイアウトファイル、KeyMapper のプロファイルに対応しています。
- **Vial のロック解除**：`QK_BOOT` のような保護されたキーのための、Vial のロック解除フローに対応しています。
- **アクション**（Logitech Options+ のアプリごとの設定に相当）：キーに、アプリを開く、URL やファイルを開く、ショートカットを実行する、キーの組み合わせを送信する、テキストを入力する、といった操作を割り当てられます。同じキーでも、最前面のアプリによって動作を変えられます（例：Safari では新規タブ、VS Code ではコマンドパレット、それ以外では Spotlight）。既製のショートカットは約 30 のアプリに対応しており、Claude（承認 / 拒否）、ChatGPT、Terminal、iTerm2、Warp、Ghostty、Safari、Chrome、Brave、Arc、Firefox、Finder、Mail、Music、VS Code、Cursor、Xcode、Zoom、Teams、Slack、Discord、Notion、Obsidian、Word、Excel、PowerPoint、Photoshop、Final Cut Pro、Spotify などが含まれます。
- **文字キー**: Mac のキーボード配列にない文字（トルコ語の ç ğ ı İ ö ş ü や ñ、é、ß など）をキーに割り当てられます。Shift または Caps Lock で大文字になります（ı → I、i → İ）。[文字キー](#文字キー)を参照してください。
- **バッテリー残量**：接続中のキーボードの充電残量がメニューバー、サイドバー、エディタのヘッダーに表示され、20 % 以下になると赤色で表示されます。Apple のキーボードは macOS 経由で、Bluetooth LE キーボード（例：Cornix）は標準の Bluetooth Battery Service 経由で読み取ります。後者は初回に Bluetooth の許可を求めます。分割キーボードでは、残量の少ないほうの値を表示します。Keychron の raw HID プロトコルにはバッテリー残量を取得するコマンドがないため、USB で接続した Keychron ではバッテリー残量は表示されません。
- **バックライト**：バックライト、RGB ライト、RGB / LED マトリクスを備えていると報告する VIA / Vial キーボードには、エフェクト、明るさ、速度、色を設定できる **ライト** ボタンが表示されます（自動検出）。実機ではまだ試していません。
- **ディスプレイ付きキーボード**：[後述](#ディスプレイ付きキーボード-leobog-amg65)を参照してください。
- **ログイン時に開く** オプション。
- **言語**：Türkçe、English、Español、日本語、简体中文。デフォルトでは macOS の言語に従い、メニューバーまたはエディタのサイドバーからすぐに切り替えられます。`kmctl` も同じ設定を使います（1 回のコマンドだけ変更するには `KEYMAPPER_LANG=ja kmctl list` のように指定します）。

## ディスプレイ付きキーボード (LEOBOG AMG65)

KeyMapper は USB ケーブルまたは 2.4 GHz レシーバー経由で LEOBOG AMG65 を検出し、keymap の上に **ディスプレイとライト** セクションを表示します。これは単体の AMG65 Studio アプリに代わるもので、すべてが KeyMapper の中で動作し、Python、libusb、ローカルサーバー、追加のヘルパーなどをインストールする必要はありません。キーボードのプロトコルは AMG65 Studio から移植しました（`THIRD_PARTY_NOTICES.md` を参照）。

| グループ | タブ | できること | 接続 |
|---|---|---|---|
| ディスプレイ | AI | Claude、Codex、Cursor の残りの使用枠を、この Mac ですでにサインインしているセッションから読み取ります（ツールごとに個別にオンにできます）。Claude の場合は、デスクトップアプリのサインインがあればそれを、なければ Claude Code のサインインを使います。オプションのアクティビティ追跡では、どのツールが実行中か、承認待ちかを表示します。 | — |
| | LED ディスプレイ | 使用状況（概要、順番に切り替え、または任意のテキストを、エフェクト付きで）を 63 × 5 の LED マトリクスにストリーミングし、ライブプレビューも表示します。 | ケーブル |
| | LCD と時計 | 画像や GIF（最大 130 フレーム）を 240 × 135 の LCD にアップロードし、時計を同期し、LED マトリクス独自のアニメーションや起動アニメーションをアップロードします。 | ケーブル |
| ライト | エフェクト | バックライトの 20 種類の内蔵エフェクトを、色、明るさ、速度、方向とともに設定します。 | ケーブルまたは 2.4 GHz |
| | キーの色 | キーを 1 つずつ塗り分けます（クリック、またはキーの上をドラッグ）。 | ケーブルまたは 2.4 GHz |
| キーボード | キーの割り当て | キーボード本体のキーテーブルです。修飾キー付きのキー、メディアキー、マウスボタンを割り当てられます。どのコンピュータでも機能します。 | ケーブルまたは 2.4 GHz |
| | 設定 | LED ディスプレイの明るさ、スリープ、Fn トグル、ゲームモード。 | ケーブル |

- **キーボードで動作確認済み**（KeyMapper で、またはそれ以前に AMG65 Studio で）：時計の同期、「点灯」と「ブリージング」のエフェクト、LED マトリクスへのストリーミング、LED ディスプレイの明るさ。その他のエフェクト、キーの色、メディアキーとマウスの割り当て、スリープ、Fn トグル、ゲームモード、2 種類のアップロードはまだ試しておらず、アプリでもそれぞれの横にその旨が表示されます。
- **フラッシュメモリ**：LCD の画像、LED アニメーション、キーテーブルはキーボードの永続メモリに書き込まれるため、送信する前にその旨が表示されます。最初に送信したキーテーブルは、ほかのソフトウェアで保存された割り当てをすべて置き換えます。
- **安全性**：キーボードがコマンドを拒否した場合や応答しなかった場合、KeyMapper はキーボードを抜き差しするまで、そのキーボードへの書き込みを停止します。警告の横にある **理由** で、失敗した手順、キーボードの応答、時刻を確認できます。AMG65 Studio がキーボードを使用している間、KeyMapper は待機し、**再試行** を表示します。
- **プライバシー**：使用状況は、オンにしたツールについてのみ、短時間だけ動作するヘルパー（`keymapper-usage`）が固定の HTTPS エンドポイントから読み取ります。保存するのは最新の数値だけで、サインインを更新したり書き戻したりすることは一切ありません。Claude デスクトップアプリや Cursor のサインインを読み取るには、一度だけキーチェーンの承認（「Claude Safe Storage」「Cursor Safe Storage」）が必要で、この承認を求めるのは **キーチェーンへのアクセスを許可** をクリックしたときだけです。アクティビティ追跡はデフォルトでオフです。オンにすると、この Mac 上のフックイベントと Codex のセッションログだけを読み取ります。ツールのフックを接続すると、そのツールの設定ファイル（`~/.claude/settings.json`、`~/.codex/hooks.json` または `~/.cursor/hooks.json`）に書き込みます。書き込むのは **フックを接続** をクリックしたときだけで、以前のファイルはバックアップとして残り、同じ手順で AMG65 Studio のフックから引き継ぐこともできます。

## アクションの仕組み

1. すべてのアクションはトリガーキーを使います。F16–F20 から順に使い、次に F13、最後に F14/F15 を使います（macOS は F14/F15 を画面の明るさの調整に使うため）。一般的なキーボードにはこれらのキーがないので、ほかの操作と衝突しません。
2. キーボードエディタでキーを選択し、パレットの **Appとアクション** タブから **Appを開く**、**アドレス/ファイルを開く**、**ショートカットを実行**、**キーの組み合わせを送信**、**テキストを入力**、**メディア/システムキー** のいずれかを直接選びます。KeyMapper は空いているトリガーキーを確保してそこにアクションを割り当て、そのトリガーキーを選択したキーに書き込みます（VIA/Vial ではファームウェアに、その他のキーボードでは macOS のリマップとして）。アプリを開くキーにはそのアプリのアイコンが表示されます。キーのアクションを変更するには、選択中のキーのカードにある **アクションを編集** を使います。
3. KeyMapper は macOS のグローバルホットキー API（Carbon の `RegisterEventHotKey`）でトリガーキーを受け取るため、そのキーが最前面のアプリに届くことはありません。最前面のアプリにルールがあればそのルールを、なければデフォルトのアクションを実行します。

### アプリごとのタブ (Logi Options+ と同様)

キーボード表示の右上には **すべてのApp** とアプリのアイコンが並び、**+** でアプリを追加できます。アプリを選択すると、各キーにそのアプリでの動作が表示されます。キーをクリックして、そのアプリ用の既製ショートカット（例：Photoshop の「取り消す」、Chrome の「タブ切り替え」）またはカスタムアクションを選ぶと、そのキーは **スマートキー** になります。トリガーキーがファームウェア（または macOS のリマップ）に書き込まれ、選択したアプリでは新しい機能が実行され、それ以外のすべてのアプリでは KeyMapper がキーの以前の機能（文字、ショートカット、音量 / メディアキー）をそのまま送信します。修飾キーとレイヤーキーは押したままにできる必要があるため、スマートキーには変換されません。

必要な許可：アプリ、URL、ショートカットを開くのに **許可は必要ありません**。キーの組み合わせの送信とテキストの入力には macOS の **アクセシビリティ** の許可が必要で、KeyMapper はそうしたアクションが使われたときにだけ許可を求めます。ad-hoc 署名のビルドでは、リビルドのたびに macOS がこの許可をリセットすることがあります。その場合は、システム設定 › プライバシーとセキュリティ › アクセシビリティ で KeyMapper を削除してから、もう一度追加してください。

## 文字キー

U.S. 配列には ğ、ş、ö、ü、İ を入力するキーがなく、キーボードが送れるのはキーだけで、文字そのものは送れません。こうした文字は KeyMapper が自分で入力します。

1. キーボードエディタでキーを選択し、パレットの **文字** タブを開きます。文字を選ぶ（トルコ語が先頭、続いてほかの言語）か、ほかの文字を入力して **割り当て** をクリックします。使用中の文字はタブの下部に一覧表示され、削除するとその枠が空きます。
2. KeyMapper はキーに予約済みのコード（⌃⌥⌘ または ⌃⌥ を付けた F13 または F16–F20、合計 12 文字分）を書き込みます。キーボードがそのコードを送ると、KeyMapper はそれを取り除いて同じ位置に文字を入力するので、速く打っても順番が崩れません。Shift または Caps Lock で大文字になり、キーを押し続けると文字が繰り返されます。
3. 文字キーには **アクセシビリティ** の許可（ない場合は **文字** タブに **許可する** ボタンが表示されます）と、KeyMapper が起動していることが必要です。macOS レベルのリマップでは修飾キー付きのキーを送れないため、VIA と Vial のキーボードでのみ使えます。また、macOS がほかのアプリからキー入力を隠すパスワード欄では何も入力されません。

## インストール

必要環境：macOS 15+、Xcode 16+（Swift 6 ツールチェーン）。

```bash
scripts/build-app.sh --install
```

`build/KeyMapper.app` をビルドし、`/Applications` にコピーします。ビルドだけを行う場合は、`--install` を付けずに実行してください。

インストール可能なパッケージ（ディスクイメージ）をビルドするには、次のように実行します。

```bash
scripts/make-dmg.sh
```

`build/KeyMapper-<version>.dmg` が作成されます。これを開いて、KeyMapper をアプリケーションのショートカットにドラッグしてください。`--install` を付けると、ディスクイメージ内のアプリが直接 `/Applications` にインストールされます（実行中のコピーがあれば先に終了します）。

デフォルトでは、ビルドは ad-hoc 署名されます。ビルドした Mac では動作しますが、別の Mac では macOS が初回起動をブロックします（**システム設定 → プライバシーとセキュリティ** の **このまま開く** で許可できます）。どの Mac でも開けるパッケージにするには、Developer ID で署名し、Apple の公証を受けてください。

```bash
xcrun notarytool store-credentials KeyMapper-notary --apple-id "<Apple ID>" --team-id <TEAMID>
```

```bash
SIGN_IDENTITY="Developer ID Application: <Name> (<TEAMID>)" NOTARY_PROFILE=KeyMapper-notary scripts/make-dmg.sh
```

1 つ目のコマンドは一度だけ実行すれば十分です。account.apple.com で発行した App 用パスワードの入力を求められ、それがキーチェーンに保存されます。2 つ目のコマンドは、アプリ、`kmctl`、`keymapper-usage` ヘルパーを hardened runtime とセキュアタイムスタンプ付きで署名し、ディスクイメージに署名して Apple の公証サービスに提出し、結果を待って（通常は数分）、チケットをディスクイメージにステープルします。Apple に却下された場合、スクリプトは公証ログを出力して停止します。Developer ID で署名すると、リビルドしてもアクセシビリティ、Bluetooth、キーチェーンの許可が維持されます。

アプリは Dock に表示されません。メニューバーのキーボードアイコンを使ってください。Finder や Spotlight からアプリをもう一度開くと、エディタウインドウが表示されます。

開発中は次のコマンドを使います。

```bash
swift run KeyMapper -- --editor
```

```bash
swift test
```

## コマンドライン (`kmctl`)

```bash
swift run kmctl list
```

| コマンド | 説明 |
|---|---|
| `kmctl list` | 接続中のキーボードを一覧表示します（macOS がバッテリー残量を報告する場合はその値も表示） |
| `kmctl dump <n> [layer]` | keymap を出力します（Keychron の場合は、キーボードが現在入力に使っているレイヤーも表示） |
| `kmctl export <n> <file.vil\|file.json>` | keymap を Vial または VIA 形式で保存します |
| `kmctl apply <n> <file>` | `.vil` / VIA `.json` / プロファイルファイルをキーボードに書き込みます（差分のあるキーだけ） |
| `kmctl remap <n> [preset\|clear]` | macOS レベルのプリセットのリマップを適用または削除します |
| `kmctl firmware <n>` | インストール済みのファームウェアバージョンを表示し、アップデートを確認します（Keychron） |

## vial.rocks からレイアウトを移行する

1. vial.rocks で自分のキーボードを開き、**Save current layout** で `.vil` ファイルをダウンロードします。
2. KeyMapper のメニューで、そのキーボードの **レイアウト** 行にある **+** をクリックし、**ファイルから読み込む（.vil / VIA .json）…** を選びます。ファイルはプロファイルとして保存されます。
3. 同じ行でそのプロファイルを選択すると、キーボードに書き込まれます。

## Keychron: 定義の自動取得 / レイヤー / ファームウェアアップデート

新しい Keychron モデル（例：Nape Pro トラックボールや V/Q/K Max シリーズ）は公開の VIA リポジトリには含まれておらず、定義は Keychron Launcher で配布されています。Keychron のデバイスについては、KeyMapper が Keychron Launcher のサーバーから定義を自動的にダウンロードしてキャッシュします。トラックボールやマウスなど、キーマトリクスを持たないデバイスも、ボタンやノブを含めて編集できます。

レイヤー：KeyMapper は Keychron の Launcher プロトコル（QMK と ZMK の両方のファームウェアファミリー）を読み取って、キーボードが現在どのレイヤーで入力しているかを把握し、キーボードが報告するレイヤーの変更に追従して、そのレイヤーでエディタを開きます。別のレイヤーに書き込んだキーは何もしないように見えるため、これは重要です。たとえば Nape Pro はレイヤー 1 で入力します。

ファームウェア：KeyMapper はインストール済みのバージョンをデバイスから読み取り（Keychron の `0xA1` コマンド、または USB のバージョンフィールド）、最新バージョンとそのリリースノートを Keychron から取得します。アップデートがある場合は、デバイスのヘッダーとメニューバーにオレンジ色の通知が表示されます。アップデートのインストールには Keychron Launcher を使います。KeyMapper がファームウェアを書き込むことはありません。汎用の VIA/QMK キーボードと Vial キーボードには、公開されたアップデートの提供元がありません。

これらの Keychron のエンドポイントは公式にドキュメント化されておらず、変更される可能性があります。変更された場合、KeyMapper は通知を出さずに、VIA リポジトリと手動で読み込んだ定義にフォールバックします。

## 定義が見つからない場合

ほかのブランドの一部のモデル（または 2.4 GHz レシーバー経由で接続したキーボード）は、VIA リポジトリに別の製品 ID で登録されています。メーカーのサイトからお使いのモデルの VIA JSON ファイルをダウンロードし、エディタの **プロファイル → VIA定義ファイルを読み込む…** で追加してください。

## 既知の制限事項

- ZMK Studio プロトコルにしか対応していないキーボードは、まだファームウェアレベルではサポートしていません。macOS のリマップで編集できます。（Keychron の ZMK ファームウェアは VIA に対応しているため、サポートしています。）
- マクロ、タップダンス、コンボはまだ編集できません（既存のものは保持されます）。
- ほかのブランドのソフトウェア（例：Logi Options+）で行ったキーの割り当ては、それとは別に動作します。KeyMapper はその上から macOS レベルでリマップします。
- MacBook の内蔵キーボードは一覧に表示されません。

## アーキテクチャ

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

アイコンはビルド時に `actool` で `Resources/AppIcon.icon` から生成されます。macOS 26 以降向けには `Assets.car`（ライト、ダーク、色合い付き、クリアの各アイコンスタイルはシステムが自動的に生成します）が、それより前の macOS 向けには `AppIcon.icns` が作られます。このドキュメントは、Xcode に同梱されている Icon Composer で開いて編集できます。

翻訳は `Sources/KeyMapperCore/Localization/` にあります。UI の文字列はソースコード内にトルコ語で書かれ、`L("…")` でマークされています。各言語の辞書は、そのトルコ語の文字列をキーとして使います。テストでは、マークされたすべての文字列が、すべての言語で同じプレースホルダー（`%@`）を使って翻訳されていることを確認しています。この README も同じ方法で翻訳されています。`README.tr.md`、`README.es.md`、`README.ja.md`、`README.zh-Hans.md` は英語版の README にセクション単位で対応しているため、英語版を変更したら、その変更を 5 つすべてに反映します。

データは `~/Library/Application Support/KeyMapper/` に保存されます（プロファイル、VIA 定義のキャッシュ、ユーザー定義）。

## ライセンス

KeyMapper は [MIT ライセンス](LICENSE) の下で公開されています。KeyMapper が基にしているコードは、それぞれのライセンスとともに [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) に記載しています。
