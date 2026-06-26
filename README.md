<div align="center">
  <img src="assets/banner.png" alt="AgentPet" width="100%" />
  <p>
    <img src="https://img.shields.io/badge/platform-macOS%2013%2B-black" alt="macOS 13+" />
    <img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT" />
    <img src="https://img.shields.io/badge/Swift-SwiftUI-orange" alt="Swift" />
    <a href="https://github.com/ntd4996/agentpet/actions"><img src="https://github.com/ntd4996/agentpet/actions/workflows/ci.yml/badge.svg" alt="CI" /></a>
    <a href="https://github.com/ntd4996/agentpet"><img src="https://img.shields.io/github/stars/ntd4996/agentpet?style=social" alt="GitHub stars" /></a>
  </p>
  <p><b>If AgentPet helps your workflow, please <a href="https://github.com/ntd4996/agentpet">give it a star</a> — it really helps!</b></p>
  <p>
    <b>English</b> ·
    <a href="docs/readme/README.vi.md">Tiếng Việt</a> ·
    <a href="docs/readme/README.zh-Hans.md">简体中文</a> ·
    <a href="docs/readme/README.ja.md">日本語</a>
  </p>
</div>

Run several coding agents at once (Claude Code, Codex, ...) and AgentPet tells you, at a glance, which one is **working**, which one is **done**, and which one is **waiting for your input**, so you stop tab-hunting across terminals. A little pet floats on your desktop and reacts to it all.

## Why

Running multiple agents in parallel means constantly switching windows to check who needs you. AgentPet surfaces that in two places:

- **Menu bar monitor** for the details: every running agent, its state, what it's doing, and a live timer.
- **Desktop pet** for an ambient signal you can read without breaking focus.

## Features

- **Multi-agent monitor** in the menu bar: live list of every agent with a colored status dot, the project, what it's doing (running tool / waiting reason), and a per-state timer that counts in real time.
- **At-a-glance menu bar icon**: shows the number of running agents, and turns **orange with a count** when one needs your input.
- **Desktop pet** that reacts to the aggregate state (working / waiting / done / celebrate), with an optional **chat bubble** (built-in or fully custom messages).
- **Native notifications** when an agent finishes or needs input.
- **Claude Code, Codex, Gemini CLI, Cursor, opencode, Windsurf & Antigravity** integration via hooks, with one-tap install from Settings (precise working / waiting / done / idle, including "needs your input"). GLM (Z.AI) works through Claude Code automatically. Cursor, Windsurf and Antigravity report working/done (they have no "needs input" hook).
- **Universal wrapper** `agentpet run -- <command>` to monitor *any* CLI agent (working/done), no per-agent setup.
- **Pet system**: browse an online pet library and download with one click, map each animation to a state, resize, and customise chat lines.
- **Polished, native Settings** (tabbed, dark) that never steals focus.

## Screenshots

<div align="center">
  <img src="assets/screenshot-menubar.png" width="360" alt="Menu bar monitor" />
  <img src="assets/screenshot-settings.png" width="360" alt="Settings" />
  <img src="assets/screenshot-pet.png" width="360" alt="Pet" />
  <img src="assets/screenshot-notification.png" width="360" alt="Notification" />
  <br/>
  <img src="assets/demo.gif" width="600" alt="Pet reacting to agent activity" />
</div>

## Requirements

- **macOS 13 Ventura or later** (macOS 14 Sonoma+ recommended; the keyboard-focus-ring cleanup uses APIs available on macOS 14+).
- **Apple Silicon (M1/M2/M3/M4) and Intel Macs** are both supported.
- The signed public desktop release is macOS only today; there is no signed public Windows or Linux release yet.
- To build the macOS app from source: Xcode 16 / Swift 6.
- Windows contributors can build and test the portable Swift `AgentPetCore`. A Windows WPF prototype lives under [`Windows/`](Windows/) with a native C# UI, a self-contained x64 installer build path, and the same event/state model. The AppKit/SwiftUI desktop app and Sparkle updater remain macOS-only.

## Install

### Homebrew

```bash
brew install --cask ntd4996/tap/agentpet
```

### Direct download

