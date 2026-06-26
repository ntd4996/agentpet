# AgentPet Windows Handoff

_Last updated: 2026-06-25_

This file records what has been completed in this session and what should be done next before continuing the Windows desktop MVP work.

## Current goal

Build a Windows version of AgentPet that behaves like the macOS app:

- system tray monitor
- floating desktop pet
- hook/agent event ingestion
- queue fallback when app is closed
- settings/docs/verification support

The chosen approach is a **new Windows-native .NET/WPF app** beside the existing Swift macOS app. The macOS AppKit/SwiftUI app remains macOS-only.

## Completed

### 1. Windows Swift environment

Installed Windows dependencies:

- Visual Studio 2022 Community with Windows SDK and VC tools
- Swift Toolchain 6.3.2 via WinGet
- .NET SDK 8.0.422 via WinGet

Fixed SwiftPM on Windows by setting Swift SDK path:

```powershell
$env:SDKROOT = "$env:LOCALAPPDATA\Programs\Swift\Platforms\6.3.2\Windows.platform\Developer\SDKs\Windows.sdk"
[Environment]::SetEnvironmentVariable('SDKROOT', $env:SDKROOT, 'User')
```

Workspace VS Code Swift settings were added in `.vscode/settings.json` so the Swift extension can find:

- `swift.path`
- `swift.runtimePath`
- `swift.SDK`
- `sourcekit-lsp.exe`
- `SDKROOT`

### 2. AgentPetCore now builds/tests on Windows

Changed Swift package/core to support Windows core-only build:

- `Package.swift`
  - Windows exposes `AgentPetCore` and `AgentPetCoreTests` only.
  - macOS keeps `agentpet` app target, Sparkle, and app tests.
- `Sources/AgentPetCore/EventSender.swift`
  - Windows queues events instead of trying Unix sockets.
- `Sources/AgentPetCore/EventSocketServer.swift`
  - Windows `start()` throws `.unsupportedPlatform`.
  - `drainQueue()` remains cross-platform.
- `Sources/AgentPetCore/EventCoding.swift`
  - Added safer `AgentPetPaths` helpers using `FileManager`/`URL`.
- `Sources/AgentPetCore/AgentHooks.swift`
- `Sources/AgentPetCore/CodexHookConfig.swift`
- `Sources/AgentPetCore/HookInstaller.swift`
  - Replaced direct `NSHomeDirectory() + "/..."` path construction.
- `Tests/AgentPetCoreTests/EventSocketServerTests.swift`
- `Tests/AgentPetCoreTests/HookAndSenderTests.swift`
  - Unix socket live tests are non-Windows only.
  - Windows queue fallback and unsupported socket tests pass.

Verified successfully on Windows with Visual Studio dev shell + `SDKROOT`:

```powershell
swift package describe
swift build --target AgentPetCore
swift test --filter AgentPetCoreTests
```

Result:

- `AgentPetCore` build passed.
- `AgentPetCoreTests` passed: **113 tests, 0 failures**.
- There was a Windows symlink warning for `.build/debug`; it did not fail build/tests.

### 3. Documentation updated for Windows core support

Updated:

- `README.md`
- `CONTRIBUTING.md`

Current docs state:

- desktop app is still macOS-only
- Windows contributors can build/test `AgentPetCore`
- Windows needs `SDKROOT` if SwiftPM cannot find the SDK

### 4. Harness created

Created AgentPet harness files:

Agents:

- `.claude/agents/agentpet-architect.md`
- `.claude/agents/agentpet-core-engineer.md`
- `.claude/agents/agentpet-docs-curator.md`
- `.claude/agents/agentpet-qa-verifier.md`

Skills:

- `.claude/skills/agentpet-orchestrator/SKILL.md`
- `.claude/skills/agentpet-code-map/SKILL.md`
- `.claude/skills/agentpet-windows-docs/SKILL.md`
- `.claude/skills/agentpet-verify/SKILL.md`

