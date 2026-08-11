[CmdletBinding()]
param(
    [switch] $BuildFromSource,
    [bool] $ModifyProfile = $true
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw 'DevNav requiere PowerShell 7 o posterior.'
}

$projectRoot = $PSScriptRoot
$installRoot = Join-Path $env:LOCALAPPDATA 'Programs\DevNav'
$installedExecutable = Join-Path $installRoot 'dev.exe'
$installedModule = Join-Path $installRoot 'DevNav.psm1'
$sourceModule = Join-Path $projectRoot 'powershell\DevNav.psm1'
$temporaryDownload = Join-Path ([System.IO.Path]::GetTempPath()) ("devnav-{0}.exe" -f [guid]::NewGuid().ToString('N'))
$temporaryChecksums = Join-Path ([System.IO.Path]::GetTempPath()) ("devnav-{0}.sha256" -f [guid]::NewGuid().ToString('N'))

New-Item -ItemType Directory -Path $installRoot -Force | Out-Null

try {
    if ($BuildFromSource) {
        $cargoCommand = Get-Command cargo -ErrorAction SilentlyContinue
        $cargoExecutable = if ($cargoCommand) {
            $cargoCommand.Source
        }
        else {
            Join-Path $HOME '.cargo\bin\cargo.exe'
        }
        if (-not (Test-Path -LiteralPath $cargoExecutable -PathType Leaf)) {
            throw 'Para -BuildFromSource instala Rust y MSVC Build Tools primero: https://rustup.rs/'
        }
        Push-Location $projectRoot
        try {
            & $cargoExecutable test
            if ($LASTEXITCODE -ne 0) { throw 'cargo test ha fallado.' }
            & $cargoExecutable build --release
            if ($LASTEXITCODE -ne 0) { throw 'cargo build --release ha fallado.' }
        }
        finally {
            Pop-Location
        }
        $sourceExecutable = Join-Path $projectRoot 'target\release\dev.exe'
    }
    else {
        $architecture = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
        $asset = switch ($architecture) {
            'X64' { 'dev-windows-x86_64.exe' }
            'Arm64' { 'dev-windows-aarch64.exe' }
            default { throw "Arquitectura Windows no soportada: $architecture" }
        }
        $downloadUrl = "https://github.com/JacobOptimiza/dev-nav/releases/latest/download/$asset"
        Write-Host "Descargando $asset..."
        Invoke-WebRequest -Uri $downloadUrl -OutFile $temporaryDownload
        Invoke-WebRequest -Uri 'https://github.com/JacobOptimiza/dev-nav/releases/latest/download/SHA256SUMS.txt' -OutFile $temporaryChecksums
        $checksumLine = Get-Content -LiteralPath $temporaryChecksums | Where-Object { $_ -match "\s$([regex]::Escape($asset))$" } | Select-Object -First 1
        if (-not $checksumLine) { throw "No se encontró el checksum publicado para $asset." }
        $expectedHash = ($checksumLine -split '\s+')[0]
        $actualHash = (Get-FileHash -LiteralPath $temporaryDownload -Algorithm SHA256).Hash
        if ($actualHash -ne $expectedHash) {
            throw "El checksum de $asset no coincide; se cancela la instalación."
        }
        $sourceExecutable = $temporaryDownload
    }

    Copy-Item -LiteralPath $sourceExecutable -Destination $installedExecutable -Force
    Copy-Item -LiteralPath $sourceModule -Destination $installedModule -Force
}
finally {
    Remove-Item -LiteralPath $temporaryDownload -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $temporaryChecksums -Force -ErrorAction SilentlyContinue
}

Import-Module $installedModule -Force

if ($ModifyProfile) {
    $profileDirectory = Split-Path -Parent $PROFILE
    New-Item -ItemType Directory -Path $profileDirectory -Force | Out-Null
    $importLine = "Import-Module '$($installedModule.Replace("'", "''"))'"
    $profileContents = if (Test-Path -LiteralPath $PROFILE) {
        Get-Content -LiteralPath $PROFILE -Raw
    }
    else {
        ''
    }
    if ($profileContents -notlike "*$importLine*") {
        Add-Content -LiteralPath $PROFILE -Value "`n$importLine"
    }
}

Write-Host "DevNav instalado en $installRoot" -ForegroundColor Green
Write-Host 'Abre una PowerShell 7 nueva y ejecuta: dev'
