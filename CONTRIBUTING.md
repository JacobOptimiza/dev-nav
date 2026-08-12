# Repository policy

DevNav is published as a read-only source and binary distribution repository.
Only repository administrators maintain the protected `main` branch. External
Issues and Pull Requests are not accepted.

You may inspect, clone, download, and fork the project under the terms of the MIT
license. A fork is independent and does not grant write access to this repository.

Before proposing changes in a fork, run the same quality gates as CI:

```powershell
cargo fmt --all -- --check
cargo check --workspace --all-targets
cargo test --workspace
cargo clippy --workspace --all-targets -- -D warnings
cargo deny check
./scripts/validate-powershell.ps1
Invoke-Pester -Path ./tests/powershell
```

Do not disclose security vulnerabilities publicly. Report them privately as
described in [SECURITY.md](SECURITY.md).
