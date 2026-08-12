# Changelog

All notable changes to DevNav are documented here. The project follows Semantic
Versioning.

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
