Set-StrictMode -Version Latest

$script:DevNavRepository = 'JacobOptimiza/dev-nav'

function Get-DevExecutable {
    $installedExecutable = Join-Path $PSScriptRoot 'dev.exe'
    $developmentExecutable = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\target\release\dev.exe'))
    $executable = if (Test-Path -LiteralPath $installedExecutable -PathType Leaf) {
        $installedExecutable
    }
    else {
        $developmentExecutable
    }
    if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) {
        throw 'No se encuentra dev.exe. Ejecuta install.ps1 desde la raíz de DevNav.'
    }
    return $executable
}

function Update-DevNavigator {
    [CmdletBinding()]
    param()

    $ErrorActionPreference = 'Stop'
    $executable = Get-DevExecutable
    $versionOutput = (& $executable --version | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $versionOutput -notmatch '^dev-nav\s+(?<Version>\d+\.\d+\.\d+)$') {
        throw 'No se pudo determinar la versión instalada de DevNav.'
    }

    $currentText = $Matches.Version
    $releaseUri = "https://api.github.com/repos/$script:DevNavRepository/releases/latest"
    Write-Host "Versión instalada: v$currentText"
    Write-Host 'Comprobando la última versión publicada...'
    $release = Invoke-RestMethod -Uri $releaseUri -Headers @{
        Accept       = 'application/vnd.github+json'
        'User-Agent' = 'DevNav-Updater'
    }
    $latestText = ([string]$release.tag_name).TrimStart('v')
    $currentVersion = [version]$currentText
    $latestVersion = [version]$latestText
    Write-Host "Última publicada: v$latestText"

    if ($currentVersion -ge $latestVersion) {
        if ($currentVersion -eq $latestVersion) {
            Write-Host "Ya tienes la última versión (v$currentText). No hace falta actualizar." -ForegroundColor Green
        }
        else {
            Write-Host 'La versión instalada es más reciente que la última release publicada; no se modificó nada.' -ForegroundColor Yellow
        }
        return
    }

    $architecture = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
    $executableAsset = switch ($architecture) {
        'X64' { 'dev-windows-x86_64.exe' }
        'Arm64' { 'dev-windows-aarch64.exe' }
        default { throw "Arquitectura Windows no soportada: $architecture" }
    }
    $requiredAssets = @($executableAsset, 'DevNav.psm1', 'SHA256SUMS.txt')
    $releaseAssets = @($release.assets)
    $downloads = @{}
    foreach ($assetName in $requiredAssets) {
        $asset = $releaseAssets | Where-Object { $_.name -eq $assetName } | Select-Object -First 1
        if (-not $asset) { throw "La release v$latestText no contiene $assetName." }
        $downloads[$assetName] = $asset.browser_download_url
    }

    $temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("devnav-update-{0}" -f [guid]::NewGuid().ToString('N'))
    $installRoot = Join-Path $env:LOCALAPPDATA 'Programs\DevNav'
    $installedExecutable = Join-Path $installRoot 'dev.exe'
    $installedModule = Join-Path $installRoot 'DevNav.psm1'
    $stagedExecutable = $null
    $stagedModule = $null
    New-Item -ItemType Directory -Path $temporaryRoot, $installRoot -Force | Out-Null

    try {
        Write-Host "Descargando DevNav v$latestText..."
        foreach ($assetName in $requiredAssets) {
            Invoke-WebRequest -Uri $downloads[$assetName] -OutFile (Join-Path $temporaryRoot $assetName)
        }

        $checksumLines = Get-Content -LiteralPath (Join-Path $temporaryRoot 'SHA256SUMS.txt')
        foreach ($assetName in @($executableAsset, 'DevNav.psm1')) {
            $checksumLine = $checksumLines | Where-Object { $_ -match "\s$([regex]::Escape($assetName))$" } | Select-Object -First 1
            if (-not $checksumLine) { throw "No se encontró el checksum publicado para $assetName." }
            $expectedHash = (($checksumLine -split '\s+')[0]).ToUpperInvariant()
            $downloadedFile = Join-Path $temporaryRoot $assetName
            $actualHash = (Get-FileHash -LiteralPath $downloadedFile -Algorithm SHA256).Hash
            if ($actualHash -ne $expectedHash) {
                throw "El checksum de $assetName no coincide; se cancela la actualización."
            }
        }

        $stagedExecutable = Join-Path $installRoot ("dev-{0}.new" -f [guid]::NewGuid().ToString('N'))
        $stagedModule = Join-Path $installRoot ("DevNav-{0}.new" -f [guid]::NewGuid().ToString('N'))
        Copy-Item -LiteralPath (Join-Path $temporaryRoot $executableAsset) -Destination $stagedExecutable
        Copy-Item -LiteralPath (Join-Path $temporaryRoot 'DevNav.psm1') -Destination $stagedModule
        Move-Item -LiteralPath $stagedExecutable -Destination $installedExecutable -Force
        Move-Item -LiteralPath $stagedModule -Destination $installedModule -Force
        Import-Module $installedModule -Force
        Write-Host "DevNav actualizado correctamente: v$currentText → v$latestText." -ForegroundColor Green
    }
    finally {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
        if ($stagedExecutable) { Remove-Item -LiteralPath $stagedExecutable -Force -ErrorAction SilentlyContinue }
        if ($stagedModule) { Remove-Item -LiteralPath $stagedModule -Force -ErrorAction SilentlyContinue }
    }
}