Added:

- `CLAUDE.md`

`CLAUDE.md` points future AgentPet code/docs/Windows verification work to `agentpet-orchestrator`.

Updated:

- `.gitignore`

Added ignore rule for local Claude worktrees:

```gitignore
.claude/worktrees/
```

### 5. Windows desktop MVP planning completed

Plan approved for a Windows-native app:

- WPF desktop app
- .NET CLI helper
- C# core model/state logic matching Swift `AgentPetCore`
- named pipe IPC
- disk queue fallback
- tray icon/flyout
- floating transparent pet window

Plan file:

- `C:\Users\PC Gaming\.claude\plans\cheerful-orbiting-owl.md`

### 6. Windows .NET solution started

Created solution/projects under `Windows/`:

- `Windows/AgentPet.sln`
- `Windows/Directory.Build.props`
- `Windows/src/AgentPet.Core/AgentPet.Core.csproj`
- `Windows/src/AgentPet.Cli/AgentPet.Cli.csproj`
- `Windows/src/AgentPet.Windows/AgentPet.Windows.csproj`
- `Windows/tests/AgentPet.Core.Tests/AgentPet.Core.Tests.csproj`

Project references added:

- `AgentPet.Cli` -> `AgentPet.Core`
- `AgentPet.Windows` -> `AgentPet.Core`
- `AgentPet.Core.Tests` -> `AgentPet.Core`

Started C# core port:

- `Windows/src/AgentPet.Core/Models/AgentState.cs`
- `Windows/src/AgentPet.Core/Models/AgentKind.cs`
- `Windows/src/AgentPet.Core/Models/AgentSource.cs`
- `Windows/src/AgentPet.Core/Models/PetMood.cs`
- `Windows/src/AgentPet.Core/Models/AgentEvent.cs`
- `Windows/src/AgentPet.Core/Models/AgentSession.cs`
- `Windows/src/AgentPet.Core/State/StateMapper.cs`

### 7. Windows .NET core port completed

Added the first buildable/tested `AgentPet.Core` implementation:

- `Windows/src/AgentPet.Core/State/SessionStore.cs`
- `Windows/src/AgentPet.Core/State/MoodResolver.cs`
- `Windows/src/AgentPet.Core/Text/TickerFormatter.cs`
- `Windows/src/AgentPet.Core/Paths/AgentPetPaths.cs`
- `Windows/src/AgentPet.Core/Events/EventCoding.cs`
- `Windows/src/AgentPet.Core/Events/EventQueue.cs`
- `Windows/src/AgentPet.Core/Events/EventPipeClient.cs`
- `Windows/src/AgentPet.Core/Events/EventPipeServer.cs`
- `Windows/src/AgentPet.Core/Events/EventSender.cs`

Updated `Windows/src/AgentPet.Core/Models/AgentEvent.cs` so `System.Text.Json` can deserialize Swift-shaped event JSON.

Added .NET tests for:

- paths
- state mapping
- session store behavior
- mood resolution
- ticker formatting
- Swift-compatible event JSON coding
- disk queue fallback/drain
- named pipe send/receive

Verified on Windows with installed .NET SDK at `C:\Program Files\dotnet\dotnet.exe`:

```powershell
& "C:\Program Files\dotnet\dotnet.exe" restore "Windows/AgentPet.sln"
& "C:\Program Files\dotnet\dotnet.exe" build "Windows/AgentPet.sln" --no-restore
& "C:\Program Files\dotnet\dotnet.exe" test "Windows/AgentPet.sln" --no-build
```

Result:

- restore passed
- solution build passed
- tests passed: **36 tests, 0 failures**

Note: `dotnet` was not available on `PATH` in the current shell, but the SDK exists at `C:\Program Files\dotnet\dotnet.exe`.

### 8. Windows CLI helper implemented

Implemented `agentpet hook ...`:

- `Windows/src/AgentPet.Cli/Program.cs`
- `Windows/src/AgentPet.Cli/Commands/HookCommand.cs`

