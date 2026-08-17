# DevNav

**Jump between Windows workspaces, launch coding agents, and run project commands without leaving PowerShell.**

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

DevNav is a fast, keyboard-first native Rust TUI for developers who work across many repositories. Fuzzy-find a workspace, jump straight into it, launch or resume a coding agent, or fire a saved project command in a few keystrokes.

**[Install](#install) · [Quick start](#quick-start) · [Workflow](#built-for-your-terminal-workflow) · [Security](#security-by-default) · [Docs](#project-docs)**

![Animated DevNav terminal interface](assets/demo/devnav.gif)

## Why DevNav

- **Jump faster** — fuzzy-find projects instead of remembering paths or drilling through directory trees.
- **Keep context close** — global favorites and aliases keep the workspaces you use most one action away.
- **Launch where you work** — start or resume Codex, Claude Code, OpenCode and Kimi directly in the selected repository.
- **Automate the repetitive** — bind up to nine project commands to `Shift+1–9`.
- **Stay native** — Rust + Win32, one direct dependency, no TUI framework and no application runtime required after installation.

## Install

### PowerShell

```powershell
irm https://raw.githubusercontent.com/JacobOptimiza/dev-nav/main/install.ps1 | iex
```

Or use the package tool you already have:

| Channel | Command |
|---|---|
| Scoop | `scoop bucket add jacoboptimiza https://github.com/JacobOptimiza/scoop-bucket; scoop install jacoboptimiza/devnav` |
| npm | `npx --yes @jacoboptimiza/devnav install` |
| Bun | `bunx --bun @jacoboptimiza/devnav install` |
| pnpm | `pnx @jacoboptimiza/devnav install` |
| Yarn | `yarn dlx -p @jacoboptimiza/devnav devnav install` |

You can also download the official x64 or ARM64 installer from the [latest GitHub Release](https://github.com/JacobOptimiza/dev-nav/releases/latest).

The package-runner commands are bootstrap channels, not a JavaScript version of DevNav. After installation use `dev update`; Scoop-managed installs use `scoop update devnav`.

## Quick start

Open a new PowerShell 7 session and run:

```powershell
dev
```

Choose the workspace you want DevNav to open by default and press `Ctrl+S` once. From then on, navigation stays keyboard-first:

| Key | Action |
|---|---|
| `/` | Fuzzy-filter workspaces |
| `Enter` | Jump to the selected directory |
| `f` / `a` | Favorite / alias |
| `c` / `r` | Codex new / resume |
| `d` / `Shift+D` | Claude Code new / resume |
| `o` / `Shift+O` | OpenCode new / resume |
| `i` / `Shift+I` | Kimi new / resume |
| `Shift+1–9` | Run a saved project command |
| `F3` | Manage custom commands |
| `F1` | Full keyboard help |

Press `F2` to switch between English and Español.

## Built for your terminal workflow

- **Global favorites** stay available even when you navigate outside your startup directory or across drives.
- **Readable aliases** add a friendly name without hiding the real repository or command.
- **Fast fuzzy search** narrows large workspace trees without leaving the TUI.
- **Project actions stay in context** — agents and commands launch in the selected directory.
- **Updates stay simple** — use `Shift+U` in the TUI or `dev update` from PowerShell.

Repository aliases keep the real identity visible:

```text
Navegador PowerShell | dev-nav
```

Custom commands do the same for the action they run:

```text
Lanzar servidor > bun run dev
```

## Coding agents

DevNav can launch or resume **Codex, Claude Code, OpenCode and Kimi** directly in the selected repository.

Codex, Claude and OpenCode keep an `Agent/repo` terminal title while running. Kimi currently uses its own live session title; DevNav restores the previous terminal title when Kimi exits.

Agent CLIs are optional and must already be installed and available on `PATH`.

## Custom commands

Save up to nine project commands and run them with `Shift+1–9`. Press `F3` to create, edit or remove them.

```powershell
dev shortcut 1 "Tests" "cargo test"
dev shortcut 2 "Dev" "bun run dev"
```

Aliases stay friendly without hiding what actually runs, and bindings remain local to your DevNav configuration.

## Security by default

- **No telemetry.** Network access is limited to installation, release checks and explicit updates.
- Downloads are checked against **SHA-256 release metadata** before installation or update.
- The release pipeline uses **Sigstore keyless signing, GitHub build attestations and in-toto provenance**.
- npm publishing uses **OIDC Trusted Publishing** with no persistent `NPM_TOKEN`.
- GitHub Actions use **minimal permissions and commit-pinned actions**, with private vulnerability reporting for sensitive security issues.

See [SECURITY.md](SECURITY.md) for the security policy and [SIGNING.md](SIGNING.md) for release verification.

## Requirements

- Windows 10 or 11 on x64 or ARM64.
- PowerShell 7 or newer.
- Windows Terminal recommended.

Published builds do not require Rust, Visual Studio, Node.js or Bun at runtime. Node.js or Bun is needed only when you choose its package-runner bootstrap command.

## Project docs

| Document | Purpose |
|---|---|
| [TROUBLESHOOTING.md](TROUBLESHOOTING.md) | Installation and runtime diagnostics |
| [SECURITY.md](SECURITY.md) | Security policy and vulnerability reporting |
| [SIGNING.md](SIGNING.md) | Release signatures and verification |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Internals and trust boundaries |
| [ASSURANCE.md](ASSURANCE.md) | Evidence-based assurance case |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Development, testing and release policy |
| [ROADMAP.md](ROADMAP.md) | Planned distribution and product work |

## License

MIT. See [LICENSE](LICENSE).
