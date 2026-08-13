# WinGet manifests

The release workflow generates immutable manifests for each tagged release after
the x64 and ARM64 Inno Setup installers have been built and checksummed. Download
the generated `winget-manifests-<version>.zip` release asset and validate it with:

```powershell
winget validate .\manifests\j\JacobOptimiza\DevNav\<version>
```

The committed `0.9.3` manifests are historical seed/reference fixtures for the
first submission. They are not the current release and should not be treated as
the permanent procedure.

Submissions are opened against `microsoft/winget-pkgs`. Automation of future
WinGet updates is intentionally deferred until the package has been accepted
and a real catalog installation has been verified.
Never replace the versioned URLs in a manifest with `/latest/download/` URLs.

## Submit a version

In the Microsoft repository, manifests must be placed under the publisher-prefix
directory `manifests/j/JacobOptimiza/DevNav/<version>/`. From a fork, validate,
commit and open a pull request using the desired version:

```powershell
winget validate .\manifests\j\JacobOptimiza\DevNav\<version>
git checkout -b JacobOptimiza-DevNav-<version>
git add manifests\j\JacobOptimiza\DevNav\<version>
git commit -m "Update package: JacobOptimiza.DevNav version <version>"
git push -u origin JacobOptimiza-DevNav-<version>
gh pr create --repo microsoft/winget-pkgs --base master `
  --head JacobOptimiza:JacobOptimiza-DevNav-<version>
```

The GitHub token used for this step must be allowed to create a fork and pull
request. Never place that token in the repository or in a script.
