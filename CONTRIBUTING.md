# Contributing to AgentPet

Thanks for your interest in improving AgentPet! Contributions of all sizes are welcome.

## Getting started

macOS full app build:

```bash
git clone https://github.com/ntd4996/agentpet.git
cd agentpet
swift build          # build the macOS package targets
swift test           # run the test suite
./scripts/build-app.sh release   # produce AgentPet.app
open build/AgentPet.app
```

Requires macOS 13+ and a recent Swift toolchain (Swift 6 / Xcode 15+).

Windows core build/test:

```powershell
git clone https://github.com/ntd4996/agentpet.git
cd agentpet
$env:SDKROOT = "$env:LOCALAPPDATA\Programs\Swift\Platforms\6.3.2\Windows.platform\Developer\SDKs\Windows.sdk"
swift package describe
swift build --target AgentPetCore
swift test --filter AgentPetCoreTests
```

Windows support has two tracks: the portable Swift `AgentPetCore` can be built/tested on Windows, and the Windows prototype in `Windows/` uses a native C# WPF shell. The WPF shell has a self-contained installer build path for Windows x64, while the Sparkle updater and macOS packaging scripts remain macOS-only.

To build the Windows WPF prototype installer from the repository root:

```powershell
.\Windows\scripts\build-release.ps1 -Version 0.1.0
```

The generated installer is self-contained for end users; the build machine needs .NET SDK 8 and Inno Setup. Use `-SkipInstaller` to publish only the self-contained app folder. The installer includes optional Desktop and Start-with-Windows shortcuts. Use `-Sign -CertificateThumbprint <thumbprint>` when building with a Windows code-signing certificate.

If SwiftPM reports `Invalid manifest fatalError` or `unable to load standard library` on Windows, set `SDKROOT` to the Swift Windows SDK path above. If `link` is missing, run the commands from a Visual Studio developer shell with Windows SDK and VC tools installed.

## Project layout

- `Sources/AgentPetCore/` — pure, testable Swift core: session state, event model, hook
  parsing/installing, queue fallback, and the non-Windows Unix-socket server. No AppKit/SwiftUI here.
- `Sources/App/` — the macOS app: menu bar, floating pet, Settings, controllers.
- `Windows/src/AgentPet.Core/` — C# port/shim for the shared Windows event/state model while the Windows shell is developed.
- `Windows/src/AgentPet.Windows/` — native Windows WPF prototype: tray icon, flyout, floating pet, and Windows resource assets.
- `Windows/src/AgentPet.Cli/` — Windows CLI hook sender for the same event model.
- `Tests/AgentPetCoreTests/` — unit tests for the Swift core.
- `scripts/` — macOS app packaging and asset generation.

The split keeps logic independent of UI. Do not port AppKit/SwiftUI to Windows; keep macOS UI in `Sources/App/` and Windows UI in `Windows/src/AgentPet.Windows/`. SwiftWin32 can be explored later, but it is not the current Windows UI path.

## Guidelines

- Keep changes focused; match the surrounding style.
- Add or update tests in `AgentPetCore` for Swift core behavior changes.
- Keep platform UI changes in their platform directory: AppKit/SwiftUI in `Sources/App/`, WPF in `Windows/src/AgentPet.Windows/`.
- Run `swift test` before opening a PR; for Windows changes also run `dotnet build Windows/AgentPet.sln` (or the WPF project build for UI-only changes).
- Conventional commit messages (`feat:`, `fix:`, `docs:`, `refactor:`...).

## Pets

AgentPet bundles no pet art. Pets use the open Codex pet-pack format
(`pet.json` + an 8×9 spritesheet) and are added at runtime via Browse or import.
Please do not commit pet assets to this repository.

## Reporting issues

Open an issue with steps to reproduce, your macOS version, and which agent
(Claude Code / Codex / Gemini CLI) you were running.