Supported options:

- `--agent <name>`
- `--event <name>`
- `--session <id>`
- `--project <path>`
- `--message <text>`
- `--transcript <path>`
- `--timestamp <unix-seconds>`
- `--pipe-name <name>` for tests/smoke overrides
- `--queue-dir <path>` for tests/smoke overrides

Behavior:

- builds an `AgentEvent`
- sends via named pipe using `EventSender`
- falls back to disk queue when app/server is closed
- exits `0` when event is delivered or queued
- exits `1` for invalid/missing arguments

Verified CLI queue fallback with:

```powershell
Windows/src/AgentPet.Cli/bin/Debug/net8.0/agentpet.exe hook --agent claude --event UserPromptSubmit --session win-test --project "C:\dev\demo" --message "hello from cli" --timestamp 123 --pipe-name "agentpet-smoke-missing" --queue-dir <temp>
```

Result:

- command exited `0`
- one queue file was written
- JSON contained lowercase `"agentKind":"claude"` and numeric `"timestamp":123`

Re-ran verification after CLI implementation:

```powershell
& "C:\Program Files\dotnet\dotnet.exe" build "Windows/AgentPet.sln" --no-restore
& "C:\Program Files\dotnet\dotnet.exe" test "Windows/AgentPet.sln" --no-build
```

Result:

- solution build passed
- tests passed: **36 tests, 0 failures**

### 9. WPF desktop MVP implemented

Added the first Windows desktop loop:

- `Windows/src/AgentPet.Windows/App.xaml`
- `Windows/src/AgentPet.Windows/App.xaml.cs`
- `Windows/src/AgentPet.Windows/Services/AppDaemon.cs`
- `Windows/src/AgentPet.Windows/Services/TrayIconService.cs`
- `Windows/src/AgentPet.Windows/ViewModels/ViewModelBase.cs`
- `Windows/src/AgentPet.Windows/ViewModels/TrayViewModel.cs`
- `Windows/src/AgentPet.Windows/ViewModels/PetViewModel.cs`
- `Windows/src/AgentPet.Windows/Windows/TrayFlyoutWindow.xaml`
- `Windows/src/AgentPet.Windows/Windows/TrayFlyoutWindow.xaml.cs`
- `Windows/src/AgentPet.Windows/Windows/PetWindow.xaml`
- `Windows/src/AgentPet.Windows/Windows/PetWindow.xaml.cs`

Behavior now included:

- starts a named-pipe daemon using `AgentPetPaths.PipeName`
- drains queued events on app launch
- maintains sessions with `SessionStore`
- shows a Windows tray icon with Show/Hide/Exit menu
- shows a minimal floating transparent pet window
- shows a tray flyout/session list
- updates pet mood/status from working/waiting/done events

Verified after WPF implementation:

```powershell
& "C:\Program Files\dotnet\dotnet.exe" build "Windows/AgentPet.sln" --no-restore
& "C:\Program Files\dotnet\dotnet.exe" test "Windows/AgentPet.sln" --no-build
```

Result:

- solution build passed
- tests passed: **36 tests, 0 failures**

Smoke test run:

```powershell
Windows/src/AgentPet.Windows/bin/Debug/net8.0-windows/AgentPet.Windows.exe
Windows/src/AgentPet.Cli/bin/Debug/net8.0/agentpet.exe hook --agent claude --event UserPromptSubmit --session win-test --project "C:\dev\demo" --message "smoke start" --timestamp 123 --queue-dir <temp>
Windows/src/AgentPet.Cli/bin/Debug/net8.0/agentpet.exe hook --agent claude --event Notification --session win-test --project "C:\dev\demo" --message "Approve command?" --timestamp 124 --queue-dir <temp>
Windows/src/AgentPet.Cli/bin/Debug/net8.0/agentpet.exe hook --agent claude --event Stop --session win-test --project "C:\dev\demo" --timestamp 125 --queue-dir <temp>
```

