# WinGet manifests

The release workflow generates immutable manifests for each tagged release after
the x64 and ARM64 Inno Setup installers have been built and checksummed. Download
the generated `winget-manifests-<version>.zip` release asset and validate it with:

```powershell
winget validate .\manifests
```

The first submission must be opened against `microsoft/winget-pkgs`. Future
releases can use `wingetcreate update` from a protected GitHub Actions secret.
Never replace the versioned URLs in a manifest with `/latest/download/` URLs.
