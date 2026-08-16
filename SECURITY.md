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
