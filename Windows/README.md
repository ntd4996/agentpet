# AgentPet Windows prototype

This directory contains the Windows source-build prototype for AgentPet. It is not a packaged release yet.

## Architecture

AgentPet keeps platform UI separate from portable logic:

- `../Sources/AgentPetCore/` remains the portable Swift core for session state, event coding, hook parsing, and queue behavior. It must not import AppKit, SwiftUI, or Sparkle.
- `src/AgentPet.Core/` is the C# Windows event/state model used by the Windows shell while the prototype matures.
- `src/AgentPet.Cli/` is the Windows CLI hook sender.
- `src/AgentPet.Windows/` is the native Windows WPF shell: tray icon, flyout, floating pet window, and Windows assets.

Do not try to port the macOS SwiftUI/AppKit UI to Windows. Swift on Windows is useful for portable logic, but Apple's UI frameworks are not available there. If a future SwiftWin32 experiment happens, keep it isolated from the current WPF shell until it can match the same event/state contract.

## Build

From the repository root on Windows:

```powershell
& "C:\Program Files\dotnet\dotnet.exe" build "Windows\AgentPet.sln"
```

To build only the WPF desktop shell:

```powershell
& "C:\Program Files\dotnet\dotnet.exe" build "Windows\src\AgentPet.Windows\AgentPet.Windows.csproj"
```

If `AgentPet.Windows` is already running, Windows may lock files under `bin/Debug/net8.0-windows`. Stop the app before rebuilding, or build into a temporary output path:

```powershell
& "C:\Program Files\dotnet\dotnet.exe" build "Windows\AgentPet.sln" -p:BaseOutputPath="$PWD\.claude\dotnet-build\"
```

## Build a Windows installer

Maintainers can build a self-contained Windows x64 release folder and installer from the repository root:

```powershell
.\Windows\scripts\build-release.ps1 -Version 0.1.0
```

The release script:

- runs the Windows .NET tests unless `-SkipTests` is passed
- publishes `AgentPet.Windows.exe` self-contained for `win-x64`
- publishes and stages the `agentpet.exe` CLI helper beside the app
- verifies `AgentPet.Windows.exe`, `agentpet.exe`, and `Assets\app.ico`
- builds `Windows\publish\installer\AgentPet-Setup-x64.exe` when Inno Setup is installed
- supports optional code signing with `-Sign` and a certificate thumbprint

The target Windows machine does not need .NET, the .NET SDK, Inno Setup, Swift, or build tools. Only the maintainer/build machine needs .NET SDK 8 and Inno Setup (`winget install JRSoftware.InnoSetup`) to create the installer. The installer includes optional Desktop and Start-with-Windows shortcuts.

Release notes for the current Windows prototype live in [`CHANGELOG.md`](CHANGELOG.md).

If you have a Windows code-signing certificate, add `-Sign` and `-CertificateThumbprint <thumbprint>` to sign the app, CLI, and installer. The script also accepts `-SignToolPath` when `signtool.exe` is not on PATH.

```powershell
.\Windows\scripts\build-release.ps1 -Version 0.1.0 -Sign -CertificateThumbprint "YOUR_THUMBPRINT"
```

To create only the self-contained folder without Inno Setup:

```powershell
.\Windows\scripts\build-release.ps1 -Version 0.1.0 -SkipInstaller
```

## Current status

The Windows app is a native WPF prototype with a repeatable self-contained installer build path. It should not be described as feature-parity with the macOS desktop app until installer signing, update flow, and broader user-facing QA are complete.
