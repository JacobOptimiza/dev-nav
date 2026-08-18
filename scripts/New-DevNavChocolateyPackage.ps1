[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$')][string] $Version,
    [Parameter(Mandatory)][ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })][string] $ReleaseManifest,
    [Parameter(Mandatory)][string] $OutputDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$templateRoot = Join-Path $PSScriptRoot '..\packaging\chocolatey'
$manifest = Get-Content -LiteralPath $ReleaseManifest -Raw | ConvertFrom-Json
$baseUrl = "https://github.com/JacobOptimiza/dev-nav/releases/download/v$Version"
$artifacts = $manifest.artifacts
$assets = @{}
foreach ($architecture in @('x64', 'arm64')) {
    $suffix = if ($architecture -eq 'x64') { 'x86_64' } else { 'aarch64' }
    $binary = $artifacts."binary-$architecture"
    if ($null -eq $binary) { throw "Release manifest has no binary-$architecture artifact." }
    $assets[$architecture] = @{
        dev = @{ url = "$baseUrl/dev-windows-$suffix.exe"; sha256 = [string]$binary.sha256 }
        module = @{ url = "$baseUrl/DevNav.psm1"; sha256 = [string]$artifacts.module.sha256 }
        manifest = @{ url = "$baseUrl/DevNav.psd1"; sha256 = [string]$artifacts.'module-manifest'.sha256 }
    }
}

function Assert-ReleaseUrl([string]$url, [string]$expectedAsset) {
    $prefix = "https://github.com/JacobOptimiza/dev-nav/releases/download/v$Version/"
    if ($url -ne "$prefix$expectedAsset") { throw "Unexpected release URL for ${expectedAsset}: $url" }
}
Assert-ReleaseUrl $assets.x64.dev.url 'dev-windows-x86_64.exe'
Assert-ReleaseUrl $assets.arm64.dev.url 'dev-windows-aarch64.exe'
Assert-ReleaseUrl $assets.x64.module.url 'DevNav.psm1'
Assert-ReleaseUrl $assets.x64.manifest.url 'DevNav.psd1'
foreach ($architecture in @('x64', 'arm64')) {
    foreach ($name in @('dev', 'module', 'manifest')) {
        if ($assets[$architecture][$name].sha256 -notmatch '^[A-Fa-f0-9]{64}$') { throw "Invalid SHA-256 for $architecture/$name." }
    }
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $templateRoot 'devnav.nuspec') -Destination $OutputDirectory -Force
Copy-Item -LiteralPath (Join-Path $templateRoot 'tools') -Destination $OutputDirectory -Recurse -Force
$nuspec = Join-Path $OutputDirectory 'devnav.nuspec'
(Get-Content -LiteralPath $nuspec -Raw).Replace('__VERSION__', $Version) | Set-Content -LiteralPath $nuspec -Encoding utf8NoBOM
$install = Join-Path $OutputDirectory 'tools\chocolateyInstall.ps1'
$text = Get-Content -LiteralPath $install -Raw
$replacements = @{
    '__X64_DEV_URL__' = $assets.x64.dev.url; '__X64_DEV_SHA256__' = $assets.x64.dev.sha256
    '__ARM64_DEV_URL__' = $assets.arm64.dev.url; '__ARM64_DEV_SHA256__' = $assets.arm64.dev.sha256
    '__MODULE_URL__' = $assets.x64.module.url; '__MODULE_SHA256__' = $assets.x64.module.sha256
    '__MANIFEST_URL__' = $assets.x64.manifest.url; '__MANIFEST_SHA256__' = $assets.x64.manifest.sha256
}
foreach ($replacement in $replacements.GetEnumerator()) { $text = $text.Replace($replacement.Key, $replacement.Value) }
$text | Set-Content -LiteralPath $install -Encoding utf8NoBOM
Write-Output $OutputDirectory
