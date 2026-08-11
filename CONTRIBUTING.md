# Contributing

Contributions are welcome through GitHub pull requests.

1. Fork the repository and create a focused branch.
2. Do not commit credentials, personal paths, generated binaries, configuration,
   favorites, aliases, or environment files.
3. Keep Windows 10/11 x64 and ARM64 compatibility.
4. Run the complete validation suite:

   ```powershell
   cargo fmt -- --check
   cargo test
   cargo clippy --all-targets -- -D warnings
   cargo build --release
   ```

5. Explain the behavior change and verification in the pull request.

All changes require CI and owner review before merge. Security vulnerabilities
must be reported privately as described in [SECURITY.md](SECURITY.md).
