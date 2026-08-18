$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'DevNavChocolatey.ps1')
$packageRoot = Get-ChocolateyPath -PathType 'PackagePath'
Remove-DevNavMachineModulePath -PackageTools (Join-Path $packageRoot 'tools')
