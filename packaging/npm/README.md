# @jacoboptimiza/devnav

Native high-performance workspace navigator for PowerShell 7 on Windows.

This package is the **bootstrap channel** for DevNav: it carries the official
x64 and ARM64 Inno Setup installers inside the tarball, verifies their SHA-256
hashes against the release manifest, and runs the matching installer
silently. After installation, DevNav lives as a standalone application under
`%LOCALAPPDATA%\Programs\DevNav` with its own updater — this package does not
need to stay installed.

No `postinstall` scripts, no runtime dependencies: nothing happens until you
explicitly run `install`.

## Install

With Bun:

```sh
bunx --bun @jacoboptimiza/devnav install
```

With npm:

```sh
npx --yes @jacoboptimiza/devnav install
```

With pnpm:

```sh
pnx @jacoboptimiza/devnav install
```

With Yarn:

```sh
yarn dlx -p @jacoboptimiza/devnav devnav install
```

Then open a new PowerShell 7 window and run:

```powershell
dev
```

## What `devnav install` does

1. Checks the platform (`win32`) and architecture (`x64` or `arm64`).
2. Selects the bundled installer for your architecture.
3. Verifies its SHA-256 hash against `release-manifest.json`; aborts on mismatch.
4. Runs the Inno Setup installer silently (`/VERYSILENT /SUPPRESSMSGBOXES /NORESTART`).
5. Verifies the installed `dev.exe --version` matches the package version.

## Requirements

- Windows 10/11 on x64 or ARM64.
- PowerShell 7 (`pwsh`) available on `PATH`.
- Any of Bun, Node.js (via npm), pnpm, or Yarn to run the bootstrap.

## Links

- Repository: <https://github.com/JacobOptimiza/dev-nav>
- Releases: <https://github.com/JacobOptimiza/dev-nav/releases>
- Security: <https://github.com/JacobOptimiza/dev-nav/security>
- License: [MIT](https://github.com/JacobOptimiza/dev-nav/blob/main/LICENSE)
