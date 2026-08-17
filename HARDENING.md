# Hardening audit

This document records the hardening review of DevNav: the concrete mechanisms
the project applies, verified against the current source tree, and the
residual limitations. It is an audit of what exists, not a claim of absolute
security.

## Memory safety and build hardening

- The core application is written in Rust, a memory-safe language. `unsafe`
  appears only at the Win32 console boundary (`src/input.rs`,
  `src/terminal.rs`, `src/config.rs`, `src/main.rs`), where the API contract
  requires it; each use is narrow and localized.
- Release builds use `lto = "thin"`, `codegen-units = 1`, `panic = "abort"`,
  and stripped symbols (`Cargo.toml` `[profile.release]`).
- Dependencies are pinned by `Cargo.lock` and screened by `cargo deny check`
  (advisories, bans, licenses, sources) on every push and pull request.

## Input handling

- The `config.tsv` parser is the only parser of file content that may be
  externally influenced. It is covered by unit tests, regression tests for
  malformed records, and ClusterFuzzLite fuzzing on qualifying pull requests
  (`fuzz/`).
- Shortcuts and custom commands are executed by PowerShell with the current
  user's permissions by design; DevNav is not a sandbox and does not claim to
  be one (see [SECURITY.md](SECURITY.md)).

## Network and cryptography

- The Rust binary performs **no network access** (verified: no HTTP/TLS use in
  `src/`).
- All network traffic happens in the PowerShell layer and only against
  `github.com` / `api.github.com` over HTTPS: update checks
  (`Invoke-RestMethod`), release downloads (`Invoke-WebRequest`), and the
  installer (`install.ps1`). GitHub requires TLS 1.2 or newer, and DevNav
  relies on the platform TLS stack (.NET/Schannel) with default certificate
  validation — no code disables or bypasses certificate verification.
- No custom cryptography is implemented; the only digest used is SHA-256 for
  artifact integrity, provided by the platform (`Get-FileHash`).
- DevNav stores no credentials and transmits none. Update downloads are
  restricted to an allow-listed URL pattern of the project's own GitHub
  Releases and are verified against `SHA256SUMS.txt` before use; the npm
  bootstrap additionally verifies installer hashes against the
  `release-manifest.json` shipped in the package. SHA-256 verification proves
  integrity, not authenticity (no code signing yet; see
  [SECURITY.md](SECURITY.md)).
- The Inno Setup compiler used in CI is itself downloaded over HTTPS and
  pinned to verified SHA-256 hashes
  (`scripts/invoke-inno-compiler.ps1`).

## Supply chain

- GitHub Actions are pinned to full commit SHAs; OpenSSF Scorecard and CodeQL
  run on `main` and pull requests.
- npm publishing uses OIDC trusted publishing — no long-lived `NPM_TOKEN`
  exists (see [CONTRIBUTING.md](CONTRIBUTING.md#npm-trusted-publishing)).
- Release builds are bit-for-bit reproducible and checked by
  `scripts/verify-build-repeatability.ps1`.

## Least privilege and local data

- Configuration is a single per-user file under `%LOCALAPPDATA%\DevNav`;
  no elevated privileges are requested by the application or installer beyond
  a per-user install directory.
- CI workflows run with minimal `permissions:` blocks and
  `persist-credentials: false` checkouts.

## Residual limitations

- Artifacts are not code-signed; integrity today is checksum- and
  attestation-based (build attestations are planned for future releases).
- The TUI paths that touch the Win32 console cannot be fully exercised in
  automated tests; coverage gates apply to everything else.