Result:

- app process launched
- CLI commands exited `0,0,0`
- queue count remained `0`, confirming live named-pipe delivery

Manual visual verification is still recommended because the automated smoke only confirmed app launch + live pipe delivery, not visual tray/pet/flyout rendering.

### 10. Windows sprite-frame pet animation added

Ported the macOS pet animation model to WPF:

- `Windows/src/AgentPet.Windows/Controls/SpritePetView.cs`
- `Windows/src/AgentPet.Windows/Assets/default-pet.png`
- `Windows/src/AgentPet.Windows/Windows/PetWindow.xaml`
- `Windows/src/AgentPet.Windows/AgentPet.Windows.csproj`

Behavior:

- reads pet packs from `%USERPROFILE%\.agentpet\pets\*/pet.json`, matching macOS `~/.agentpet/pets`
- slices transparent spritesheets by alpha gutters, matching `Sources/App/SpriteSlicer.swift`
- maps mood to clip rows in the same order as macOS `PetBindings.defaults`: idle, working, waiting, done, celebrate
- cycles frames with the same FPS as macOS `ImageSpriteView`: working/celebrate 8 FPS, waiting 4 FPS, idle/done 3 FPS
- falls back to bundled `default-pet.png` when no imported pet pack exists

Verified after sprite renderer implementation:

```powershell
Get-Process AgentPet.Windows -ErrorAction SilentlyContinue | Stop-Process -Force
& "C:\Program Files\dotnet\dotnet.exe" build "Windows/AgentPet.sln" --no-restore
& "C:\Program Files\dotnet\dotnet.exe" test "Windows/AgentPet.sln" --no-build
```

Result:

- solution build passed
- tests passed: **36 tests, 0 failures**

Launched the updated app and sent `UserPromptSubmit` then `Notification` test events to show working/waiting sprite clips. App process was left running for visual inspection.

### 11. Windows fixed-grid pet pack slicing and Goku pack repaired

Updated the Windows sprite renderer for generated/local packs that already match the AgentPet fixed-grid spec:

- `Windows/src/AgentPet.Windows/Controls/SpritePetView.cs`
  - if a spritesheet is exactly `1536 x 1872`, slice it as a fixed `8 x 9` grid of `192 x 208` cells
  - only fall back to alpha-gutter slicing for non-fixed-grid sheets
- `Windows/src/AgentPet.Windows/Services/PetCatalogService.cs`
  - thumbnails for `1536 x 1872` sheets now use the first `192 x 208` frame directly, avoiding alpha-slicer thumbnail mis-crops

Repaired the local generated Goku pack at:

```text
C:\Users\PC Gaming\AppData\Local\AgentPet\pets\goku-generated\
```

Important asset workflow learned:

- Do **not** add invisible/low-alpha guide lines to force alpha slicing. The Windows alpha slicer treats any alpha as content and can split/crop cards or effects incorrectly.
- For sheets already matching the fixed spec (`1536 x 1872`, `8 x 9`, `192 x 208`), use fixed-grid slicing in the app.
- When repairing AI-generated source images:
  - use A1 -> A4 source images in animation order instead of relying on only A3
  - A1/A2 were RGB/white-background sources; background removal must preserve enclosed whites such as eyes/highlights
  - A3/A4 were transparent but their poses/effects crossed naive `192px` column boundaries; detect alpha components/pose centers instead of splitting the original image into equal columns
  - crop each detected pose with safety margins, preserve aspect ratio, then fit into a transparent `192 x 208` cell

Generated outputs left in the local pack include:

- `spritesheet.png` — repaired clean fixed-grid sheet, no guide lines
- `_a1_a4_crop-preview-v2.png` — source crop preview that the user confirmed looked good
- `_spritesheet-preview-small.png` — compact sheet preview
- timestamped `spritesheet.backup-*` files — older generated sheets retained as backups

Pet settings preview follow-up:

