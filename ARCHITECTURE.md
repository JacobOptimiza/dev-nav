# Architecture

DevNav is a Windows-only folder navigator: a native Rust TUI binary driven from
PowerShell through a thin integration module. This document describes what
exists in the repository today; it does not describe planned work (see
[ROADMAP.md](ROADMAP.md)).

## Components

### Rust native navigator (`src/`)

A single binary (`dev`) plus a small library crate, with no runtime
dependencies beyond `windows-sys`:

- `main.rs` — CLI entry point: `--version`, config-only commands
  (`--set-language`, `--detect-language`, `--set-shortcut`, `--clear-shortcut`),
  root resolution (`--root` argument, then configured root, then `DEV_HOME`,
  then the user profile), TUI launch, and result-file writing.
- `app.rs` — application state machine: modes (normal, help, filter, path,
  alias, command, confirm-root, command manager/editor/delete confirmation),
  directory listing, fuzzy filtering, favorites/aliases, and frame generation
  (`render_rows` is pure string generation; `render` wraps it with the real
  terminal handle).
- `config.rs` — the `config.tsv` parser/writer (see below) with atomic saves
  (`ReplaceFileW` on Windows) and the `Shortcut` model shared by the lib and
  bin targets.
- `i18n.rs` — dependency-free Spanish/English localization.
- `input.rs` / `terminal.rs` — Win32 console input and raw-mode handling
  (Windows-only by design).
- `model.rs` — the `ShellResult` payload contract (`cd` / `exec` / `update`).
- `render.rs` — ANSI frame diffing renderer.

### PowerShell integration (`powershell/DevNav.psm1`)

The module the user actually invokes (`dev`). Responsibilities:

- Locate the installed executable (managed install vs. portable layouts).
- Language detection/init, startup update check, and config helpers that read
  and write the same `config.tsv` as the Rust binary.
- Run the TUI with a `--result` temp file, then interpret the result: change
  directory, execute a command in the selected folder, or run the updater —
  actions that only a shell can perform on the user's session.
- Shortcut management (`Set-DevShortcut`, `Remove-DevShortcut`, …) and the
  self-updater (`Update-DevNavigator`).

### Installer and profile integration

- `installer/DevNav.iss` — Inno Setup script producing per-user x64/ARM64
  installers into `%LOCALAPPDATA%\Programs\DevNav`.
- `installer/ProfileIntegration.ps1` — installs/removes the PowerShell module
  and profile hook for the installing user.
- `install.ps1` — bootstraps a managed installation from a release.

### Distribution channels

The GitHub Release is the canonical source of every artifact; all other
channels derive from it:

- **npm bootstrap** (`packaging/npm/bin/devnav.mjs`) — a transient delivery
  channel with no runtime dependencies. The tarball embeds the canonical Inno
  installers plus `release-manifest.json`; the bootstrap verifies SHA-256
  hashes before delegating to Inno. It never owns installed files.
- **Scoop** — portable artifacts in the release feed the separate
  `JacobOptimiza/scoop-bucket` repository (`packaging/scoop/`).
- **WinGet** — immutable versioned manifests with SHA-256
  (`packaging/winget/`), submitted to `microsoft/winget-pkgs`.

## `dev` invocation flow

1. The user runs `dev` in PowerShell; the module resolves the executable and
   passes `--result <temp file>` (and optionally `--root`).
2. The Rust binary reads `%LOCALAPPDATA%\DevNav\config.tsv`, enters the TUI on
   the current console, and handles all interaction locally.
3. On exit it writes one NUL-separated record to the result file:
   `cd\0<path>\0`, `exec\0<path>\0<command>` or `update\0\0`.
4. The PowerShell module reads the file and performs the action in the user's
   session (or triggers the updater). The temp file is removed afterwards.

## Configuration (`config.tsv`)

Single flat TSV file owned jointly by the Rust binary and the PowerShell
module, read and written by both through stable key prefixes: `root`,
`show_favorites`, `check_updates`, `language`, `favorite\0t<path>`,
`alias\0t<path>\0t<alias>`, and `shortcut\0t<slot>\0t<alias>\0t<command>`
(1–9, executed as Shift+digit in the TUI). The Rust writer escapes `%`, tab
and newline and replaces the file atomically.

## Trust boundaries

- **Rust binary**: local process with console and filesystem access only. It
  never executes commands itself; it only records intents in the result file.
- **PowerShell module**: the trust pivot. It executes the `cd`/`exec` the
  binary requested — commands typed by the user in the TUI or configured
  shortcuts from `config.tsv` — in the user's own session and privileges.
- **Network** is used in exactly two places: the startup/friendly update check
  and updater (GitHub Releases API over TLS), and package-manager downloads
  during initial installation (npm registry / Scoop / WinGet). The TUI itself,
  navigation, favorites, aliases, and shortcuts are fully offline.
- **Integrity of downloaded artifacts**: the npm bootstrap verifies SHA-256
  hashes from `release-manifest.json` before running the installer; Scoop and
  WinGet manifests carry release SHA-256 hashes. Checksums verify integrity,
  not authenticity (see [SECURITY.md](SECURITY.md)).
