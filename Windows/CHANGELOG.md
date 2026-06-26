# AgentPet Windows changelog

## 0.1.0 - 2026-06-26

First self-contained Windows WPF prototype release build.

### Added

- Self-contained `win-x64` publish for `AgentPet.Windows.exe`; target machines do not need .NET/runtime/build tools.
- Inno Setup installer output at `Windows/publish/installer/AgentPet-Setup-x64.exe`.
- Installer shortcuts:
  - Start Menu shortcut
  - optional Desktop shortcut
  - optional "Run AgentPet with Windows" startup shortcut
- `agentpet.exe` CLI helper staged beside the installed app to preserve the named-pipe/queue event loop.
- Reminder-first Vietnamese Windows UI with morning/afternoon task windows, bubble settings, and pet size controls.
- Pet click workflow:
  - click once: show current task
  - double-click: show next task
  - triple-click: mark current task complete and move to next task
- Reminder repeat every 30 seconds for the current task.
- 15 / 10 / 5 minute warning bubbles and warning sound before a task window ends.
- Completion sound for early/on-time task completion.
- About tab usage instructions for the click workflow and reminder behavior.
- About tab "Kiểm tra cập nhật" button that checks GitHub Releases, downloads `AgentPet-Setup-x64.exe`, runs the silent installer after AgentPet closes, and reopens the app when the installer succeeds.
- Bubble width slider in the Bubble/Bong bóng tab.
- Custom cursor-anchored pet dragging so the pet remains recoverable at screen edges.

### Fixed

- Double-click detection after custom dragging now waits briefly before dispatching the final click count, so click/double-click/triple-click actions do not override each other.
- Chat bubble flips below the pet near the top edge and shifts horizontally near left/right edges to keep message content visible.
- Reminder/click actions no longer reset the pet back to a fixed screen position.

### Notes

- The installer built by default is unsigned. Use `Windows/scripts/build-release.ps1 -Sign` with a valid Windows code-signing certificate to sign the app, CLI, and installer.
- User settings, pet packs, and queue data remain under `%LOCALAPPDATA%\AgentPet` and are not removed by uninstall.
- This is a Windows WPF prototype release artifact. Auto-update uses GitHub Releases and an unsigned installer unless the release is built with `-Sign`.
