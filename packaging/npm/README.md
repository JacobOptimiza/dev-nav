# @jacoboptimiza/devnav

Official bootstrap for DevNav, the native workspace navigator for PowerShell 7
on Windows.

Use the package runner you already have. Each command installs the same official
native DevNav release for Windows x64 or ARM64.

## Install

### Bun

```sh
bunx --bun @jacoboptimiza/devnav install
```

### npm

```sh
npx --yes @jacoboptimiza/devnav install
```

### pnpm

```sh
pnx @jacoboptimiza/devnav install
```

### Yarn

```sh
yarn dlx -p @jacoboptimiza/devnav devnav install
```

Then open a new PowerShell 7 window and run:

```powershell
dev
```

After installation, use `dev update`. Bun, npm, pnpm and Yarn are verified
bootstrap channels; they do not own or update the installed application.

## Security properties

- No `postinstall` script.
- Zero runtime dependencies.
- Explicit installation only through the `install` command.
- Architecture selection restricted to Windows x64 and ARM64.
- Installer SHA-256 verified against `release-manifest.json`.
- Installed `dev.exe` version verified after setup.

## What `devnav install` does

1. Checks the platform (`win32`) and architecture (`x64` or `arm64`).
2. Selects the bundled installer for your architecture.
3. Verifies its SHA-256 hash against `release-manifest.json`; aborts on mismatch.
4. Runs the Inno Setup installer silently (`/VERYSILENT /SUPPRESSMSGBOXES /NORESTART`).
5. Verifies the installed `dev.exe --version` matches the package version.

The package carries the x64 and ARM64 Inno Setup installers from the canonical
GitHub Release. It runs the matching installer and then gets out of the way;
DevNav remains a standalone native application under
`%LOCALAPPDATA%\Programs\DevNav`.

## Requirements

- Windows 10/11 on x64 or ARM64.
- PowerShell 7 (`pwsh`) available on `PATH`.
- Any of Bun, Node.js (via npm), pnpm, or Yarn to run the bootstrap.

## Links

- Repository: <https://github.com/JacobOptimiza/dev-nav>
- Releases: <https://github.com/JacobOptimiza/dev-nav/releases>
- Security: <https://github.com/JacobOptimiza/dev-nav/security>
- License: [MIT](https://github.com/JacobOptimiza/dev-nav/blob/main/LICENSE)
