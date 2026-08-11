# Security policy

## Supported versions

Only the latest published release receives security fixes.

## Reporting a vulnerability

Do not disclose suspected vulnerabilities in a public issue. Use GitHub's
private vulnerability reporting feature in the Security tab of this repository.
Include the affected version, reproduction steps, impact, and any suggested
mitigation. Reports will be acknowledged as soon as reasonably possible.

DevNav does not require credentials and performs no network requests at runtime.
The installer downloads release assets exclusively from this GitHub repository
and verifies their published SHA-256 checksum before installation.
