# Roadmap

DevNav currently distributes signed-by-checksum release assets through GitHub
and installs them with the PowerShell bootstrap script. The roadmap below keeps
future distribution work visible without promising a package before it has been
tested end to end.

## WinGet distribution

Goal: support a reliable, silent, per-user installation with:

- [ ] Build a real Windows installer for x64.
- [ ] Build a real Windows installer for ARM64.
- [ ] Install `dev.exe` and `DevNav.psm1`.
- [ ] Add a marker-based PowerShell profile integration that can be removed safely.
- [ ] Support silent install, upgrade, repair and clean uninstall.
- [ ] Preserve `%LOCALAPPDATA%\DevNav\config.tsv` during upgrades and uninstall.
- [ ] Test fresh install, upgrade and uninstall in Windows Sandbox.
- [ ] Generate and validate WinGet manifests with pinned version URLs and SHA-256.
- [ ] Submit `JacobOptimiza.DevNav` to `microsoft/winget-pkgs`.
- [ ] Automate future WinGet update submissions from GitHub Actions.

Until these checks pass, do not use `winget install JacobOptimiza.DevNav`: the
package is not published yet. Use the documented PowerShell installer instead.

## Distribution requirements

WinGet manifests will reference immutable release URLs such as
`/releases/download/vX.Y.Z/DevNavSetup-x64.exe`, never `/latest/download/`. The
installer must be non-interactive when invoked by WinGet and must return reliable
exit codes. The existing PowerShell installer remains available for manual
installation and source builds.
