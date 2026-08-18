# DevNav Chocolatey packaging source

This directory contains the source for a future Chocolatey package. It is not
published and is deliberately not tied to v0.14.0: the package must be
materialized from the release manifest of a future release that includes this
integration.

The package is machine-owned and installs the official, versioned release
assets into:

```text
%ChocolateyInstall%\lib\devnav\tools\DevNav\
  dev.exe
  DevNav.psm1
  DevNav.psd1
  .devnav-managed-by-chocolatey
```

It registers `%ChocolateyInstall%\lib\devnav\tools` in the machine
`PSModulePath`, without changing any PowerShell profile. The module keeps each
user's configuration in that user's `%LOCALAPPDATA%\DevNav` directory.

## Materialize and pack

The release workflow's `release-manifest.json` is the input source of truth.
The materializer constructs the immutable GitHub Release URLs and injects the
published SHA-256 values; it rejects other URLs, missing architectures and
invalid hashes.

```powershell
./scripts/New-DevNavChocolateyPackage.ps1 `
  -Version 0.15.0 `
  -ReleaseManifest .\release-manifest.json `
  -OutputDirectory $env:TEMP\devnav-chocolatey
choco pack $env:TEMP\devnav-chocolatey\devnav.nuspec
```

Do not add compiled binaries to this repository and do not run `choco push`
from this project without a separate release decision.

## Architecture and ownership

Native architecture is detected from `PROCESSOR_ARCHITECTURE` and
`PROCESSOR_ARCHITEW6432`, not Chocolatey's processor-width helpers. Native
x64 and ARM64 select their matching official binary. Real x86 is rejected,
and `--forcex86` cannot select an incorrect asset.

Installation, upgrade and uninstall are expected to be idempotent. The
Chocolatey marker prevents DevNav self-updates; `dev update` only tells the
user to run `choco upgrade devnav`. The package never runs DevNav as
administrator to initialize user configuration.

## Community verifier limitation

DevNav supports Windows 10/11 on x64 and ARM64. It does not support x86 and
does not declare Windows Server 2019. The Chocolatey Community verifier runs
on Windows Server 2019 and also exercises `forcex86`. Publishing will
therefore require a verifier exemption request; this source does not broaden
DevNav's supported platforms and does not request the exemption yet.
