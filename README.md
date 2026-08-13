# DevNav

**Fast native workspace navigation for PowerShell 7 on Windows.**

[![CI](https://github.com/JacobOptimiza/dev-nav/actions/workflows/ci.yml/badge.svg)](https://github.com/JacobOptimiza/dev-nav/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/JacobOptimiza/dev-nav)](https://github.com/JacobOptimiza/dev-nav/releases/latest)
[![npm](https://img.shields.io/npm/v/@jacoboptimiza/devnav?logo=npm)](https://www.npmjs.com/package/@jacoboptimiza/devnav)
[![Windows](https://img.shields.io/badge/Windows-x64%20%7C%20ARM64-0078D4)](https://github.com/JacobOptimiza/dev-nav/releases/latest)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

**English** | [Español](README.es.md)

![DevNav terminal interface](assets/devnav-preview.svg)

Jump between projects, fuzzy-search workspaces, save favorites and aliases, and
launch coding agents or commands directly in the selected repository.

## Install DevNav

Choose the tool you already use. Every bootstrap installs the same native
DevNav release for Windows x64 or ARM64.

### Package runners

#### Bun

```powershell
bunx --bun @jacoboptimiza/devnav install
```

#### npm

```powershell
npx --yes @jacoboptimiza/devnav install
```

#### pnpm

```powershell
pnx @jacoboptimiza/devnav install
```

#### Yarn

```powershell
yarn dlx -p @jacoboptimiza/devnav devnav install
```

These are verified bootstrap channels, not JavaScript installations of DevNav.
They have no `postinstall` script or runtime dependencies: the bootstrap selects
the official x64 or ARM64 installer, verifies its SHA-256 against
`release-manifest.json`, installs it, and validates the installed version.

After installation, update DevNav with `dev update`—not with npm, Bun, pnpm, or
Yarn. The package runner is a discovery and bootstrap channel; it does not own
the installed application.

<details>
<summary>How package-runner installation works</summary>

The npm package contains the installers published by the canonical GitHub
Release. Running `install` detects Windows and the current architecture, checks
the selected installer against the release inventory, invokes the silent
per-user Inno Setup installer, and confirms that `dev.exe --version` matches the
package version. The runner exits after setup and is not required at runtime.

</details>

### PowerShell

No Node.js or package manager is required. Run the official installer from
PowerShell 7:

```powershell
irm https://raw.githubusercontent.com/JacobOptimiza/dev-nav/main/install.ps1 | iex
```

To inspect the script before executing it:

```powershell
$installer = Join-Path $env:TEMP 'devnav-install.ps1'
Invoke-WebRequest https://raw.githubusercontent.com/JacobOptimiza/dev-nav/main/install.ps1 -OutFile $installer
Get-Content $installer
& $installer
```

The same per-user x64 and ARM64 installers are also available from the
[latest GitHub Release](https://github.com/JacobOptimiza/dev-nav/releases/latest).

### Other distribution channels

| Channel | Status |
|---|---|
| GitHub installer | Available |
| npm, Bun, pnpm and Yarn | Available |
| Scoop | Coming soon—the portable release artifacts exist; the public bucket is still being validated |
| WinGet | Pending Microsoft approval of `JacobOptimiza.DevNav` |

### Start DevNav

Open a new PowerShell 7 session:

```powershell
dev
```

Continue with [First run](#first-run-choose-your-startup-directory) to choose
the folder DevNav opens by default.

### Requirements

- Windows 10 or 11 on x64 or ARM64.
- PowerShell 7 or newer (`pwsh`).
- Windows Terminal recommended.

Published binaries do not require Rust or Visual Studio. A package runner is
required only when you choose its bootstrap command.

## Why DevNav?

- Starts directly in your chosen workspace.
- Keeps every favorite available while you navigate across drives.
- Opens coding agents or runs commands in the highlighted repository.
- Returns directory changes to the current PowerShell session correctly.
- Runs as a native, keyboard-first Windows application with no telemetry.

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
| `.` | Select the directory currently shown |
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

### Custom commands

Bind commands to `Shift+1` … `Shift+9` and run them in the highlighted project:

```powershell
dev shortcut 1 "Dev" "bun run dev"
dev shortcut 2 "Tests" "cargo test"
```

Use `Set-DevShortcut` for scripts, overwrite a slot by using the same index, or
remove one with `Remove-DevShortcut -Index 1` (or `dev shortcut 1`). Bindings
persist locally and appear in the `F1` help panel.

## Update

From PowerShell:

```powershell
dev update
```

Or press `Shift+U` inside the TUI. DevNav compares the installed semantic
version with the latest release, downloads only when needed, verifies checksums,
and reports the result. The updater replaces only application files and preserves
the separate local configuration.

Installs bootstrapped through npm, Bun, pnpm, Yarn, PowerShell, or the GitHub
installer use `dev update`; the bootstrap tool does not own future updates.

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

- No telemetry. Network access is limited to installation, the optional
  consented release check, and explicit updates.
- Release binaries and the PowerShell module are verified with SHA-256.
- Local configuration is excluded from the repository and preserved on updates.
- GitHub Actions use minimal permissions and commit-pinned actions.
- Future npm releases use OIDC Trusted Publishing; no `NPM_TOKEN` is stored.
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
cargo fmt --all -- --check
cargo check --workspace --all-targets
cargo test --workspace
cargo clippy --workspace --all-targets -- -D warnings
cargo deny check
./scripts/validate-powershell.ps1
Invoke-Pester -Path ./tests/powershell
```

The repository pins Rust 1.97.1 with `rustfmt` and `clippy`. PowerShell quality
gates use the native parser, PSScriptAnalyzer 1.25.0 and Pester 6.1.0. Dependency
licenses, advisories, registries and duplicate versions are checked by
`cargo-deny` using [deny.toml](deny.toml). CI runs all of these checks.

See the public [roadmap](ROADMAP.md) for planned distribution work.

## License

MIT. See [LICENSE](LICENSE).
