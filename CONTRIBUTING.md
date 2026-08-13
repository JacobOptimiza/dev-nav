# Contributing

DevNav is a public, read-only project for inspection, cloning and downloading.
The maintainer keeps the canonical repository changes internal; external Issues
and Pull Requests are not part of the current contribution model. Security
vulnerabilities must always use private reporting through [SECURITY.md](SECURITY.md).

You may inspect, clone, download, and fork the project under the terms of the MIT
license. Please keep changes small, focused, and documented.

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

Do not disclose security vulnerabilities publicly. Report them privately as
described in [SECURITY.md](SECURITY.md).

## Releasing

Every channel ships the exact bytes built once by the release workflow: the
GitHub release is canonical and npm, Scoop and WinGet derive from it. One
version is shared by `Cargo.toml`, the Git tag, the GitHub release,
`powershell/DevNav.psd1`, `packaging/npm/package.json` and
`packaging/scoop/devnav.template.json`; CI and the release workflow abort on any
mismatch. npm versions are immutable once public, so treat them with the same
care as tags.

The npm and Scoop channels must never publish versions up to and including
0.9.7 — those releases predate this packaging. v0.10.0 is the first
multichannel release; the release workflow enforces the floor.

### npm trusted publishing

Future publishing uses OIDC trusted publishing with staged publishing; no
`NPM_TOKEN` exists anywhere. The trusted publisher is restricted to repository
`JacobOptimiza/dev-nav`, workflow `release.yml`, environment `npm-production`,
and the `npm stage publish` action. The initial v0.10.0 package was published
manually to establish the package; later releases stage the exact tested
tarball for maintainer approval on npmjs.com.

### Scoop bucket

The Scoop manifest lives in the separate `JacobOptimiza/scoop-bucket`
repository; see [packaging/scoop/README.md](packaging/scoop/README.md) for
seeding it from the generated `devnav.scoop.json` release asset and for the
`checkver`/`autoupdate` automation.
