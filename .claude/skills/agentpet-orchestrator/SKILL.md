---
name: agentpet-orchestrator
description: Use this for AgentPet repo work involving Swift code edits, Windows support, docs updates, build/test verification, or follow-up harness updates. Trigger aggressively for requests like chỉnh sửa file/chức năng, port Windows, update docs, check docs, verify build, refine harness, rerun/update/fix previous AgentPet work. Do not use for unrelated generic questions.
---

# AgentPet Orchestrator

Use this skill to coordinate precise AgentPet changes across code, tests, and docs.

## Phase 0: Context check

1. Inspect current diff before editing.
2. Classify the request as one or more scopes:
   - `core`: `Sources/AgentPetCore/`, `Tests/AgentPetCoreTests/`
   - `mac-app`: `Sources/App/`, app tests, Sparkle, AppKit/SwiftUI
   - `windows`: SwiftPM Windows, SDKROOT, queue fallback, future CLI/UI
   - `windows-pet-art`: WPF sprite renderer, local generated pet packs, fixed-grid/alpha slicing, `%LOCALAPPDATA%/AgentPet/pets/*`
   - `windows-reminder`: Vietnamese Windows reminder-pet UI, morning/afternoon reminders, bubble reminders, pet size settings, `%LOCALAPPDATA%/AgentPet/settings.json`
   - `docs`: README, CONTRIBUTING, localized readmes, web install copy
   - `harness`: `.claude/agents/`, `.claude/skills/`, `CLAUDE.md`
3. If `_workspace/` exists and the user asks for a partial update, reuse previous artifacts. Otherwise continue from repository state.

## Team pattern

Default to a small expert team:

- `agentpet-architect` for scope and sequencing
- `agentpet-core-engineer` for Swift core/source edits
- `agentpet-docs-curator` for docs and Windows claims
- `agentpet-qa-verifier` for build/test verification

When invoking agents, use `model: "opus"` for harness-quality work. If the platform only exposes built-in agent types, pass the relevant role brief from `.claude/agents/*.md` into the agent prompt.

## Execution workflow

1. **Plan** — architect identifies exact files and out-of-scope areas.
2. **Implement** — code engineer edits only necessary files.
3. **Verify** — QA runs focused commands after each module-level change.
4. **Document** — docs curator updates only claims backed by verification.
5. **Final check** — summarize files changed, commands run, warnings, and follow-ups.

## Windows pet art / spritesheet workflow

Use this when repairing or generating local Windows pet packs under `%LOCALAPPDATA%/AgentPet/pets/*`.

- If a spritesheet is exactly `1536 x 1872`, treat it as the AgentPet fixed-grid spec: `8 x 9` cells, each `192 x 208`.
- The Windows WPF renderer should fixed-grid slice exact-spec sheets before falling back to alpha-gutter slicing.
- `SpritePetView` chooses animation rows by `Mood`; settings/live previews must cycle or simulate moods to show non-idle rows. If a preview only shows A1/row 0, inspect the preview mood binding before regenerating art. For the floating pet, ensure settings preview mood is wired through to `PetViewModel`, not only to the small settings preview control.
- Do **not** add invisible/low-alpha guide lines to force alpha slicing. The alpha slicer treats guides/effects as content and can split/crop cards or pets incorrectly.
- For AI source images like the local `goku-generated` pack:
  - use A1 -> A4 source images in animation order rather than relying on only one source image
  - for RGB/white-background sources, remove only outside-connected canvas and preserve enclosed whites such as eyes/highlights
  - for transparent sources whose poses cross naive cell boundaries, detect alpha components/pose centers instead of splitting into equal original-source columns
  - crop each pose with safety margins, preserve aspect ratio, fit into `192 x 208`, and verify no cell is empty or edge-clipped
- If the app executable is locked during build, stop `AgentPet.Windows` first or build to a temporary output path; use `C:\Program Files\dotnet\dotnet.exe` because `dotnet` may not be on PATH.