- `Windows/src/AgentPet.Windows/MainWindow.xaml`
  - selected pet summary now renders the selected spritesheet with `SpritePetView` instead of a static thumbnail
  - the preview binds `Mood` to a settings preview mood so the user can see non-idle rows
- `Windows/src/AgentPet.Windows/ViewModels/SettingsViewModel.cs`
  - added a preview timer cycling `idle -> working -> waiting -> done -> celebrate`
  - the `Live preview` button now toggles this preview cycle

Reason: `SpritePetView` chooses rows by `Mood`; without live agent events, settings stayed on `idle`, so Goku appeared to only perform A1/row 0 even though A2-A4 rows were present in the sheet. Follow-up wiring connects `SettingsViewModel.PreviewMoodChanged` to `PetViewModel.SetPreviewMood`, so the actual floating pet window also cycles preview moods while Live preview is active. Pausing Live preview clears the preview override and returns the floating pet to real session-driven mood.

Verification performed:

```powershell
& "C:\Program Files\dotnet\dotnet.exe" build "Windows/src/AgentPet.Windows/AgentPet.Windows.csproj"
Start-Process -FilePath "E:\TOOL DUNG CODE\PET-agent\Windows\src\AgentPet.Windows\bin\Debug\net8.0-windows\AgentPet.Windows.exe"
```

Result:

- Windows app project build passed after preview-cycle/floating-pet wiring changes: **0 warnings, 0 errors**
- stopped previous `AgentPet.Windows.exe` process `8220`, relaunched the rebuilt app, and observed process `8344` running
- user visually confirmed the regenerated Goku sprite sheet looked good; preview-cycle change was added so both the settings screen and floating pet can show non-idle rows without live agent events

### 12. Windows UI shifted to Vietnamese reminder-pet MVP

Implemented the first reminder-first Windows prototype direction:

- `Windows/src/AgentPet.Windows/Models/ReminderSettings.cs`
  - stores morning/afternoon reminder slots, task text, time windows, pet size, bubble settings
- `Windows/src/AgentPet.Windows/Services/ReminderSettingsService.cs`
  - persists `%LOCALAPPDATA%/AgentPet/settings.json`
  - falls back to Vietnamese defaults if the file is missing or invalid
- `Windows/src/AgentPet.Windows/Services/ReminderSchedulerService.cs`
  - checks active reminder windows with a `DispatcherTimer`
  - fires at most once per slot/day in memory
- `Windows/src/AgentPet.Windows/ViewModels/SettingsViewModel.cs`
  - now owns Vietnamese tab state, reminder fields, bubble settings, pet size, save/test/preview commands
- `Windows/src/AgentPet.Windows/ViewModels/PetViewModel.cs`
  - supports pet-size binding and temporary Vietnamese reminder bubbles
- `Windows/src/AgentPet.Windows/MainWindow.xaml`
  - General/Pet/Bubble/About tabs are now Vietnamese and clickable
  - General tab configures morning/afternoon reminders and pet size
  - Bubble tab configures reminder bubble behavior
  - About tab describes the reminder-pet direction
- `Windows/src/AgentPet.Windows/Windows/PetWindow.xaml`
  - floating pet size now binds to settings instead of hardcoded `170`
- `Windows/src/AgentPet.Windows/Services/TrayIconService.cs`
- `Windows/src/AgentPet.Windows/ViewModels/TrayViewModel.cs`
  - tray copy moved toward Vietnamese/reminder-first wording

Follow-up refinement after user feedback:

- reminder slots now support multiple tasks per morning/afternoon instead of one task per buổi
- each task has `Enabled`, task text, and dropdown-selected `FromTime`/`ToTime`
- time selection uses 15-minute `ComboBox` options instead of raw text fields
- Bubble tab now includes `Tôi nên gọi bạn là gì?` plus editable greeting/reminder/encouragement phrases
- reminder phrase supports `{name}` and `{task}` placeholders
- About tab now credits: `Được phát triển bởi Leon • 93 MEDIA`

