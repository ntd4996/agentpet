# CLAUDE.md

## Harness: AgentPet Windows/Core & Docs

**Goal:** Coordinate precise AgentPet Swift core edits, Windows build verification, and documentation updates without overstating Windows desktop support.

**Current implementation direction:**
- Keep portable logic in `Sources/AgentPetCore/` and the Windows event/state model in `Windows/src/AgentPet.Core/`.
- Keep macOS UI in `Sources/App/`.
- Keep the Windows prototype UI in `Windows/src/AgentPet.Windows/` as a native C# WPF shell.
- For Windows/generated pet art, exact `1536×1872` sheets are fixed-grid `8×9` (`192×208` cells); avoid alpha guide lines and make both settings and floating-pet previews cycle `Mood` so non-idle rows are visible.
- The Windows WPF prototype is moving toward a Vietnamese personal work-reminder pet: General/Cài đặt configures morning/afternoon reminders and pet size; Bubble/Bong bóng configures reminder bubbles; keep the AI event loop available in the background unless explicitly removed.
- Do not port SwiftUI/AppKit to Windows; treat SwiftWin32 as future experimentation only unless explicitly requested.
- When docs mention Windows, distinguish Swift `AgentPetCore` support, the source-build Windows prototype, and a released Windows desktop product.

**Trigger:** For AgentPet code edits, file/function mapping, Windows support, Swift build/test verification, docs checks, docs updates, or harness follow-up work, use the `agentpet-orchestrator` skill. Simple one-off questions can be answered directly.

**Change history:**
| Date | Change | Target | Reason |
|------|--------|--------|--------|
| 2026-06-25 | Initial AgentPet harness setup | `.claude/agents/`, `.claude/skills/`, `CLAUDE.md` | Support precise code edits, Windows core verification, and docs updates |
| 2026-06-26 | Windows pet-art workflow update | `Windows/src/AgentPet.Windows/`, `.claude/skills/agentpet-orchestrator/`, `HANDOFF.md` | Fixed-grid generated sheets, A1-A4 crop repair, and mood-cycling live previews |
| 2026-06-26 | Windows reminder-pet direction | `Windows/src/AgentPet.Windows/`, `.claude/skills/agentpet-orchestrator/`, `HANDOFF.md` | Vietnamese reminder-first UI, morning/afternoon reminders, bubble settings, and pet size controls |
