# Roadmap

DevNav is distributed from GitHub and through the public npm bootstrap package.
Release payloads are checksum-verified with SHA-256; checksums verify integrity
and are not digital signatures.

## Distribution status

- [x] GitHub releases with x64 and ARM64 application binaries.
- [x] Per-user Windows installers and PowerShell integration.
- [x] Publish the v0.10.0 multichannel release payload.
- [x] Publish `@jacoboptimiza/devnav` as a public npm bootstrap package.
- [x] Verify Bun, npm, pnpm and Yarn bootstrap commands from the public registry.
- [x] Configure npm Trusted Publishing for future releases.
- [x] Publish portable x64 and ARM64 Scoop artifacts in the GitHub Release.
- [ ] Create and validate the public `JacobOptimiza/scoop-bucket` bootstrap.
- [x] Generate WinGet manifests with immutable versioned URLs and SHA-256.
- [x] Submit the initial `JacobOptimiza.DevNav` manifests to
  `microsoft/winget-pkgs`.
- [ ] Microsoft acceptance and public WinGet catalog propagation.
- [ ] Validate fresh install, upgrade and uninstall in Windows Sandbox.
- [ ] Automate future WinGet submissions after a real catalog installation has
  been verified.

The roadmap describes status only. Operational instructions live in the
packaging documentation and workflows.
