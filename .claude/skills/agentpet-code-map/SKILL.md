---
name: agentpet-code-map
description: Use whenever editing or locating AgentPet files/functions: SwiftPM targets, AgentPetCore events/hooks/session logic, macOS AppKit app boundaries, tests, CI, or packaging scripts. Must trigger before broad code edits, refactors, or questions like file nào xử lý chức năng này.
---

# AgentPet Code Map

Use this skill to find the right files before editing.

## Repository areas

- `Package.swift` — SwiftPM targets and platform gates.
- `Sources/AgentPetCore/` — portable model/event/hook/session logic.
- `Sources/App/` — macOS-only SwiftUI/AppKit app, settings, pet window, menu bar, Sparkle updater.
- `Tests/AgentPetCoreTests/` — portable tests. Windows socket live tests should be guarded out.
- `Tests/AgentPetAppTests/` — macOS app tests.
- `scripts/` — macOS app/DMG/release tooling.
- `web/` — Astro/Cloudflare marketing/gallery/install site.
- `docs/` and `docs/readme/` — release and localized docs.

## Fast routing

- Event JSON encoding/paths: `Sources/AgentPetCore/EventCoding.swift`
- Queue/socket send: `Sources/AgentPetCore/EventSender.swift`
- Daemon socket server/queue drain: `Sources/AgentPetCore/EventSocketServer.swift`
- Hook locations/specs: `Sources/AgentPetCore/AgentHooks.swift`
- Hook install/uninstall transforms: `Sources/AgentPetCore/HookInstaller.swift`
- Codex config transform: `Sources/AgentPetCore/CodexHookConfig.swift`
- Session state: `Sources/AgentPetCore/SessionStore.swift`, `StateMapper.swift`, `AgentSession.swift`
- Transcript parsing: `Sources/AgentPetCore/TranscriptReader.swift`
- macOS entry/UI: `Sources/App/AppEntry.swift`, `AgentPetApp.swift`, `PetWindowController.swift`, `StatusBarController.swift`
- Windows verification tests: `Tests/AgentPetCoreTests/EventSocketServerTests.swift`, `HookAndSenderTests.swift`

## Editing rules

- Read the exact target file before editing.
- Prefer small edits matching surrounding style.
- Keep platform guards close to platform-specific code.
- For path changes, prefer `URL.appendingPathComponent` and `FileManager`.
- For target layout changes, update tests and docs together.

## Output checklist

When done mapping, report:

- likely files to modify
- files intentionally not touched
- tests to run
- docs that may need update