Latest verification:

```powershell
& "C:\Program Files\dotnet\dotnet.exe" build "Windows/src/AgentPet.Windows/AgentPet.Windows.csproj"
& "C:\Program Files\dotnet\dotnet.exe" test "Windows/tests/AgentPet.Core.Tests/AgentPet.Core.Tests.csproj"
```

Result:

- Windows app build passed: **0 warnings, 0 errors**
- Windows core tests passed: **36 tests, 0 failures**
- relaunched `AgentPet.Windows.exe`; process observed as PID `10000`

UX refinement after visual review:

- task cards were softened with darker rounded cards and clearer text inputs
- floating pet reminder bubbles now wrap long reminder text instead of trimming with ellipses
- pet window supports interactions:
  - single click: pet responds with a short helper bubble
  - double click: pet responds with an encouragement bubble and celebrate mood
- latest verification after UX refinement:
  - Windows app build passed: **0 warnings, 0 errors**
  - Windows core tests passed: **36 tests, 0 failures**
  - relaunched `AgentPet.Windows.exe`; process observed as PID `9096`

Animation/flicker refinement:

- `SpritePetView` now keeps the current source when mood clips are temporarily unavailable instead of clearing to `null`
- mood changes no longer reset to frame 0; they reuse the current frame index modulo the new row
- mood changes use a short opacity ease from `0.86 -> 1.0` instead of a hard source jump
- `PetWindow` now uses a fixed manual window size to avoid `SizeToContent` re-measuring/reposition flicker when the bubble or pet sprite changes
- pet click interactions now add subtle scale animations:
  - single click: helper bubble + small pulse
  - double click: encouragement bubble + larger celebrate pulse
- latest verification after animation/flicker refinement:
  - Windows app build passed: **0 warnings, 0 errors**
  - Windows core tests passed: **36 tests, 0 failures**
  - relaunched `AgentPet.Windows.exe`; process observed as PID `27864`

Name/dropdown/flicker follow-up:

- bubble preview and scheduler now replace both `{name}` and literal `bạn` with the configured user display name, so saved names such as `Dũng` apply to default sentences too
- `SpritePetView` cleanup removed a stray tool-text artifact and restored valid C# syntax
- `SpritePetView` skips alpha-empty frames and keeps the previous source instead of showing a blank frame, reducing blink at the end of animation rows
- time dropdowns have an app-specific style applied instead of plain unstyled ComboBoxes
- latest verification after follow-up:
  - Windows app build passed: **0 warnings, 0 errors**
  - Windows core tests passed: **36 tests, 0 failures**
  - relaunched `AgentPet.Windows.exe`; process observed as PID `26864`

The AI coding event loop is still present via `AppDaemon`; the Windows UI now presents reminders as the primary product direction instead of agent monitoring.

## Important current state

The Windows .NET MVP now builds/tests and has the first live CLI -> named pipe -> WPF daemon loop plus sprite-frame pet animation. It is still an MVP: imported pet browser/settings/installer/parity work is deferred, but the pet renderer now follows the macOS sprite-frame animation model rather than a static glyph.

The Windows sprite renderer also supports clean fixed-grid generated packs. The local `goku-generated` pack has been repaired with an A1->A4 source workflow and should be kept free of invisible alpha guide lines.

The Windows UI is now evolving into a Vietnamese personal work-reminder pet. Continue from the reminder MVP implementation, not the older AI-coding-only settings UI.

The next session should continue from the Windows MVP implementation, not restart planning.

## Next steps

### Immediate next steps

1. Manually verify visual WPF behavior:
   - tray icon appears
   - floating pet appears
   - tray flyout opens from tray menu/double-click
   - flyout/session list updates after CLI hook events
   - pet mood/status changes for working/waiting/done
   - queued events drain on app launch

2. Add tests for CLI/WPF integration paths as behavior is implemented.

3. Run verification after each increment:

