# Troubleshooting

**English** | [Español](TROUBLESHOOTING.es.md)

This guide contains diagnostic procedures. Start with the installation and
shortcut documentation in the [README](README.md).

## Quick diagnostics

Run in PowerShell 7:

```powershell
$PSVersionTable.PSVersion
Get-Command dev -ErrorAction SilentlyContinue
Test-Path (Join-Path $env:LOCALAPPDATA 'Programs\DevNav\DevNav.psm1')
```

If `dev` is available, also check the configured root:

```powershell
Get-DevRoot
Test-Path -LiteralPath (Get-DevRoot)
```

DevNav requires PowerShell 7 or newer and an existing startup directory.

## Installation

### `install.ps1` is blocked by PowerShell

Inspect the downloaded script before allowing it:

```powershell
Get-Content .\install.ps1
Unblock-File .\install.ps1
.\install.ps1
```

Do not disable execution policy globally. If your organization enforces a
policy, ask its administrator before bypassing it.

### Download or checksum failure

The installer intentionally stops if a release asset cannot be downloaded or
its SHA-256 checksum differs.

```powershell
Test-NetConnection github.com -Port 443
Invoke-WebRequest https://github.com -Method Head
```

Check the proxy, firewall, TLS inspection, and GitHub availability. Retry the
installer; never remove checksum verification.

### Rust or Cargo is missing

Normal installation downloads a published binary and does not need Rust or
Visual Studio. Rust and the MSVC Build Tools are required only for:

```powershell
.\install.ps1 -BuildFromSource
```

Install Rust from [rustup](https://rustup.rs/) and the Microsoft C++ build tools,
then verify:

```powershell
rustc --version
cargo --version
```

### The `dev` command is unavailable

`dev` is a PowerShell alias exported by the DevNav module; the installer does
not add `dev.exe` directly to the global `PATH`.

This also applies after a successful Bun, npm, pnpm, Yarn, PowerShell or GitHub
installer bootstrap. Open a new PowerShell 7 session before diagnosing the
installation.

For classic/bootstrap installations, the module normally lives under:

```text
%LOCALAPPDATA%\Programs\DevNav
```

For Scoop-managed installations, diagnose the Scoop-owned copy instead:

```powershell
scoop prefix devnav
Get-Module -ListAvailable DevNav
Get-Command dev -ErrorAction SilentlyContinue
```

Open a new PowerShell 7 window and run:

```powershell
$PROFILE
Get-Content -LiteralPath $PROFILE
Get-Module -ListAvailable
Get-Command dev -ErrorAction SilentlyContinue
```

Classic/bootstrap installations should import:

```text
%LOCALAPPDATA%\Programs\DevNav\DevNav.psm1
```

To repair a classic/bootstrap installation, rerun `install.ps1`. For Scoop,
use `scoop update devnav`, or, if necessary, `scoop uninstall devnav` followed
by `scoop install jacoboptimiza/devnav`. Do not place `dev.exe` alone on `PATH`,
because that bypasses the wrapper required to change the current shell
directory and run commands. Do not repair a Scoop installation by editing the
PowerShell profile manually.

## Configuration

### Correct the startup directory

The recommended flow is visual:

1. Run `dev`.
2. Highlight the correct directory.
3. Press `Ctrl+S`.
4. Verify the full path and press `Enter`.

The automation-friendly equivalent is:

```powershell
Set-DevRoot $HOME
Get-DevRoot
Test-Path -LiteralPath (Get-DevRoot)
```

`DEV_HOME` remains a compatibility fallback only when no startup directory has
been saved.

### Favorites are missing

Press `Shift+F` inside DevNav. The list header indicates whether global favorite
shortcuts are visible or hidden. This preference persists between sessions.

Hiding global shortcuts does not delete favorites. Verify the local file exists:

```powershell
$config = Join-Path $env:LOCALAPPDATA 'DevNav\config.tsv'
Test-Path -LiteralPath $config
Select-String -LiteralPath $config -Pattern '^favorite\t'
```

Do not publish this file: it contains local paths and aliases.

### A coding agent does not open

Check which optional CLIs are available:

```powershell
'codex', 'claude', 'opencode', 'kimi' | ForEach-Object {
    $command = Get-Command $_ -ErrorAction SilentlyContinue
    [pscustomobject]@{
        CLI       = $_
        Available = [bool] $command
        Path      = $command.Source
    }
}
```

Install the missing CLI through its official installer and open a new terminal.

## TUI behavior

### Unexpected exit or incorrect keyboard input

1. Use PowerShell 7 inside Windows Terminal.
2. Run `dev`, not the internal `dev.exe` directly.
3. Close older DevNav instances.
4. Update DevNav using the installation channel that owns it, then open a new
   terminal.

If the problem continues, record the error shown after returning to the prompt
and include:

```powershell
$PSVersionTable.PSVersion
Get-Command dev
Get-DevRoot
```

## Updates

### Change the startup-check preference

Press `Ctrl+U` inside the TUI, or set it explicitly from PowerShell:

```powershell
Set-DevUpdateCheck $true   # enable
Set-DevUpdateCheck $false  # disable
```

DevNav asks only once when no preference exists. The check is silent when the
installed version is current or the network is unavailable, and no update is
installed without explicit confirmation.

### Install an update manually

Classic/bootstrap channels (Bun, npm, pnpm, Yarn, PowerShell and the GitHub
installer) use DevNav's own updater. Scoop installations use `scoop update
devnav`; do not use the package runner to update them. On Scoop, `dev update`
only delegates to Scoop and does not self-update.

Run:

```powershell
dev update
```

Or press `Shift+U` inside the TUI. The updater compares versions, verifies the
downloaded executable and module, and replaces only application files. It does
not overwrite `%LOCALAPPDATA%\DevNav\config.tsv`, so the startup directory,
favorites, aliases, and UI preferences remain intact.

Users upgrading from a version older than `0.5.0` must update once from a clone:

```powershell
git pull --ff-only
.\install.ps1
```
