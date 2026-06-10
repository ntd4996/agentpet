# Model bubble token design

## Problem

The bubble (menu-bar and pet) shows agent-kind icon, project, title,
activity message, etc. via the token-based `BubbleLayout` system
(`Sources/App/BubbleSettings.swift`, `BubbleToken` enum, rendered by
`AgentRow` in `PetView.swift`). It currently has no way to show *which LLM
model* an agent session is using (e.g. "Sonnet 4.6", "GPT-5.1").

## Confirmed facts

- Claude Code hook payloads (and other agents using the same `claudeNested`
  hook style — Codex, Gemini CLI, opencode, Copilot, Kiro, all decoded via
  `ClaudeHookPayload` per `HookPayload.event`'s `default:` case) are
  documented to include a top-level `model` object on most hook events,
  shaped `{"id": "...", "display_name": "..."}`. The exact shape across all
  these agents/events is **not independently verified** in this repo.
- Cursor (`CursorHookPayload`), Windsurf (`WindsurfHookPayload`), and
  Antigravity (`AntigravityHookPayload`) payload shapes are unconfirmed to
  carry any model field at all.
- `AgentEvent` and `AgentSession` currently have no `model` field.
- The bubble token system (`BubbleToken: CaseIterable`) already supports
  optional/per-session tokens that hide themselves when absent — `.title`
  is the existing precedent (`tokenHasValue(.title) = session.title != nil`).
- `BubbleSettingsView.inactiveTokens` is `BubbleToken.allCases.filter { ... }`,
  so a brand-new case automatically appears in the "add token" picker for
  existing users without any layout-migration code.

## Design

### 1. Shared `HookModelInfo` decoder (new, in `HookPayloads.swift`)

A small `Decodable` type that **never throws**, regardless of the actual
JSON shape of `model`:

```swift
public struct HookModelInfo: Decodable, Equatable {
    public let displayName: String?

    private enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case id
    }

    public init(from decoder: Decoder) throws {
        if let c = try? decoder.container(keyedBy: CodingKeys.self) {
            displayName = (try? c.decodeIfPresent(String.self, forKey: .displayName))
                .flatMap { $0 }
                ?? (try? c.decodeIfPresent(String.self, forKey: .id)).flatMap { $0 }
        } else if let single = try? decoder.singleValueContainer(),
                  let str = try? single.decode(String.self) {
            displayName = str
        } else {
            displayName = nil
        }
    }
}
```

Rationale: since the exact `model` shape per agent/event is unconfirmed,
a synthesized `Decodable` would throw on any mismatch and silently drop the
*entire* hook event (the payload structs use `try?` at the top level). This
custom decoder absorbs any shape — object with `display_name`, object with
only `id`, bare string, or absent — and falls back to `nil` rather than
failing the whole decode.

### 2. `AgentEvent.model: String?`

New optional field on `AgentEvent` (`Sources/AgentPetCore/AgentEvent.swift`),
threaded through the existing memberwise init with a `nil` default.

### 3. Per-payload decode

- `ClaudeHookPayload`: add `public let model: HookModelInfo?` (`CodingKeys.model
  = "model"`). In `makeEvent`, pass `model: model?.displayName` to
  `AgentEvent`. This single change covers Claude, Codex, Gemini, opencode,
  Copilot, Kiro (all routed through `ClaudeHookPayload.decode`).
- `CursorHookPayload`, `WindsurfHookPayload`, `AntigravityHookPayload`: same
  optional `model: HookModelInfo?` field added and threaded into
  `makeEvent`'s `AgentEvent(...)` call. If these agents don't actually send a
  `model` key, this decodes to `nil` harmlessly — the token simply won't show
  for those rows (same degrade-gracefully pattern as `.title`).

### 4. `AgentSession.model: String?`

New optional field on `AgentSession`
(`Sources/AgentPetCore/AgentSession.swift`), default `nil`.

### 5. `SessionStore.apply` merge logic

In `SessionStore.swift`, for the "existing session" branch:

```swift
if let model = event.model { existing.model = model }
```

— mirrors the existing `if let project = event.project { existing.project =
project }` pattern. Once a model name is known for a session, it persists
across later events that don't carry a `model` field (e.g. `Stop`), instead
of being clobbered to `nil`.

For the "new session" branch, pass `model: event.model` straight into the
`AgentSession` initializer.

### 6. New `BubbleToken.model` case

In `BubbleSettings.swift`:

- Add `.model` to the `BubbleToken` enum (`CaseIterable`).
- `displayName`: "Model" (localized via `NSLocalizedString`)
- `shortName`: "Model"
- `chipSymbol`: `"cpu"` (SF Symbol)
- `chipColor`: `.pink`
- Add to `BubbleLayout.original` and `.standard` as `.init(token: .model,
  isVisible: false)`; add to `.detailed` as `.init(token: .model, isVisible:
  true)`.
- Existing users (custom saved layouts predating this change) will see
  "Model" appear in the inactive-tokens picker (`BubbleSettingsView`) via
  the existing `BubbleToken.allCases` diff — no migration code needed.

### 7. Rendering in `AgentRow` (`PetView.swift`)

- `tokenHasValue(.model)` returns `session.model != nil`.
- New `case .model` in `tokenView(for:)`, rendered like `.stateLabel`:
  small text at `secondaryPt`, `textColor(0.55)`, no animation (static,
  unlike `.message` which types/erases).

```swift
case .model:
    if let model = session.model {
        Text(model)
            .font(.system(size: secondaryPt, weight: .regular))
            .foregroundStyle(textColor(0.55))
            .lineLimit(1)
            .truncationMode(.tail)
    }
```

## Testing

- `Tests/AgentPetCoreTests`: add cases to the existing hook-decode tests
  (`MultiAgentHookTests.swift` or similar) feeding synthetic JSON with:
  - `"model": {"id": "claude-sonnet-4-6-20250514", "display_name": "Sonnet 4.6"}`
    → `AgentEvent.model == "Sonnet 4.6"`
  - `"model": {"id": "gpt-5.1"}` (no `display_name`) → `AgentEvent.model ==
    "gpt-5.1"`
  - `"model": "some-string"` → `AgentEvent.model == "some-string"`
  - `model` key absent → `AgentEvent.model == nil`, and the payload still
    decodes successfully (other fields populate normally).
  - malformed `model` (e.g. `"model": 123`) → still decodes successfully,
    `AgentEvent.model == nil`.
- `SessionStore` test: apply an event with `model` set, then a later event
  for the same session with `model == nil` — assert `session.model` retains
  the earlier value.
- `BubbleSettingsTests.swift`: assert `.model` appears in
  `BubbleToken.allCases`, and that `.original`/`.standard` have it
  `isVisible == false` while `.detailed` has it `true`.
- Manual: trigger a real Claude Code session, enable the "Model" token via
  Settings → Bubble, confirm "Sonnet 4.6" (or current model) appears on the
  chat line. Confirm a Cursor/Codex/etc session either shows its model (if
  the payload happens to carry one) or simply omits the token without
  breaking the row layout.

## Out of scope / known limitations

- Whether Codex, Gemini CLI, Cursor, Windsurf, Antigravity, opencode,
  Copilot, and Kiro CLI actually send a `model` field in their hook payloads
  is **unconfirmed**. This design makes the decode safe either way (never
  breaks the event), but actually *seeing* the model for those agents may
  require a follow-up once real payloads are captured — same caveat already
  noted for Cursor's `tool_input` shape in the cursor-activity-bubble design.
- No manual override / per-agent static label setting (Approach B/C from
  brainstorming) — purely auto-detected from hook payload, hidden when
  absent. A manual-override setting can be a follow-up if auto-detection
  proves too sparse across providers.