function Invoke-DevNavigator {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]] $Command = @()
    )

    if ($Command.Count -eq 1 -and $Command[0] -eq 'update') {
        Update-DevNavigator
        return
    }
    $executable = Get-DevExecutable

    $resultFile = Join-Path ([System.IO.Path]::GetTempPath()) ("devnav-{0}.result" -f [guid]::NewGuid().ToString('N'))
    try {
        & $executable --root (Get-DevRoot) --result $resultFile
        if ($LASTEXITCODE -ne 0) { return }
        if (-not (Test-Path -LiteralPath $resultFile)) { return }

        $parts = [System.IO.File]::ReadAllText($resultFile).Split([char]0)
        if ($parts.Count -lt 2) { throw 'DevNav devolvió un resultado no válido.' }
        $kind, $directory = $parts[0], $parts[1]
        if ($kind -eq 'update') {
            Update-DevNavigator
            return
        }
        Set-Location -LiteralPath $directory

        $commandText = if ($Command.Count -gt 0) { $Command -join ' ' } elseif ($parts.Count -gt 2) { $parts[2] } else { '' }
        if ($kind -eq 'exec' -or $Command.Count -gt 0) {
            if (-not [string]::IsNullOrWhiteSpace($commandText)) {
                Invoke-Expression $commandText
            }
        }
    }
    finally {
        Remove-Item -LiteralPath $resultFile -Force -ErrorAction SilentlyContinue
    }
}

function Get-DevRoot {
    $configPath = Join-Path $env:LOCALAPPDATA 'DevNav\config.tsv'
    if (Test-Path -LiteralPath $configPath -PathType Leaf) {
        $rootLine = Get-Content -LiteralPath $configPath | Where-Object { $_.StartsWith("root`t") } | Select-Object -First 1
        if ($rootLine) {
            $encodedRoot = $rootLine.Substring(5)
            return $encodedRoot.Replace('%0A', "`n").Replace('%09', "`t").Replace('%25', '%')
        }
    }
    if ($env:DEV_HOME) { return $env:DEV_HOME }
    return $HOME
}

function Set-DevRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Path
    )

    $resolvedRoot = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    if (-not (Test-Path -LiteralPath $resolvedRoot -PathType Container)) {
        throw "La ruta no es una carpeta: $resolvedRoot"
    }
    $encodedRoot = $resolvedRoot.Replace('%', '%25').Replace("`t", '%09').Replace("`n", '%0A')
    $configPath = Join-Path $env:LOCALAPPDATA 'DevNav\config.tsv'
    $configDirectory = Split-Path -Parent $configPath
    New-Item -ItemType Directory -Path $configDirectory -Force | Out-Null
    $existingLines = if (Test-Path -LiteralPath $configPath) {
        @(Get-Content -LiteralPath $configPath | Where-Object { -not $_.StartsWith("root`t") })
    }
    else {
        @()
    }
    (@("root`t$encodedRoot") + $existingLines) | Set-Content -LiteralPath $configPath -Encoding utf8NoBOM
    Write-Host "Ruta de inicio guardada: $resolvedRoot" -ForegroundColor Green
}

Set-Alias -Name dev -Value Invoke-DevNavigator -Scope Global
Export-ModuleMember -Function Invoke-DevNavigator, Update-DevNavigator, Get-DevRoot, Set-DevRoot -Alias dev
