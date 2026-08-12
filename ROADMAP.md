# Roadmap

DevNav currently distributes signed-by-checksum release assets through GitHub
and installs them with the PowerShell bootstrap script. The roadmap below keeps
future distribution work visible without promising a package before it has been
tested end to end.

## WinGet distribution

Goal: support a reliable, silent, per-user installation with:

- [x] Build a real Windows installer for x64.
- [x] Build a real Windows installer for ARM64.
- [x] Install `dev.exe` and `DevNav.psm1`.
- [x] Add a marker-based PowerShell profile integration that can be removed safely.
- [x] Support silent install, upgrade, repair and clean uninstall.
- [ ] Preserve `%LOCALAPPDATA%\DevNav\config.tsv` during upgrades and uninstall.
- [ ] Test fresh install, upgrade and uninstall in Windows Sandbox.
- [ ] Generate and validate WinGet manifests with pinned version URLs and SHA-256.
- [ ] Submit `JacobOptimiza.DevNav` to `microsoft/winget-pkgs`.
- [ ] Automate future WinGet update submissions from GitHub Actions.

The release pipeline now builds the x64 and ARM64 installers and generates the
manifests. WinGet remains unavailable until the installers have passed Sandbox
install/upgrade/uninstall validation and the first manifests have been accepted
in `microsoft/winget-pkgs`.
Until then, use the documented PowerShell installer.

## Distribution requirements

WinGet manifests will reference immutable release URLs such as
`/releases/download/vX.Y.Z/DevNavSetup-x64.exe`, never `/latest/download/`. The
installer must be non-interactive when invoked by WinGet and must return reliable
exit codes. The existing PowerShell installer remains available for manual
installation and source builds.
