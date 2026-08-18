$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'DevNavChocolatey.ps1')
Remove-DevNavMachineModulePath -PackageTools (Join-Path $env:ChocolateyPackageFolder 'tools')