```powershell
& "C:\Program Files\dotnet\dotnet.exe" restore "Windows/AgentPet.sln"
& "C:\Program Files\dotnet\dotnet.exe" build "Windows/AgentPet.sln"
& "C:\Program Files\dotnet\dotnet.exe" test "Windows/AgentPet.sln"
```

4. Manual smoke test after build works:

```powershell
# launch app
Windows/src/AgentPet.Windows/bin/Debug/net8.0-windows/AgentPet.Windows.exe

# send events
Windows/src/AgentPet.Cli/bin/Debug/net8.0/agentpet.exe hook --agent claude --event UserPromptSubmit --session win-test --project "C:\dev\demo"
Windows/src/AgentPet.Cli/bin/Debug/net8.0/agentpet.exe hook --agent claude --event Notification --session win-test --project "C:\dev\demo" --message "Approve command?"
Windows/src/AgentPet.Cli/bin/Debug/net8.0/agentpet.exe hook --agent claude --event Stop --session win-test --project "C:\dev\demo"
```

Expected smoke result:

- tray icon appears
- floating pet appears
- flyout/session list updates
- pet mood changes for working/waiting/done
- queued events drain on app launch

## Deferred work

Do not implement these until the first loop works:

- full pet gallery/browser
- full settings parity
- all agent installers
- `agentpet run -- <command>` parity
- installer/updater/MSIX/winget
- launch at login
- sound customization
- WSL-specific integration
- localized Windows docs

## Notes for future agent

- Use `agentpet-orchestrator` skill for further AgentPet work.
- Do not claim full Windows support until the WPF app builds/runs and smoke test passes.
- Keep macOS app behavior untouched unless explicitly requested.
- Treat Swift `AgentPetCore` as behavior reference for the C# port.
- If SwiftPM fails on Windows, check `SDKROOT` first.

## New verified Windows release state

The Windows WPF prototype now has a repeatable self-contained release path:

- `Windows/scripts/build-release.ps1`
- `Windows/installer/AgentPet.iss`
- `Windows/CHANGELOG.md`
- published self-contained folder: `Windows/publish/AgentPet.Windows-win-x64`
- installer output: `Windows/publish/installer/AgentPet-Setup-x64.exe`

Verified on this machine:

```powershell
& "C:\Program Files\dotnet\dotnet.exe" test "Windows\AgentPet.sln" -c Release
& "C:\Program Files\dotnet\dotnet.exe" build "Windows\src\AgentPet.Windows\AgentPet.Windows.csproj" -c Release
.\Windows\scripts\build-release.ps1 -Version 0.1.0 -SkipInstaller
.\Windows\scripts\build-release.ps1 -Version 0.1.0 -SkipTests
```

Result:

- Windows solution tests passed: **36 tests, 0 failures**
- Windows WPF app Release build passed: **0 warnings, 0 errors**
- self-contained publish completed successfully
- installer compile completed successfully
- resulting installer SHA256 after update-check, bubble-size, and click/edge fixes: `28CCD78818F8BDD5F26764A43D99CA42BD27C536D7FBEDF209B9ABF143FD8002`
- installer is currently unsigned, but the build script now supports optional signing with `-Sign`, `-CertificateThumbprint`, and `-SignToolPath`
- installer now offers optional Desktop and Start-with-Windows shortcuts
- pet window drag behavior now uses custom cursor-anchored dragging instead of WPF `DragMove`; it clamps the actual pet sprite to the work area so it stays recoverable, reminder/click actions no longer reset the user-chosen position, and the bubble moves below the pet near the top edge after layout/render updates

Reminder workflow update:

- click 1 = show việc đang làm
- click 2 = show việc kế tiếp
- click 3 = hoàn thành việc hiện tại và chuyển sang việc kế tiếp
- reminder scheduler now emits 15 / 10 / 5 minute warnings and plays an alert sound
- About tab now documents the click workflow and reminder behavior

The next session should continue from the release installer verification state, not restart planning.
