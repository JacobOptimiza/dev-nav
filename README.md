# DevNav

**Fast native workspace navigation for PowerShell 7 on Windows.**

[![CI](https://github.com/JacobOptimiza/dev-nav/actions/workflows/ci.yml/badge.svg)](https://github.com/JacobOptimiza/dev-nav/actions/workflows/ci.yml)
[![CodeQL](https://github.com/JacobOptimiza/dev-nav/actions/workflows/codeql.yml/badge.svg)](https://github.com/JacobOptimiza/dev-nav/actions/workflows/codeql.yml)
[![OpenSSF Best Practices](https://www.bestpractices.dev/projects/14088/badge)](https://www.bestpractices.dev/projects/14088)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/JacobOptimiza/dev-nav/badge)](https://scorecard.dev/viewer/?uri=github.com/JacobOptimiza/dev-nav)
[![Windows](https://img.shields.io/badge/Windows-x64%20%7C%20ARM64-0078D4)](https://github.com/JacobOptimiza/dev-nav/releases/latest)
[![PowerShell 7+](https://img.shields.io/badge/PowerShell-7%2B-5391FE?logo=powershell&logoColor=white)](https://learn.microsoft.com/powershell/)
[![Rust 1.97+](https://img.shields.io/badge/Rust-1.97%2B-orange?logo=rust&logoColor=white)](https://www.rust-lang.org/tools/install)
[![npm](https://img.shields.io/npm/v/@jacoboptimiza/devnav?logo=npm)](https://www.npmjs.com/package/@jacoboptimiza/devnav)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

**English** | [Español](README.es.md)

DevNav is a native workspace navigator for developers who live in PowerShell and work across multiple repositories. Fuzzy-find a project, jump into it, and launch the agent or command you need without breaking terminal flow.

## Why DevNav

Working across many repositories creates friction beyond typing `cd`: remembering paths, switching context, finding the right workspace, and repeating setup before real work starts.

DevNav turns that overhead into a fast, repeatable workflow:

- **Find and jump instantly** — fuzzy-search projects instead of navigating directory trees or remembering paths.
- **Reduce context switching** — favorites, aliases, and custom commands keep frequent work one action away.
- **Start ready to work** — launch coding agents or commands directly in the selected repository, already in the right context.
- **Stay fast and lightweight** — the core is native Rust, designed for a responsive terminal workflow with no extra runtime required after installation.

![Animated DevNav terminal interface](assets/demo/devnav.gif)

## TUI preview

Real captures from the native DevNav executable: the navigator, the F1 help
panel, and the centered F3 custom-command manager.

### Navigator

![DevNav navigator](assets/screenshots/devnav-main.png)

### Help — F1

![DevNav help modal](assets/screenshots/devnav-f1-help.png)

### Custom commands — F3

![DevNav custom-command manager](assets/screenshots/devnav-f3-manager.png)

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

For npm, pnpm, and Yarn, the bootstrap package declares Node.js `>=22`. CI
validates that package on Node 22, 24, and 26; Node 24 is the release baseline
and Node 26 is the forward-compatibility lane. Bun runs this bootstrap with its
own runtime. None of these runtimes is required after DevNav is installed.

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

### Scoop

Add the official DevNav bucket:

```powershell
scoop bucket add jacoboptimiza https://github.com/JacobOptimiza/scoop-bucket
```

Then install DevNav:

```powershell
scoop install jacoboptimiza/devnav
```

Scoop installs the portable native build and owns the installed files. It does
not use the Inno Setup installer.

Update Scoop-managed installations with:

```powershell
scoop update devnav
```

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
| Scoop | Available — official [JacobOptimiza/scoop-bucket](https://github.com/JacobOptimiza/scoop-bucket) |
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
Windows PowerShell 5.1, 32-bit Windows, Linux, and macOS are not supported.

## First run: choose your startup directory

The **startup directory** is the folder that contains your repositories, or any
folder you want DevNav to show whenever you run `dev`. The recommended setup
does not require commands or editing files:

1. Run `dev`. On the first interactive launch only, choose whether DevNav may
   silently check for new releases at startup; it never installs anything
   without asking.
2. A fresh installation opens at `$HOME`. Navigate with `↑`, `↓`, and `→`. To
   go directly to another path or drive, press `p`, type the path, and confirm
   with `Enter`.
3. Highlight the directory you want to use as your startup directory.
4. Press `Ctrl+S` (**save as startup directory**).
5. Review the displayed path and press `Enter` to confirm or `Esc` to cancel.

The next `dev` starts directly in that directory. You can repeat these steps at
any time to change it. `Ctrl+S` deliberately uses a chord plus confirmation to
avoid accidental changes.

### Alternative for terminals, scripts, or agents

After installation, Codex, Cursor, or any script can configure the same path
without opening the TUI:

```powershell
Set-DevRoot $HOME
Get-DevRoot
```

`Set-DevRoot` validates that the directory exists and saves the same local
configuration as `Ctrl+S`.

For compatibility with existing setups, `DEV_HOME` continues to work when no
startup directory has been saved yet. A directory selected with `Ctrl+S` or
`Set-DevRoot` takes precedence:

```powershell
$env:DEV_HOME = $HOME
```

## Global favorites, even outside the root

Favorites are not limited to the startup directory. They always appear at the
top of the list while you navigate elsewhere. The favorite matching the current
directory is also shown, so entering a favorite never makes it disappear.

Global favorite shortcuts are visible by default. Press `Shift+F` to hide or
show them; DevNav persists that preference between sessions. Hiding shortcuts
does not delete favorites or hide real directories in the current folder.

To add a directory from another drive or outside the startup directory:

1. Run `dev`.
2. Press `p`.
3. Type an absolute path, for example `D:\Clients` or `C:\Work\Repo`.
4. Press `Enter` to open that location.
5. Navigate with the arrow keys and `→` until the target directory is
   highlighted.
6. Press `f` to save it as a favorite.

It will then appear at the top from any location. Highlight it and press `f`
again to remove it. Press `a` to display it as `alias - directory-name`.

The startup directory, favorites, aliases, and UI preferences are local and
live outside the repository in `%LOCALAPPDATA%\DevNav\config.tsv`.

## Shortcuts

Shortcuts are grouped by workflow. The most frequently used actions appear
first so they are easy to discover and remember.

### Navigation and selection

| Shortcut | Action |
|---|---|
| `↑` / `↓` or `j` / `k` | Move the selection |
| `Enter` | Select the directory and return to PowerShell |
| `→` / `l` | Enter the highlighted directory |
| `←` / `h` | Go to the parent directory |
| `Backspace` | Go to the parent directory |
| `.` | Select the directory currently shown |
| `g` | Return to the startup directory |
| `p` | Open any absolute path, including another drive |
| `Ctrl+S` | Save the highlighted directory as the startup directory; requires confirmation |
| `F1` | Open the full shortcut help panel |
| `F2` | Switch between English and Español |
| `F3` | Open the custom-command manager |

### Agents

| Shortcut | Action |
|---|---|
| `c` | Codex: start a new session (`codex`) in the highlighted directory |
| `r` | Codex: resume the repository's last session (`codex resume --last`) |
| `d` | Start Claude Code (`claude`) in the highlighted directory |
| `Shift+D` | Resume the repository's last Claude Code session (`claude --continue`) |
| `o` | Start OpenCode (`opencode`) in the highlighted directory |
| `Shift+O` | Resume the repository's last OpenCode session (`opencode --continue`) |
| `i` | Start Kimi Code (`kimi`) in the highlighted directory |
| `Shift+I` | Resume the repository's last Kimi Code session (`kimi --continue`) |

### Organization, search and actions

| Shortcut | Action |
|---|---|
| `/` | Start incremental fuzzy filtering |
| `f` | Add or remove a global favorite |
| `Shift+F` | Show or hide global favorite shortcuts; the state persists between sessions |
| `a` | Edit the highlighted directory alias |
| `e` | Enter and run a command in the highlighted directory |
| `u` | Refresh the current directory |
| `Ctrl+U` | Enable or disable startup update checks |
| `Shift+U` | Check for and install the latest DevNav release |
| `q` / `Esc` | Cancel and return to PowerShell |

The bottom bar shows only essential actions to avoid visual overload. Press
`F1` at any time for the complete panel; scroll with `↑` / `↓` and close it
with `F1`, `Esc`, or `Enter`.

`:` remains available as a Vim-style alias for `e`.

### Agent terminal titles

When DevNav launches a known agent, it temporarily sets the current terminal
title to `Agent/repository` for agents with `DevNavManagedTitle` ownership and
restores the previous title when the process ends. The result file carries the
agent identity explicitly; arbitrary commands and legacy results are never
guessed as agents. Codex uses its per-invocation `tui.terminal_title=[]`
override, while Claude Code and OpenCode receive their documented process-local
title-disable environment variables. Kimi uses `NativeAgentTitle`: current
Kimi Code manages its own terminal title and does not currently offer a
compatible per-invocation override, so DevNav does not set its title but
restores the caller's captured title after Kimi exits. No user configuration is
changed and unsupported hosts fall back silently.

### Custom commands

Bind commands to `Shift+1–9` and run them in the highlighted project:

Press `F3` to open the centered manager. It has nine `Shift+1–9` slots; use
`↑` / `↓` to move or `1–9` to select a slot directly. `Enter` adds or edits,
and `Delete` asks for removal confirmation. In the editor, `Tab` switches
between Alias and Command, `Enter` saves, and `Esc` cancels. `F2` changes the
language without losing the manager state or editor draft. `Shift+1–9` execute
their commands only from the normal navigator, never while managing slots.

The manager renders the editable alias and real command as `alias > command`
(for example, `Lanzar servidor > bun run dev`), while repository rows use
`alias | repo` (for example, `Navegador PowerShell | dev-nav`). Without an alias,
only the real value is shown; an alias never hides the project identity.

```powershell
dev shortcut 1 "Dev" "bun run dev"
dev shortcut 2 "Tests" "cargo test"
```

Use `Set-DevShortcut` for scripts, overwrite a slot by using the same index, or
remove one with `Remove-DevShortcut -Index 1` (or `dev shortcut 1`). Bindings
persist locally and appear in the `F1` help panel.

You can also select a repository and pass an optional agent or shell command
from PowerShell:

```powershell
dev codex
dev "git status"
```

The agent CLIs are optional. DevNav returns the command to PowerShell, so the
CLI you choose must be installed and available on `PATH`.

### Language

On the first interactive launch, DevNav detects the first supported language in
your Windows UI language preference list (`es-*` or `en-*`). It shows a bilingual
confirmation before asking about startup update checks. The confirmed choice is
stored as `es-ES` or `en-US`, so the prompt appears only once.

Use `F2` at any time to switch language without losing the current folder,
selection, mode, scroll position or input. From PowerShell:

```powershell
dev language
dev language en
dev language es
```

The equivalent module commands are `Get-DevLanguage` and `Set-DevLanguage`.

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

Scoop-managed installations use `scoop update devnav`. Their
`.devnav-managed-by-scoop` marker tells `dev update` to detect Scoop ownership,
skip self-updating, and show the Scoop command instead.

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
- npm releases use OIDC Trusted Publishing; no `NPM_TOKEN` is stored.
- Dependabot monitors Cargo and GitHub Actions dependencies.
- Security reports use GitHub Private Vulnerability Reporting; use the issue or
  pull-request templates for non-sensitive work.

See [SECURITY.md](SECURITY.md) for the security policy and expectations,
[ARCHITECTURE.md](ARCHITECTURE.md) for component and trust boundaries,
[ASSURANCE.md](ASSURANCE.md) for the evidence-based assurance case,
[CONTRIBUTING.md](CONTRIBUTING.md) for development policy, and the
[troubleshooting guide](TROUBLESHOOTING.md) for diagnostics.

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
cargo llvm-cov --workspace --json --output-path target/llvm-cov-export.json
python scripts/rust-production-coverage.py target/llvm-cov-export.json --threshold 80
python -m unittest discover -s tests/coverage
./scripts/validate-powershell.ps1
./scripts/invoke-pester-coverage.ps1
node --test "tests/npm/**/*.test.mjs"
./scripts/invoke-npm-coverage.ps1
```

The MSRV is Rust 1.97; CI pins Rust 1.97.1 with `rustfmt` and `clippy`.
PowerShell quality gates use the native parser, PSScriptAnalyzer 1.25.0 and
Pester 6.1.0. Dependency licenses, advisories, registries and duplicate versions are checked by
`cargo-deny` using [deny.toml](deny.toml). CI runs all of these checks.

See the public [roadmap](ROADMAP.md) for planned distribution work.

## FAQ

Quick answers are listed here. Full diagnostics and procedures are available in
the [troubleshooting guide](TROUBLESHOOTING.md).

### Does normal installation require Rust or Visual Studio?

No. The installer downloads and verifies the published binary. Rust and MSVC
are required only with `-BuildFromSource`.
[See details](TROUBLESHOOTING.md#rust-or-cargo-is-missing).

### Why is `dev` not recognized after installation?

`dev` is an alias loaded by the PowerShell module, not an executable added to
`PATH`. Restart PowerShell 7 and check the profile if it does not appear.
[See the solution](TROUBLESHOOTING.md#the-dev-command-is-unavailable).

### How do I correct the startup directory?

Highlight the correct directory in the TUI and press `Ctrl+S`, or run
`Set-DevRoot $HOME`.
[See the commands](TROUBLESHOOTING.md#correct-the-startup-directory).

### Why does Codex, Claude, OpenCode, or Kimi not open?

Each CLI is optional and must be installed and available on PowerShell's
`PATH`.
[See diagnostics](TROUBLESHOOTING.md#a-coding-agent-does-not-open).

### What should I do if PowerShell blocks `install.ps1`?

Inspect the script and unblock only that file if you trust its origin. Do not
disable execution policy globally.
[See the procedure](TROUBLESHOOTING.md#installps1-is-blocked-by-powershell).

### What should I do if a download or checksum fails?

Check the connection, proxy, or firewall and retry. Do not bypass SHA-256
verification.
[See the explanation](TROUBLESHOOTING.md#download-or-checksum-failure).

### What should I do if the TUI exits or keys do not respond?

Run `dev` from PowerShell 7 in Windows Terminal, close older instances, and
update DevNav.
[See diagnostics](TROUBLESHOOTING.md#unexpected-exit-or-incorrect-keyboard-input).

### How do I update DevNav?

Run `dev update` from PowerShell or press `Shift+U` inside the TUI. This also
applies to installations bootstrapped through npm, Bun, pnpm, or Yarn.
[See the steps](TROUBLESHOOTING.md#install-an-update-manually).

### How do I disable or re-enable the startup update check?

Press `Ctrl+U` inside the TUI. You can also use
`Set-DevUpdateCheck $false` or `Set-DevUpdateCheck $true` from PowerShell. The
preference survives updates.
[See details](TROUBLESHOOTING.md#change-the-startup-check-preference).

## License

MIT. See [LICENSE](LICENSE).
