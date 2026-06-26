---
name: agentpet-windows-docs
description: Use for any AgentPet Windows documentation, README/CONTRIBUTING update, install-page update, docs check, localized docs sync, or wording about Windows/macOS support. Trigger for “update docs”, “check docs”, “tài liệu Windows”, “hướng dẫn build Windows”, “Windows support”, and follow-up fixes.
---

# AgentPet Windows Docs

Use this skill to write accurate Windows documentation for AgentPet.

## Truth model

Current verified status:

- The macOS desktop app remains macOS-only.
- `AgentPetCore` can build and pass core tests on Windows when the Swift Windows SDK is configured.
- Windows live IPC is queue-only in this increment; Unix socket live delivery is non-Windows only.
- Full Windows tray/floating pet UI is future work unless implemented later.

## Required Windows setup wording

Mention that Windows SwiftPM may need:

1. Visual Studio 2022 Community or Build Tools with Windows SDK and VC tools.
2. Swift Toolchain installed via WinGet.
3. `SDKROOT` set to Swift's Windows SDK path if SwiftPM reports `Invalid manifest fatalError` or `unable to load standard library`.

Example:

```powershell
$env:SDKROOT = "$env:LOCALAPPDATA\Programs\Swift\Platforms\6.3.2\Windows.platform\Developer\SDKs\Windows.sdk"
[Environment]::SetEnvironmentVariable('SDKROOT', $env:SDKROOT, 'User')
```

Verification command shape:

```powershell
swift package describe
swift build --target AgentPetCore
swift test --filter AgentPetCoreTests
```

## Files to consider

- `README.md` — top-level support and build notes.
- `CONTRIBUTING.md` — contributor setup and test matrix.
- `docs/readme/README.vi.md`, `README.zh-Hans.md`, `README.ja.md` — localized docs if support claims change.
- `web/src/pages/install.astro` — public install page. Do not mark Windows desktop available unless released.
- `.github/workflows/ci.yml` — if documenting CI-backed Windows support.

## Writing rules

- Do not overclaim: say “Windows core build/test support” not “Windows app support”.
- Include tested commands and known warnings separately.
- Keep user-facing docs concise; put troubleshooting in CONTRIBUTING if detailed.
- If localized docs cannot be updated confidently, update English source and flag translation follow-up.

## Verification before final docs

Ask QA for command results. A docs claim is valid only if one of these is true:

- command was run in this session and passed
- CI verifies it
- docs clearly label it as planned/future

## Output checklist

- docs files changed
- exact support claim added/removed
- verified commands supporting the claim
- translation follow-up, if any
