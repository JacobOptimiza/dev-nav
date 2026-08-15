# Contributing

DevNav is a public project. Use the repository's Issue and pull-request
templates for non-sensitive reports and focused changes. Security
vulnerabilities must always use private reporting through [SECURITY.md](SECURITY.md).

You may inspect, clone, download, and fork the project under the terms of the
MIT license. Keep changes small, focused, documented, and scoped to one
purpose.

## Development prerequisites

- Windows on x64 or ARM64 and PowerShell 7 or newer.
- Rust 1.97 or newer (the CI toolchain is pinned to 1.97.1) with MSVC Build
  Tools for native builds.
- Node.js only for the npm bootstrap tests. The package declares Node `>=22`;
  CI tests 22, 24, and 26, with Node 24 as the release baseline.

For new Node.js environments, prefer a currently supported release line. Node
is never required to run the installed native DevNav application.

Before maintaining a fork or preparing an internal change, run the same quality gates as CI:

```powershell
cargo fmt --all -- --check
cargo check --workspace --all-targets
cargo test --workspace
cargo clippy --workspace --all-targets -- -D warnings
cargo deny check
./scripts/validate-powershell.ps1
Invoke-Pester -Path ./tests/powershell
node --test "tests/npm/**/*.test.mjs"
```

The repository also fuzzes the `config.tsv` parser with ClusterFuzzLite on
pull requests that affect its Rust source or fuzzing integration. Fuzzing is a
supplement to, not a replacement for, the ordinary test suite.

## Testing policy

Major new functionality must include appropriate automated tests for its new
behavior. Bug fixes must include regression tests when reasonably practical.
Add or update the applicable existing suite for the component you change:
Rust, PowerShell/Pester, or the npm bootstrap. All applicable tests must pass
in CI before merge. Documentation-only changes and changes that do not alter
behavior do not need new tests.

Use a focused branch and pull request, wait for CI, and squash merge only after
the applicable checks pass. New Actions references must use full commit SHAs.

Do not disclose security vulnerabilities publicly. Report them privately as
described in [SECURITY.md](SECURITY.md).

## Releasing

Every channel ships the exact bytes built once by the release workflow: the
GitHub release is canonical, npm and Scoop derive from it, and the workflow
also generates the versioned WinGet submission asset. One
version is shared by `Cargo.toml`, the Git tag, the GitHub release,
`powershell/DevNav.psd1`, `packaging/npm/package.json` and
`packaging/scoop/devnav.template.json`; CI and the release workflow abort on any
mismatch. npm versions are immutable once public, so treat them with the same
care as tags.

Future release artifacts receive GitHub build attestations. Consumers can
verify a downloaded artifact with `gh attestation verify <artifact> -R
JacobOptimiza/dev-nav`.

The npm and Scoop channels must never publish versions up to and including
0.9.7 — those releases predate this packaging. v0.10.0 is the first
multichannel release; the release workflow enforces the floor.

### npm trusted publishing

Publishing uses OIDC trusted publishing with staged publishing; no `NPM_TOKEN`
exists anywhere. The trusted publisher is restricted to repository
`JacobOptimiza/dev-nav`, workflow `release.yml`, environment `npm-production`,
and the `npm stage publish` action. The initial v0.10.0 package was published
manually to establish the package; later releases stage the exact tested
tarball for maintainer approval on npmjs.com.

### Scoop bucket

The Scoop manifest lives in the separate `JacobOptimiza/scoop-bucket`
repository; see [packaging/scoop/README.md](packaging/scoop/README.md) for
seeding it from the generated `devnav.scoop.json` release asset and for the
`checkver`/`autoupdate` automation.
