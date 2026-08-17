# Security policy

## Supported versions

Security fixes are provided for the latest stable DevNav release line. The
currently supported release is `0.13.x` (latest: `0.13.0`). Please update to
the latest release before reporting an issue against an older version.

## Reporting a vulnerability

Please use [GitHub Private Vulnerability Reporting](https://github.com/JacobOptimiza/dev-nav/security/advisories/new)
to report security vulnerabilities privately. Do not open a public issue for a
sensitive vulnerability or disclose it publicly before we have had a chance to
respond.

Include the affected version, operating system and architecture, reproduction
steps or a proof of concept, impact, and any relevant logs or configuration
details (with secrets removed). We will acknowledge a report within seven days
and keep the reporter informed as we investigate.

## Response process

Reports received through private vulnerability reporting follow this process:

1. **Acknowledge** the report within seven days.
2. **Assess** validity, affected versions, and impact, reproducing the issue
   locally where possible.
3. **Fix** confirmed vulnerabilities on a private branch, with a regression
   test where practical, and ship the fix in a new release of the supported
   line.
4. **Disclose** through a GitHub security advisory once the fix is available,
   crediting the reporter unless they prefer otherwise.

No additional SLA is introduced by this process; complex issues may take
longer, and the reporter is kept informed as work progresses.

There have been no resolved vulnerabilities in the last twelve months and no
published GitHub security advisories, so no reporter credit has been issued to
date. Reporters who want credit will be named in the advisory and release
notes unless they ask to remain anonymous.

## Security expectations

Users can expect DevNav to avoid telemetry, keep its configuration local to the
current Windows user, verify downloaded release files with SHA-256 in the
supported installation and update paths, and require explicit confirmation
before an update is installed.

DevNav is not a sandbox. Custom commands, coding-agent CLIs, and other commands
returned to PowerShell execute with the permissions of the current user.
SHA-256 checks verify integrity against published metadata but are not digital
signatures, and the current v0.13.0 release must not be represented as signed.
Static-analysis coverage also has the Rust extraction limitation documented
below.

No SLA, absolute-security guarantee, or new vulnerability-response commitment
is introduced by this section.

## Security controls

CodeQL analyzes Rust, GitHub Actions and JavaScript/TypeScript on pushes to
`main` and pull requests. The Rust lane uses the buildless extractor
(`build-mode: none`) on Ubuntu; it was tried on `windows-latest` with no
extraction improvement, so the simpler lane is kept. Because buildless
extraction does not compile the crate, 9 of the 10 Rust files currently
produce macro-expansion diagnostics (`matches!`, `format!`, …); this residual
is an extractor limitation, is tracked rather than hidden, and a green CodeQL
run is not evidence of extraction-clean Rust analysis. OpenSSF Scorecard runs
on `main` and publishes its current result through the repository badge.

Additional automated controls:

- `cargo deny check` (advisories, bans, licenses, sources) in CI on pushes to
  `main` and pull requests.
- ClusterFuzzLite fuzzing of the `config.tsv` parser on qualifying pull
  requests.
- Coverage floors enforced in CI (>= 80%): Rust production-only lines and
  regions (`scripts/rust-production-coverage.py`), PowerShell commands and
  lines (`scripts/invoke-pester-coverage.ps1`), and npm bootstrap lines
  (`scripts/invoke-npm-coverage.ps1`).
- Release integrity: every artifact ships a SHA-256 checksum; the npm
  bootstrap verifies installers against `release-manifest.json` before
  executing them, and Scoop/WinGet manifests pin release hashes. Checksums
  verify integrity, not authenticity.
- Future release artifacts receive GitHub build attestations; an attestation
  proves build provenance and is not equivalent to a legacy code-signing
  signature.

These controls complement, but do not replace, private vulnerability
reporting.

## Trust boundaries and threat surface

See [ARCHITECTURE.md](ARCHITECTURE.md) for the component layout. In summary:
the Rust binary is a local console application that never executes commands;
the PowerShell module is the component that acts on the user's session using
intents the user typed or configured locally; network access is limited to
GitHub Releases for update checks/downloads and to package managers during
initial installation. Configuration lives in a single per-user file
(`%LOCALAPPDATA%\DevNav\config.tsv`).
