# Roadmap

DevNav is currently distributed from GitHub through the PowerShell installer
and release installers. Release payloads are checksum-verified with SHA-256;
checksums verify integrity and are not digital signatures.

## Distribution status

- [x] GitHub releases with x64 and ARM64 application binaries.
- [x] Per-user Windows installers and PowerShell integration.
- [x] npm and Scoop packaging implemented from the canonical release payload.
- [ ] Publish the first multichannel release after v0.9.7.
- [ ] Make npm and Scoop installation channels available to users.
- [x] Generate WinGet manifests with immutable versioned URLs and SHA-256.
- [x] Submit the initial `JacobOptimiza.DevNav` manifests to
  `microsoft/winget-pkgs`.
- [ ] Microsoft acceptance and public WinGet catalog propagation.
- [ ] Validate fresh install, upgrade and uninstall in Windows Sandbox.
- [ ] Automate future WinGet submissions after a real catalog installation has
  been verified.

The roadmap describes status only. Operational instructions live in the
packaging documentation and workflows.
