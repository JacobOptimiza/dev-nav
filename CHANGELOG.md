# Changelog

All notable changes to DevNav are documented here. The project follows Semantic
Versioning.

## [Unreleased]

## [0.11.0] - 2026-08-14

### Added

- Add bilingual English/Spanish TUI text and localized shortcut labels.
- Detect the preferred Windows UI language on first launch and request
  confirmation before asking about startup update checks.
- Add global `F2` language switching with persisted `es-ES` / `en-US`
  preferences.
- Add `dev language`, `dev language es`, `dev language en`,
  `Get-DevLanguage`, and `Set-DevLanguage`.
- Standardize the visible shortcut contract as `Shift+...` in English and
  `Mayús+...` in Spanish, with at most one modifier.

## [0.10.0] - 2026-08-13

### Added

- Add the official npm bootstrap package for Bun, npm, pnpm and Yarn, plus
  Scoop packaging, beginning with the first multichannel release v0.10.0.
- Add portable x64/ARM64 Scoop archives and a `DevNav.psd1` module manifest
  for PowerShell module registration.
- Add configurable Shift+1…Shift+9 project shortcuts: each slot binds an
  optional visible alias and a shell command, persists in `config.tsv`
  (backward compatible), and runs in the selected project directory through the
  existing `exec` result path. Configure with `dev shortcut <1..9> [alias]
  <command>` (or `Set-DevShortcut`/`Remove-DevShortcut`); empty slots are
  no-ops. Configured aliases surface in the footer and the shortcuts help
  panel.

### Changed

- Scoop-managed installations delegate updates to `scoop update devnav`.

## [0.9.7] - 2026-08-12

### Fixed

- Retry transient failures while downloading the verified Inno Setup compiler in
  the release workflow.

## [0.9.6] - 2026-08-12

### Fixed

- Retry interrupted release downloads and resume partial files before checksum
  verification.

## [0.9.5] - 2026-08-12

### Fixed

- End the current `dev` invocation after a successful update.
- Roll back both installed files if replacement or executable validation fails.

## [0.9.4] - 2026-08-12

### Fixed

- Prevent the updater from reloading `DevNav.psm1` while that module is still
  executing, avoiding broken private-command resolution in the current session.
- Detect module changes and request a PowerShell restart before continuing.

## [0.9.3] - 2026-08-12

### Fixed

- Upload only files when creating a GitHub release; generated manifest folders
  remain available for validation without being passed as release assets.

## [0.9.2] - 2026-08-12

### Fixed

- Resolve installer sources relative to the Inno Setup script so release builds
  produce the x64 and ARM64 setup executables reliably.

## [0.9.1] - 2026-08-12

### Fixed

- Build the ARM64 installer on runners without the App Installer `winget`
  command by using the versioned Inno Setup compiler fallback.

## [0.9.0] - 2026-08-12

### Added

- Build per-user `DevNavSetup-x64.exe` and `DevNavSetup-arm64.exe` installers
  with silent install, upgrade and uninstall support.
- Add marker-based PowerShell profile integration that can be removed without
  touching unrelated profile content.
- Generate version-pinned WinGet manifests with release SHA-256 values.

### Changed

- Preserve `%LOCALAPPDATA%\DevNav\config.tsv` when uninstalling application files.

## [0.8.1] - 2026-08-12

### Added

- Pin the supported Rust toolchain to 1.97.1 and enforce workspace format, check,
  test and Clippy quality gates.
- Add PowerShell parser validation, PSScriptAnalyzer 1.25.0 and Pester 6.1.0
  checks to CI.
- Add `cargo-deny` policy checks for advisories, licenses, sources and bans.

### Changed

- Add `-WhatIf` and `-Confirm` support to state-changing PowerShell commands.
- Document the complete local quality-gate commands for contributors.

## [0.8.0] - 2026-08-12

### Added

- Ask once, on the first interactive launch, whether DevNav may check GitHub for new releases at startup.
- Add `Ctrl+U` and `Set-DevUpdateCheck` to enable or disable startup checks at any time.

### Changed

- Keep startup checks silent when DevNav is current or the network is unavailable.
- Always require explicit confirmation before downloading or installing an update.
- Skip the startup prompt and network check in non-interactive sessions.

## [0.7.0] - 2026-08-12

### Added

- Add `Shift+F` to show or hide global favorite shortcuts and persist the preference between sessions.
- Show the favorites visibility state directly in the directory-list header.

### Fixed

- Keep every favorite visible while navigating, including the favorite that matches the current directory.

### Changed

- Show global favorites by default when no explicit preference has been saved.

## [0.6.1] - 2026-08-11

### Changed

- Use `$HOME` as the only public first-launch fallback and remove concrete personal folder names from code, tests, and documentation.
- Document and verify that updates replace only application files and preserve the separate local configuration.

## [0.6.0] - 2026-08-11

### Added

- Add `Ctrl+S` to save the highlighted directory as the startup root after an explicit confirmation.
- Add `Set-DevRoot` as the automation-friendly equivalent for terminals, scripts, and coding agents.
- Persist the startup root alongside favorites and aliases in the local DevNav configuration.

### Changed

- Make visual startup-root selection the primary onboarding path.
- Use the user profile as the neutral first-launch fallback.
- Keep `DEV_HOME` as a backwards-compatible fallback when no startup root has been saved.

## [0.5.0] - 2026-08-11

### Added

- Add `dev update` with semantic version comparison, architecture detection, checksum verification, and clear status messages.
- Add `Shift+U` to launch the updater directly from the TUI.
- Publish the PowerShell module as a checksummed release asset so the updater can update the complete installation.
- Add native `dev.exe --version` reporting.

### Changed

- Use the same `Codex: session` wording as every other agent in the shortcuts panel.

## [0.4.0] - 2026-08-11

### Added

- Add an `F1` help panel with every shortcut grouped by workflow and clear descriptions.
- Support scrolling the help panel in shorter terminal windows.

### Changed

- Replace the overloaded bottom legend with concise, context-aware guidance.
- Make `F1` available from every application mode and restore the previous mode when help closes.

## [0.3.1] - 2026-08-11

### Documentation

- Add a user-friendly FAQ and troubleshooting guide for installation, project roots, PowerShell profiles, PATH, agent CLIs, checksums, updates, and source builds.
- Explain which setup tasks the installer handles automatically and when Rust or MSVC are required.

## [0.3.0] - 2026-08-11

### Added

- Use `e` as the discoverable, single-key shortcut for running a command in the selected directory.

### Changed

- Group README shortcuts by workflow and prioritize common actions in the TUI help.
- Keep `:` as a backwards-compatible command-mode alias.
- Align the public documentation with the repository's read-only policy.

## [0.2.0] - 2026-08-11

### Added

- Launch Claude Code, OpenCode, or Kimi Code in the selected repository.
- Resume the latest repository session for each additional agent with Shift shortcuts.

### Changed

- Clarify that `r` resumes the latest Codex session for the selected repository.

## [0.1.1] - 2026-08-11

### Fixed

- Align the top-right border corner with the terminal edge.

## [0.1.0] - 2026-08-11

### Added

- Native Windows workspace navigation from PowerShell 7.
- Persistent global favorites and aliases.
- Navigation to arbitrary paths and drives.
- Fuzzy filtering and direct command execution.
- Codex launch and `resume --last` shortcuts.
- Differential VT renderer and native Win32 keyboard input.
- Automated x64 and ARM64 release installation workflow.