Grab the latest `AgentPet.dmg` from [Releases](https://github.com/ntd4996/agentpet/releases), open it, and drag AgentPet to Applications.

### Build from source

macOS desktop app:

```bash
git clone https://github.com/ntd4996/agentpet.git
cd agentpet
./scripts/build-app.sh release
open build/AgentPet.app
```

Windows core build/test for contributors:

```powershell
$env:SDKROOT = "$env:LOCALAPPDATA\Programs\Swift\Platforms\6.3.2\Windows.platform\Developer\SDKs\Windows.sdk"
swift package describe
swift build --target AgentPetCore
swift test --filter AgentPetCoreTests
```

Windows prototype from source:

```powershell
& "C:\Program Files\dotnet\dotnet.exe" build "Windows\AgentPet.sln"
```

Windows self-contained installer for maintainers:

```powershell
.\Windows\scripts\build-release.ps1 -Version 0.1.0
```

This produces `Windows\publish\installer\AgentPet-Setup-x64.exe` for Windows x64 machines without requiring .NET/runtime/build tools on the target machine. The build machine needs .NET SDK 8 and Inno Setup.

To build only the WPF desktop shell:

```powershell
& "C:\Program Files\dotnet\dotnet.exe" build "Windows\src\AgentPet.Windows\AgentPet.Windows.csproj"
```

If SwiftPM reports `Invalid manifest fatalError` or `unable to load standard library` on Windows, set `SDKROOT` to the Swift Windows SDK path above and run from a Visual Studio developer shell with VC tools available. If the WPF app is running while you rebuild, stop it first or build with a temporary `BaseOutputPath` to avoid locked `bin` files.

Builds are Developer ID-signed and notarized by Apple, so they open without a Gatekeeper warning. AgentPet also updates itself: it checks for new versions automatically, and you can update in-app from the menu bar **Updates** button.

On first launch, open **Settings → General** and click **Install** next to Claude Code, then **Enable** notifications.

### Uninstall

1. In **Settings → General**, click **Remove** next to each agent you connected (this strips AgentPet's hooks from the agents' config so they don't error after the app is gone).
2. Remove the app and its data:

```bash
brew uninstall --cask agentpet          # or drag /Applications/AgentPet.app to Trash
rm -rf ~/.agentpet                       # downloaded pets + state
rm -f  ~/Library/Preferences/com.agentpet.app.plist
```

## Usage

**Claude Code** (recommended): install the hook from Settings. AgentPet then reflects each session's real state (including "waiting for input").

**Any other CLI agent**: wrap it.

```bash
agentpet run -- <your-agent-command>     # e.g. agentpet run -- aider
```

The session shows as *working* while it runs and *done* when it exits.

## Pets

Pets use the open Codex pet-pack format (`pet.json` + an 8×9 spritesheet). You can:

- **Browse** the online library and download a pet with one click (Settings → Pet → Browse pets).
- **Map animations**: pick which sheet animation plays for each state.
- **Delete** pets you no longer want.

A starter pet is installed automatically on first launch. AgentPet bundles no pet art; packs are added at runtime.

## Roadmap

- Notarized DMG + Homebrew cask
- Click an agent to reveal its terminal
- Per-project pets

## Tech

The macOS app is Swift + SwiftUI, a Unix-socket daemon for agent events, and a tiny CLI helper, all in one SwiftPM package. Portable state/event logic stays in `AgentPetCore`; platform UI stays separate. The Windows prototype uses a native C# WPF shell under [`Windows/`](Windows/) instead of trying to port SwiftUI/AppKit. See [`docs/specs`](docs/specs) for the design.

## Support

If AgentPet saves you some tab-hunting, here's how to help:

- ⭐ **[Star the repo](https://github.com/ntd4996/agentpet)** so more people find it.
- ☕ **[Buy me a coffee](https://buymeacoffee.com/ntd4996)** if you'd like to fuel more features.

Built by **[Nguyễn Thành Đạt (@ntd4996)](https://github.com/ntd4996)**.

## Acknowledgements

The Codex pet-pack format and the online pet library are provided by
**[Petdex](https://github.com/crafter-station/petdex)** (MIT). AgentPet is an
independent, interop client: it reads packs in Petdex's format and lets you
download them from Petdex's public API. AgentPet bundles no pet art; every pet
asset is owned by its respective submitter under their own license. If you hold
rights to a character, please direct takedowns to Petdex.

## License

MIT, see [LICENSE](LICENSE). Application code only; pet assets are not part of this repository.
