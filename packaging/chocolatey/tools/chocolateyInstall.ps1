$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'DevNavChocolatey.ps1')

$architecture = Get-DevNavNativeArchitecture
$assets = @{
    x64 = @{
        dev = @{ url = '__X64_DEV_URL__'; sha256 = '__X64_DEV_SHA256__' }
        module = @{ url = '__MODULE_URL__'; sha256 = '__MODULE_SHA256__' }
        manifest = @{ url = '__MANIFEST_URL__'; sha256 = '__MANIFEST_SHA256__' }
    }
    arm64 = @{
        dev = @{ url = '__ARM64_DEV_URL__'; sha256 = '__ARM64_DEV_SHA256__' }
        module = @{ url = '__MODULE_URL__'; sha256 = '__MODULE_SHA256__' }
        manifest = @{ url = '__MANIFEST_URL__'; sha256 = '__MANIFEST_SHA256__' }
    }
}
$selected = Get-DevNavAssetSet -Architecture $architecture -Assets $assets
$packageRoot = Get-ChocolateyPath -PathType 'PackagePath'
$packageTools = Join-Path $packageRoot 'tools'
$moduleRoot = Join-Path $packageTools 'DevNav'
New-Item -ItemType Directory -Path $moduleRoot -Force | Out-Null

if ($architecture -eq 'x64') {
    Get-ChocolateyWebFile -PackageName 'devnav' -FileFullPath (Join-Path $moduleRoot 'dev.exe') -Url '__X64_DEV_URL__' -Checksum '__X64_DEV_SHA256__' -ChecksumType 'sha256'
} elseif ($architecture -eq 'arm64') {
    Get-ChocolateyWebFile -PackageName 'devnav' -FileFullPath (Join-Path $moduleRoot 'dev.exe') -Url '__ARM64_DEV_URL__' -Checksum '__ARM64_DEV_SHA256__' -ChecksumType 'sha256'
}
Get-ChocolateyWebFile -PackageName 'devnav' -FileFullPath (Join-Path $moduleRoot 'DevNav.psm1') -Url '__MODULE_URL__' -Checksum '__MODULE_SHA256__' -ChecksumType 'sha256'
Get-ChocolateyWebFile -PackageName 'devnav' -FileFullPath (Join-Path $moduleRoot 'DevNav.psd1') -Url '__MANIFEST_URL__' -Checksum '__MANIFEST_SHA256__' -ChecksumType 'sha256'
Assert-DevNavSha256 -Path (Join-Path $moduleRoot 'dev.exe') -Expected $selected.dev.sha256
Assert-DevNavSha256 -Path (Join-Path $moduleRoot 'DevNav.psm1') -Expected $selected.module.sha256
Assert-DevNavSha256 -Path (Join-Path $moduleRoot 'DevNav.psd1') -Expected $selected.manifest.sha256
New-Item -ItemType File -Path (Join-Path $moduleRoot '.devnav-managed-by-chocolatey') -Force | Out-Null
Add-DevNavMachineModulePath -PackageTools $packageTools
