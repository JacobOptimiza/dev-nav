# WinGet manifests

The release workflow generates immutable manifests for each tagged release after
the x64 and ARM64 Inno Setup installers have been built and checksummed. Download
the generated `winget-manifests-<version>.zip` release asset and validate it with:

```powershell
winget validate .\manifests\j\JacobOptimiza\DevNav\<version>
```

The current `0.9.3` manifests are also committed in this directory so they can
be copied directly into a submission branch for `microsoft/winget-pkgs`.

The first submission must be opened against `microsoft/winget-pkgs`. Future
releases can use `wingetcreate update` from a protected GitHub Actions secret.
Never replace the versioned URLs in a manifest with `/latest/download/` URLs.
