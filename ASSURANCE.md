# Assurance case

This page states verifiable claims about DevNav, the evidence that backs them,
and the residual limitations that remain. It is intentionally narrow: only
properties the repository itself can demonstrate.

## Build and test quality

**Claim.** The Rust workspace builds warning-free and its full test suite
passes on the pinned toolchain (1.97.1).

**Evidence.** CI `validate` job: `cargo fmt --check`, `cargo check
--workspace --all-targets`, `cargo test --workspace`, `cargo clippy
--workspace --all-targets -- -D warnings`, `cargo deny check`. PowerShell:
parser + PSScriptAnalyzer + Pester (`.github/workflows/ci.yml`).

**Residual limitation.** None for this claim.

## Test coverage ≥ 80% (per language)

**Claim.** Test coverage stays at or above 80% for Rust production code, the
PowerShell integration, and the npm bootstrap, enforced in CI.

**Evidence.**
- Rust: `scripts/rust-production-coverage.py` computes production-only
  coverage from `cargo llvm-cov` 0.8.7 JSON, excluding only `#[cfg(test)]`
  items (analyzed by its own unit tests, `tests/coverage/`). The CI `validate`
  job fails below 80% lines or regions. Current: 87.60% lines / 86.30%
  regions.
- PowerShell: `scripts/invoke-pester-coverage.ps1` runs Pester 6.1.0 once
  with JaCoCo coverage over `powershell/DevNav.psm1`, `install.ps1` and
  `installer/ProfileIntegration.ps1`; the CI `powershell` job fails below 80%
  commands or lines. Current: 82.19% / 82.87%.
- JavaScript: `scripts/invoke-npm-coverage.ps1` runs the bootstrap tests under
  Node's native test runner with `--experimental-test-coverage`; the
  Node 24 leg of the CI `distribution` job fails below 80% lines. Current:
  93.79% lines. (Node reports *line* coverage; the historical
  93.78% *statement* figure is kept only as a baseline reference.)

**Residual limitation.** Rust coverage excludes host-bound code paths
(`Terminal::enter/size/drop`, `read_key`, `Renderer::draw`, `run()/main()`,
`detect_system_locale`) from the numerator only because they require a real
interactive console; they remain in the denominator and are not automatically
covered by this suite.

## Dependency policy

**Claim.** Dependencies are pinned (`Cargo.lock`), license-audited and
vulnerability-checked in CI on pushes to `main` and pull requests.

**Evidence.** `cargo deny check` (advisories, bans, licenses, sources) in the
CI `validate` job; Dependabot configuration; the npm bootstrap has zero
runtime dependencies.

**Residual limitation.** Advisory data depends on the RustSec/advisory-database
feed at check time.

## Static analysis

**Claim.** CodeQL analyzes Rust, GitHub Actions and JavaScript/TypeScript on
pushes to `main` and pull requests.

**Evidence.** `.github/workflows/codeql.yml`; results upload to
security/code-scanning.

**Residual limitation.** Rust extraction runs the buildless extractor
(`build-mode: none`) and currently reports 9 of 10 files with macro-expansion
diagnostics; running the lane on `windows-latest` was tried and did not reduce
them. A green CodeQL run is therefore not evidence of extraction-clean
analysis.

## Fuzzing

**Claim.** The `config.tsv` parser is fuzz-tested automatically on qualifying
pull requests.

**Evidence.** ClusterFuzzLite (`.clusterfuzzlite/`, `.github/workflows/cflite_pr.yml`)
on pull requests affecting its Rust source or fuzzing integration.

**Residual limitation.** Fuzzing covers the parser target only; it does not
replace the unit suites.

## Release integrity and provenance

**Claim.** Release artifacts are built once by the release workflow, checksums
(SHA-256) are published for every artifact, channels derive from the canonical
GitHub Release, and future artifacts receive GitHub build attestations.

**Evidence.** `.github/workflows/release.yml`; `release-manifest.json`
verification in the npm bootstrap; Scoop/WinGet manifests carry release
SHA-256 hashes; version consistency across `Cargo.toml`, tag, release,
`DevNav.psd1`, `package.json` and the Scoop template is enforced by CI.

**Residual limitation.** SHA-256 checksums verify integrity, not authenticity.
A build attestation proves workflow provenance and is not equivalent to a
legacy code-signing signature on the binaries.

## Package and version consistency

**Claim.** One version is shared by every channel and checked mechanically.

**Evidence.** CI consistency checks abort the release on any mismatch; npm and
Scoop enforce a `0.10.0` floor for multichannel packaging.

**Residual limitation.** None for this claim.

## Not automatable

The following remain human responsibilities and are not covered by any
automated gate: code review quality, issue triage, the decision to publish a
release, and manual verification of the interactive TUI on real consoles.
