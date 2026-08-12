# Contributing

Issues and focused Pull Requests are welcome. CI is required for every change;
submission does not guarantee merge. The `main` branch is protected and changes
must go through a Pull Request.

You may inspect, clone, download, and fork the project under the terms of the MIT
license. Please keep changes small, focused, and documented.

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
