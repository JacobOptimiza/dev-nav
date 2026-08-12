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

## Submit the first version

In the Microsoft repository, manifests must be placed under the publisher-prefix
directory `manifests/j/JacobOptimiza/DevNav/0.9.3/`. The files in this folder
already use that layout. From a fork, validate, commit and open a pull request:

```powershell
winget validate .\manifests\j\JacobOptimiza\DevNav\0.9.3
git checkout -b JacobOptimiza-DevNav-0.9.3
git add manifests\j\JacobOptimiza\DevNav\0.9.3
git commit -m "New package: JacobOptimiza.DevNav version 0.9.3"
git push -u origin JacobOptimiza-DevNav-0.9.3
gh pr create --repo microsoft/winget-pkgs --base master `
  --head JacobOptimiza:JacobOptimiza-DevNav-0.9.3
```

The GitHub token used for this step must be allowed to create a fork and pull
request. Never place that token in the repository or in a script.
