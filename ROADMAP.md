# Roadmap

DevNav is distributed through GitHub Releases, the public npm bootstrap package,
and the public Scoop bucket.
Release payloads are checksum-verified with SHA-256; checksums verify integrity
and are not digital signatures.

## Planning horizon

This roadmap covers the next 12 months from its current revision. During that
horizon DevNav intends to keep Windows x64 and ARM64 as the supported
platforms, maintain the native Rust + PowerShell architecture, preserve the
GitHub Release, npm-bootstrap and Scoop distribution paths, pursue public
WinGet catalog availability, and continue improving quality and security
controls without rewriting published release history.

During the same horizon DevNav does not plan to claim Linux or macOS support,
replace the native core with a JavaScript runtime, or make package runners own
updates after installation. Linux/WSL remains an evaluation item rather than a
committed deliverable.

## Current maintenance and quality baseline

- [x] Rust, PowerShell and npm bootstrap test suites green in CI on pushes to
  `main` and on pull requests (pinned toolchains: Rust 1.97.1, Pester 6.1.0,
  PSScriptAnalyzer 1.25.0, Node 22/24/26 with 24 as the release baseline).
- [x] Coverage floors enforced in CI at >= 80% for all three languages:
  Rust production-only lines and regions, PowerShell commands and lines, and
  npm bootstrap lines (Node native coverage).
- [x] CodeQL static analysis for Rust, GitHub Actions and
  JavaScript/TypeScript; ClusterFuzzLite fuzzing of the `config.tsv` parser;
  `cargo deny` advisory/license/ban checks.
- [x] Version consistency across all channels enforced mechanically.

## Near-term quality and security work

- [ ] Keep reducing CodeQL Rust extraction errors if upstream extractor
  support improves (current residual is macro-expansion-related and documented
  in [SECURITY.md](SECURITY.md)).
- [ ] Revisit OpenSSF Scorecard findings that require organizational decisions
  (branch protection coverage, review and maintenance signals) rather than
  code changes.
- [ ] Validate a real cross-version Scoop upgrade on a future release and
  automate WinGet submissions once a catalog installation is verified.

## Distribution status

- [x] GitHub releases with x64 and ARM64 application binaries.
- [x] Per-user Windows installers and PowerShell integration.
- [x] Publish the v0.10.0 multichannel release payload.
- [x] Publish `@jacoboptimiza/devnav` as a public npm bootstrap package.
- [x] Verify Bun, npm, pnpm and Yarn bootstrap commands from the public registry.
- [x] Configure npm Trusted Publishing for future releases.
- [x] Publish portable x64 and ARM64 Scoop artifacts in the GitHub Release.
- [x] Create and validate the public `JacobOptimiza/scoop-bucket` bootstrap.
- [x] Generate WinGet manifests with immutable versioned URLs and SHA-256.
- [x] Submit the initial `JacobOptimiza.DevNav` manifests to
  `microsoft/winget-pkgs`.
- [ ] Microsoft acceptance and public WinGet catalog propagation.
- [x] Validate fresh Scoop install, package-manager ownership, update behavior,
  and uninstall on a clean GitHub-hosted Windows runner.
- [ ] Validate a real cross-version Scoop upgrade on a future release.
- [ ] Automate future WinGet submissions after a real catalog installation has
  been verified.

The roadmap describes status only. Operational instructions live in the
packaging documentation and workflows.
