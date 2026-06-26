---
name: agentpet-verify
description: Use whenever asked to verify AgentPet, run tests, check a fix, diagnose SwiftPM/Windows build failures, validate docs claims, or confirm core/macOS app behavior. Trigger for “verify”, “test”, “build”, “check”, “fix Swift build”, “lỗi manifest”, and Windows SDK/toolchain issues.
---

# AgentPet Verify

Use this skill to verify AgentPet changes with the right platform assumptions.

## Windows environment

Swift on Windows requires both Visual Studio build tools and Swift's Windows SDK. In this session the SDK lives at:

```text
%LOCALAPPDATA%\Programs\Swift\Platforms\6.3.2\Windows.platform\Developer\SDKs\Windows.sdk
```

If SwiftPM fails with `Invalid manifest fatalError`, or `swiftc` says `unable to load standard library`, set `SDKROOT` before running SwiftPM.

## Windows command pattern

```powershell
cmd /v:on /s /c "set ""PATH=C:\Program Files (x86)\Microsoft Visual Studio\Installer;%PATH%"" && call ""C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"" -arch=x64 -host_arch=x64 && set ""PATH=!PATH!;%LOCALAPPDATA%\Programs\Swift\Toolchains\6.3.2+Asserts\usr\bin;%LOCALAPPDATA%\Programs\Swift\Runtimes\6.3.2\usr\bin"" && set ""SDKROOT=!LOCALAPPDATA!\Programs\Swift\Platforms\6.3.2\Windows.platform\Developer\SDKs\Windows.sdk"" && swift package describe && swift build --target AgentPetCore && swift test --filter AgentPetCoreTests"
```

## Verification matrix

### Windows core

- `swift package describe`
- `swift build --target AgentPetCore`
- `swift test --filter AgentPetCoreTests`

Expected: core build/tests pass; app/Sparkle targets are absent on Windows.

### macOS full app

- `swift package describe`
- `swift build`
- `swift test`

Expected: app target and Sparkle are present; full app/tests pass.

## Troubleshooting

- Missing `link`: run inside Visual Studio dev shell.
- `Invalid manifest fatalError`: set `SDKROOT` to Swift Windows SDK.
- `unable to load standard library`: verify `Windows.sdk/usr/lib/swift/windows/Swift.swiftmodule` exists.
- `.build/debug` symlink warning on Windows: report it, but do not treat it as failure if build/tests pass.

## Output format

Report:

- command run
- environment assumptions (`SDKROOT`, dev shell)
- pass/fail
- failures/warnings
- next recommended check
