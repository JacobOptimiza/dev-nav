# Security policy

## Supported versions

Security fixes are provided for the latest stable DevNav release line. The
currently supported release is `0.12.x` (latest: `0.12.0`). Please update to
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

CodeQL analyzes Rust and GitHub Actions on pushes to `main` and pull requests.
OpenSSF Scorecard runs on `main` and publishes its current result through the
repository badge. These controls complement, but do not replace, private
vulnerability reporting.