Relevant files:

- `Windows/src/AgentPet.Windows/Controls/SpritePetView.cs` — fixed-grid and alpha slicing
- `Windows/src/AgentPet.Windows/Services/PetCatalogService.cs` — pet catalog thumbnails
- `.claude/goku-ai-spritesheet-prompt.md` — generated Goku fixed-grid prompt/spec
- `HANDOFF.md` — latest verified Windows MVP and pet-art status

## Windows reminder-pet UI direction

The Windows WPF prototype is moving toward a Vietnamese personal work-reminder pet while preserving the existing AI event loop in the background.

- Keep user-facing Windows UI copy Vietnamese unless the user asks for localization/multi-language support.
- Reminder settings live in `%LOCALAPPDATA%/AgentPet/settings.json` and are Windows-only MVP settings.
- General/Cài đặt should configure multiple morning and afternoon reminder tasks, each with task text plus dropdown-selected `HH:mm` start/end windows, and pet size.
- Bubble/Bong bóng should configure reminder-bubble visibility, duration, user display name, and editable communication phrases using `{name}` and `{task}` placeholders.
- Reminder bubbles should wrap full text; do not truncate long task names with ellipses.
- To reduce flicker, prefer fixed pet-window sizing over `SizeToContent` when the sprite or bubble changes; if mood rows are animated, avoid clearing the image source during transitions.
- Floating pet interactions should stay friendly: single click can show a helper bubble, double click can show encouragement/celebrate.
- Prefer pet bubble reminders first; Windows toast notifications are deferred unless explicitly requested.
- Do not remove `AppDaemon`/named-pipe agent behavior without explicit approval; the UI is reminder-first, not necessarily agent-free.

Relevant files:

- `Windows/src/AgentPet.Windows/MainWindow.xaml` — Vietnamese settings tabs
- `Windows/src/AgentPet.Windows/ViewModels/SettingsViewModel.cs` — reminder settings, tab commands, pet selection
- `Windows/src/AgentPet.Windows/ViewModels/PetViewModel.cs` — floating pet mood/size/reminder bubbles
- `Windows/src/AgentPet.Windows/Models/ReminderSettings.cs` — persisted reminder settings model
- `Windows/src/AgentPet.Windows/Services/ReminderSettingsService.cs` — JSON persistence
- `Windows/src/AgentPet.Windows/Services/ReminderSchedulerService.cs` — timer-based reminder checks

## Windows Swift verification

On this machine, SwiftPM needs Visual Studio dev shell and `SDKROOT` pointing at Swift's Windows SDK. Use the command pattern from `.claude/agents/agentpet-qa-verifier.md`.

Key commands:

```powershell
swift package describe
swift build --target AgentPetCore
swift test --filter AgentPetCoreTests
```

If `Invalid manifest fatalError` or `unable to load standard library` appears, set:

```powershell
$env:SDKROOT = "$env:LOCALAPPDATA\Programs\Swift\Platforms\6.3.2\Windows.platform\Developer\SDKs\Windows.sdk"
```

## Guardrails

- Do not claim full Windows desktop support until a Windows UI/app exists.
- Do not port macOS AppKit/Sparkle code unless explicitly requested.
- Keep macOS app targets macOS-only.
- Keep docs and verification aligned; unverified future work must be labeled future/planned.

## Error handling

- One retry is allowed after fixing environment or obvious compile errors.
- If verification is skipped, say why and list the exact command the user should run.
- If docs and code disagree, fix docs after verifying actual behavior.

## Test scenarios

### Normal flow

User asks: “cập nhật docs Windows sau khi core build được”. The orchestrator verifies Windows build/test, updates README/CONTRIBUTING with core-only support, and does not mark desktop Windows as released.

### Error flow

User asks: “fix Swift build Windows” and SwiftPM fails with `Invalid manifest fatalError`. The orchestrator routes to QA first, checks `SDKROOT`, then only edits source if the toolchain is healthy and compile errors remain.
