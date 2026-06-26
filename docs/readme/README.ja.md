<div align="center">
  <img src="../../assets/banner.png" alt="AgentPet" width="100%" />
  <p>
    <img src="https://img.shields.io/badge/platform-macOS%2013%2B-black" alt="macOS 13+" />
    <img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT" />
    <img src="https://img.shields.io/badge/Swift-SwiftUI-orange" alt="Swift" />
    <a href="https://github.com/ntd4996/agentpet"><img src="https://img.shields.io/github/stars/ntd4996/agentpet?style=social" alt="GitHub stars" /></a>
  </p>
  <p><b>AgentPet が役に立ったら、ぜひ <a href="https://github.com/ntd4996/agentpet">スター</a> をお願いします！</b></p>
  <p>
    <a href="../../README.md">English</a> ·
    <a href="README.vi.md">Tiếng Việt</a> ·
    <a href="README.zh-Hans.md">简体中文</a> ·
    <b>日本語</b>
  </p>
</div>

複数のコーディングエージェント（Claude Code、Codex など）を同時に動かすと、AgentPet がどれが**作業中**で、どれが**完了**し、どれが**あなたの入力待ち**かを一目で教えてくれます。ターミナルを行き来する必要はもうありません。小さなペットがデスクトップに浮かび、すべてに反応します。

## なぜ

複数のエージェントを並行して動かすと、誰が自分を必要としているか確認するためにウィンドウを切り替え続けることになります。AgentPet はそれを 2 か所で可視化します:

- **メニューバーのモニター**で詳細を: 実行中の各エージェント、その状態、何をしているか、リアルタイムのタイマー。
- **デスクトップのペット**で、作業を中断せずに把握できるさりげない合図を。

## 機能

- **マルチエージェント監視**（メニューバー）: 各エージェントを状態色のドット、プロジェクト名、何をしているか（実行中ツール / 待機理由）、状態ごとのリアルタイムタイマー付きで一覧表示。
- **一目でわかるメニューバーアイコン**: 実行中のエージェント数を表示し、入力が必要なときは**オレンジ＋数字**に変化。
- **デスクトップのペット**が集約状態（working / waiting / done / celebrate）に反応し、任意で**チャットバブル**（組み込み or 完全カスタムのメッセージ）を表示。
- エージェントの完了時や入力が必要なときに**ネイティブ通知**。
- **Claude Code・Codex・Gemini CLI** を hook で統合し、設定からワンタップでインストール（working / waiting / done / idle を正確に検出、「入力待ち」も含む）。
- **汎用ラッパー** `agentpet run -- <コマンド>` で*任意の* CLI エージェントを監視（working/done）、個別設定は不要。
- **ペットシステム**: オンラインのペットライブラリを閲覧してワンクリックでダウンロード、各状態にアニメーションを割り当て、サイズ変更、チャット文のカスタマイズ。
- **洗練されたネイティブ設定**（タブ・ダーク）。フォーカスを奪いません。

## スクリーンショット

<div align="center">
  <img src="../../assets/screenshot-menubar.png" width="360" alt="メニューバー監視" />
  <img src="../../assets/screenshot-settings.png" width="360" alt="設定" />
  <img src="../../assets/screenshot-pet.png" width="360" alt="ペット" />
  <img src="../../assets/screenshot-notification.png" width="360" alt="通知" />
  <br/>
  <img src="../../assets/demo.gif" width="600" alt="エージェントの活動に反応するペット" />
</div>

## 動作環境

- **macOS 13 Ventura 以降**（macOS 14 Sonoma 以降を推奨。キーボードのフォーカスリング無効化に macOS 14+ の API を使用）。
- **Apple Silicon（M1/M2/M3/M4）と Intel Mac** の両方に対応。
- リリース済みのデスクトップアプリは現在 macOS 専用です。パッケージ化された Windows / Linux 版はまだありません。
- ソースからビルドするには: Xcode 16 / Swift 6。
- Windows コントリビューターは Swift `AgentPetCore` をビルド/テストできます。ソースビルドの Windows プロトタイプは [`Windows/`](../../Windows/) にあり、ネイティブ C# WPF UI を使います。SwiftUI/AppKit と Sparkle は macOS 専用のままです。

## インストール

### Homebrew

```bash
brew install --cask ntd4996/tap/agentpet
```

### 直接ダウンロード

[Releases](https://github.com/ntd4996/agentpet/releases) から最新の `AgentPet.dmg` を入手し、開いて AgentPet を Applications にドラッグします。

### ソースからビルド

```bash
git clone https://github.com/ntd4996/agentpet.git
cd agentpet
./scripts/build-app.sh release
open build/AgentPet.app
```

> **注意:** 現在のビルドは Developer ID 署名済みですが**まだ公証されていません**。そのため macOS が初回起動をブロックする場合があります。一度だけ隔離フラグを削除してください:
> ```bash
> xattr -dr com.apple.quarantine "/Applications/AgentPet.app"
> ```
> 完全に公証されたビルド（警告なし）は近日公開予定です。

初回起動時に **Settings → General** を開き、Claude Code の横の **Install** をクリックし、通知を **Enable** にしてください。

## 使い方

**Claude Code**（推奨）: 設定から hook をインストールします。AgentPet は各セッションの実際の状態（「入力待ち」を含む）を反映します。

**その他の CLI エージェント**: ラップして実行します。

```bash
agentpet run -- <あなたのエージェントコマンド>     # 例: agentpet run -- aider
```

セッションは実行中に *working*、終了時に *done* と表示されます。

## ペット

ペットはオープンな Codex ペットパック形式（`pet.json` + 8×9 のスプライトシート）を使います。できること:

- オンラインライブラリを**閲覧**してワンクリックでダウンロード（Settings → Pet → Browse pets）。
- **アニメーションの割り当て**: 各状態でどのアニメーションを再生するか選択。
- 不要なペットを**削除**。

初回起動時にスターターペットが自動でインストールされます。AgentPet はペット素材を同梱しません。ペットは実行時に追加されます。

## ロードマップ

- 公証済み DMG + Homebrew cask
- エージェントをクリックしてそのターミナルを表示
- プロジェクトごとのペット

## 技術

Swift + SwiftUI、エージェントイベント用の Unix ソケットデーモン、小さな CLI ヘルパーを、1 つの SwiftPM パッケージにまとめています。設計は [`docs/specs`](../specs) を参照。

## 応援

AgentPet がターミナル探しを減らせたなら、こんな応援ができます:

- ⭐ **[リポジトリにスター](https://github.com/ntd4996/agentpet)** して、より多くの人に届けてください。
- ☕ **[コーヒーをおごる](https://buymeacoffee.com/ntd4996)** と、さらなる機能開発の励みになります。

開発: **[Nguyễn Thành Đạt (@ntd4996)](https://github.com/ntd4996)**

## 謝辞

Codex ペットパック形式とオンラインペットライブラリは **[Petdex](https://github.com/crafter-station/petdex)**（MIT）が提供しています。AgentPet は独立した相互運用クライアントで、Petdex 形式のパックを読み込み、Petdex の公開 API からダウンロードできます。AgentPet はペット素材を同梱しません。各ペット素材は提出者が各自のライセンスで保有します。あるキャラクターの権利をお持ちの場合は、テイクダウン要請を Petdex までお願いします。

## ライセンス

MIT、[LICENSE](../../LICENSE) を参照。アプリケーションコードのみが対象です。ペット素材は本リポジトリには含まれません。
