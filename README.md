# DevNav

**A fast, native workspace navigator for PowerShell 7 on Windows.**

Built in Rust · keyboard-first · no TUI framework · no telemetry.

[![CI](https://github.com/JacobOptimiza/dev-nav/actions/workflows/ci.yml/badge.svg)](https://github.com/JacobOptimiza/dev-nav/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/JacobOptimiza/dev-nav)](https://github.com/JacobOptimiza/dev-nav/releases/latest)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Windows](https://img.shields.io/badge/Windows-x64%20%7C%20ARM64-0078D4)](https://github.com/JacobOptimiza/dev-nav/releases/latest)

**English** | [Español](README.es.md)

![DevNav terminal interface](assets/devnav-preview.svg)

Open `dev`, find a repository, and launch Codex, Claude Code, OpenCode, Kimi, or
any command in that directory. DevNav also provides persistent aliases, global
favorites, fuzzy filtering, and a visual way to choose your startup directory.

## Why DevNav?

- Starts directly in your chosen workspace.
- Keeps every favorite available while you navigate across drives.
- Opens coding agents in the highlighted repository with one key.
- Returns directory changes to the current PowerShell session correctly.
- Runs as a native, event-driven Windows executable with differential VT rendering.
- Stores configuration locally and never sends telemetry.

## Requirements

- Windows 10 or 11, x64 or ARM64.
- PowerShell 7 or newer (`pwsh`).
- Windows Terminal recommended.

Published binaries do not require Rust or Visual Studio.

## Install

### Quick install

Run this in PowerShell 7:

```powershell
irm https://raw.githubusercontent.com/JacobOptimiza/dev-nav/main/install.ps1 | iex
```

The installer detects the architecture, downloads `dev.exe` and its PowerShell
module from the latest GitHub release, verifies both SHA-256 checksums, installs
them under `%LOCALAPPDATA%\Programs\DevNav`, and adds the module import to the
PowerShell 7 profile.

If you prefer to inspect the installer before running it:

```powershell
git clone https://github.com/JacobOptimiza/dev-nav.git
Set-Location dev-nav
Get-Content .\install.ps1
.\install.ps1
```

Open a new PowerShell 7 window and run:

```powershell
dev
```

## First run: choose your startup directory

The startup directory is the folder containing your repositories, or any folder
you want DevNav to show on launch.

1. Run `dev`. On the first interactive launch only, choose whether DevNav may
   silently check for new releases at startup; this never installs without asking.
2. A fresh installation opens at `$HOME`. Navigate with `↑`, `↓`, and `→`.
   Press `p` to enter any absolute path or drive.
3. Highlight the directory you want to use as your startup directory.
4. Press `Ctrl+S`.
5. Verify the full path and press `Enter`; press `Esc` to cancel.

For scripts and coding agents, the equivalent command is:

```powershell
Set-DevRoot $HOME
Get-DevRoot
```

## Global favorites

Press `f` on a directory to add or remove it from global favorites. Every saved
favorite stays at the top while you navigate, including the favorite matching
the current directory.

Global favorite shortcuts are visible by default. Press `Shift+F` to hide or
show them. DevNav persists this preference between sessions; hiding shortcuts
does not delete favorites or hide real child directories.

Favorites, aliases, startup directory, and UI preferences live outside the
repository in `%LOCALAPPDATA%\DevNav\config.tsv`. Updates do not overwrite it.

## Shortcuts

Press `F1` at any time for the complete, scrollable help panel.

### Navigation and organization

| Shortcut | Action |
|---|---|
| `↑` / `↓` or `j` / `k` | Move the selection |
| `Enter` | Select the directory and return to PowerShell |
| `→` / `l` | Enter the highlighted directory |
| `←` / `h` / `Backspace` | Go to the parent directory |
| `/` | Start incremental fuzzy filtering |
| `p` | Open any absolute path or drive |
| `g` | Return to the startup directory |
| `Ctrl+S` | Save the highlighted directory as startup directory, with confirmation |
| `f` | Add or remove a global favorite |
| `Shift+F` | Show or hide global favorite shortcuts |
| `a` | Create or edit an alias |

### Coding agents and commands

| Shortcut | Action |
|---|---|
| `c` | Codex: new session in the highlighted repository |
| `r` | Codex: resume the repository's last session |
| `d` / `Shift+D` | Claude Code: new / last session |
| `o` / `Shift+O` | OpenCode: new / last session |
| `i` / `Shift+I` | Kimi: new / last session |
| `e` | Enter and run a command in the highlighted directory |
| `u` | Refresh the current directory |
| `Ctrl+U` | Enable or disable update checks at startup |
| `Shift+U` | Check for and install a DevNav update |
| `F1` | Open or close the shortcuts panel |
| `q` / `Esc` | Exit or cancel |

`:` remains available as a Vim-style alias for `e`.

## Update

From PowerShell:

```powershell
dev update
```

Or press `Shift+U` inside the TUI. DevNav compares the installed semantic
version with the latest release, downloads only when needed, verifies checksums,
and reports the result. The updater replaces only application files and preserves
the separate local configuration.

On the first interactive launch, DevNav asks once whether it may check GitHub for
new releases at startup. This check never downloads or installs anything without
an explicit confirmation. It stays silent when DevNav is current or the network
is unavailable, and it is skipped in non-interactive sessions. Change the saved
preference with `Ctrl+U` or from PowerShell:

```powershell
Set-DevUpdateCheck $true   # enable
Set-DevUpdateCheck $false  # disable
```

## Architecture

- Rust 2024 with direct Win32 integration through `windows-sys`.
- Native keyboard input through `ReadConsoleInputW`.
- Custom VT renderer with row buffering and differential updates.
- Event-driven loop with no polling or idle rendering.
- Separate result channel so PowerShell can persist directory changes.
- One direct dependency and no TUI framework.

## Security and privacy

- No telemetry. Network access is limited to the optional, consented release check and explicit updates.
- Release binaries and the PowerShell module are verified with SHA-256.
- Local configuration is excluded from the repository and preserved on updates.
- GitHub Actions use minimal permissions and commit-pinned actions.
- The public repository is read-only for external contributors.

See [SECURITY.md](SECURITY.md), [CONTRIBUTING.md](CONTRIBUTING.md), and the
[troubleshooting guide](TROUBLESHOOTING.md).

## Build from source

Requires stable Rust and the MSVC Build Tools:

```powershell
git clone https://github.com/JacobOptimiza/dev-nav.git
Set-Location dev-nav
.\install.ps1 -BuildFromSource
```

Development checks:

```powershell
cargo fmt -- --check
cargo test
cargo clippy --all-targets -- -D warnings
cargo build --release
```

## Distribution roadmap

A WinGet package is planned. WinGet supports portable packages, but DevNav also
requires its PowerShell module and profile integration, so the first submission
will follow after a non-interactive installer package can be validated in Windows
Sandbox without reducing the current installation guarantees.

## License

MIT. See [LICENSE](LICENSE).
