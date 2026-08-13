Set-StrictMode -Version Latest

$script:DevNavRepository = 'JacobOptimiza/dev-nav'
$script:DevNavRestartRequired = $false
$script:DevNavUpdateCompleted = $false

function Get-DevConfigPath {
    return (Join-Path $env:LOCALAPPDATA 'DevNav\config.tsv')
}

function Get-DevConfigValue {
    param([Parameter(Mandatory)][string] $Name)

    $configPath = Get-DevConfigPath
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) { return $null }
    $prefix = "$Name`t"
    $line = Get-Content -LiteralPath $configPath | Where-Object { $_.StartsWith($prefix) } | Select-Object -First 1
    if (-not $line) { return $null }
    return $line.Substring($prefix.Length)
}

function Set-DevConfigValue {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)][string] $Value
    )

    $configPath = Get-DevConfigPath
    if (-not $PSCmdlet.ShouldProcess($configPath, "Set configuration value '$Name'")) { return }
    $configDirectory = Split-Path -Parent $configPath
    New-Item -ItemType Directory -Path $configDirectory -Force | Out-Null
    $prefix = "$Name`t"
    $existingLines = if (Test-Path -LiteralPath $configPath) {
        @(Get-Content -LiteralPath $configPath | Where-Object { -not $_.StartsWith($prefix) })
    }
    else {
        @()
    }
    (@("$prefix$Value") + $existingLines) | Set-Content -LiteralPath $configPath -Encoding utf8NoBOM
}

function Set-DevUpdateCheck {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param([Parameter(Mandatory, Position = 0)][bool] $Enabled)

    if (-not $PSCmdlet.ShouldProcess('DevNav local configuration', 'Change startup update checks')) { return }
    Set-DevConfigValue -Name 'check_updates' -Value $Enabled.ToString().ToLowerInvariant()
    $state = if ($Enabled) { 'activada' } else { 'desactivada' }
    Write-Host "Comprobación de actualizaciones al iniciar: $state." -ForegroundColor Green
}

function Get-DevInstalledVersion {
    $versionOutput = (& (Get-DevExecutable) --version | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $versionOutput -notmatch '^dev-nav\s+(?<Version>\d+\.\d+\.\d+)$') {
        throw 'No se pudo determinar la versión instalada de DevNav.'
    }
    return [version]$Matches.Version
}

function Get-DevLatestRelease {
    param([ValidateRange(1, 120)][int] $TimeoutSeconds = 30)

    return Invoke-RestMethod -Uri "https://api.github.com/repos/$script:DevNavRepository/releases/latest" -TimeoutSec $TimeoutSeconds -Headers @{
        Accept       = 'application/vnd.github+json'
        'User-Agent' = 'DevNav-Updater'
    }
}

function Invoke-DevDownload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Uri,
        [Parameter(Mandatory)][string] $OutFile,
        [ValidateRange(1, 10)][int] $Attempts = 5
    )

    $lastError = $null
    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        try {
            $parameters = @{
                Uri         = $Uri
                OutFile     = $OutFile
                ErrorAction = 'Stop'
            }
            if ($attempt -gt 1 -and (Test-Path -LiteralPath $OutFile -PathType Leaf)) {
                $parameters.Resume = $true
            }
            Invoke-WebRequest @parameters
            return
        }
        catch {
            $lastError = $_
            if ($attempt -lt $Attempts) {
                Start-Sleep -Seconds ([Math]::Min($attempt * 2, 10))
            }
        }
    }
    throw "No se pudo descargar '$Uri' tras $Attempts intentos: $($lastError.Exception.Message)"
}

function Initialize-DevUpdateCheckPreference {
    $saved = Get-DevConfigValue -Name 'check_updates'
    if ($null -ne $saved) { return $saved -eq 'true' }
    if ([Console]::IsInputRedirected) { return $false }

    Write-Host 'DevNav puede comprobar en GitHub si existe una versión nueva al iniciar.' -ForegroundColor Cyan
    Write-Host 'Sólo comprueba: nunca descarga ni instala sin tu confirmación explícita.'
    $answer = (Read-Host '¿Mantener esta comprobación activada? [S/n]').Trim()
    $enabled = $answer -notmatch '^(?i:n|no)$'
    Set-DevConfigValue -Name 'check_updates' -Value $enabled.ToString().ToLowerInvariant()
    return $enabled
}

function Test-DevManagedInstallation {
    # Package managers such as Scoop own the files they install; DevNav must not
    # self-update underneath them. Managed layouts carry a marker file next to
    # this module.
    return (Test-Path -LiteralPath (Join-Path $PSScriptRoot '.devnav-managed-by-scoop') -PathType Leaf)
}

function Invoke-DevStartupUpdateCheck {
    if ([Console]::IsInputRedirected) { return }
    if (Test-DevManagedInstallation) { return }
    if (-not (Initialize-DevUpdateCheckPreference)) { return }

    try {
        $installedVersion = Get-DevInstalledVersion
        $release = Get-DevLatestRelease -TimeoutSeconds 5
        $latestText = ([string]$release.tag_name).TrimStart('v')
        $latestVersion = [version]$latestText
    }
    catch {
        # The optional startup check must never block normal navigation.
        return
    }

    if ($latestVersion -le $installedVersion) { return }
    Write-Host "Nueva versión disponible: v$installedVersion → v$latestVersion" -ForegroundColor Yellow
    $answer = (Read-Host '¿Quieres actualizar ahora? [s/N]').Trim()
    if ($answer -match '^(?i:s|si|sí|y|yes)$') {
        # An explicitly requested update reports failures instead of hiding them.
        Update-DevNavigator
    }
}

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

function Invoke-DevCli {
    # Thin, mockable wrapper around the dev.exe binary used by the shortcut
    # configuration commands. Returns the process exit code.
    param([Parameter(Mandatory)][string[]] $Arguments)
    $executable = Get-DevExecutable
    & $executable @Arguments
    return $LASTEXITCODE
}

function Set-DevShortcut {
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Bind')]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateRange(1, 9)]
        [int] $Index,

        [Parameter(Mandatory, Position = 1, ParameterSetName = 'Bind')]
        [string] $Command,

        [Parameter(Position = 2, ParameterSetName = 'Bind')]
        [string] $Alias,

        [Parameter(ParameterSetName = 'Clear')]
        [switch] $Clear
    )

    if ($Clear) {
        if (-not $PSCmdlet.ShouldProcess("atajo $Index", 'Eliminar')) { return }
        $exitCode = Invoke-DevCli -Arguments @('--clear-shortcut', $Index)
        if ($exitCode -ne 0) { throw "No se pudo eliminar el atajo $Index (dev.exe salió con $exitCode)." }
        Write-Host "Atajo $Index eliminado." -ForegroundColor Green
        return
    }

    if ([string]::IsNullOrWhiteSpace($Command)) {
        throw 'Debes indicar el comando del atajo, o usar -Clear para eliminarlo.'
    }
    if (-not $PSCmdlet.ShouldProcess("atajo $Index", "Vincular '$Command'")) { return }
    # The command is stored verbatim and only evaluated by the shell when the
    # shortcut is invoked; never during configuration.
    $arguments = @('--set-shortcut', [string]$Index, $Command)
    if (-not [string]::IsNullOrWhiteSpace($Alias)) {
        $arguments += @('--alias', $Alias)
    }
    $exitCode = Invoke-DevCli -Arguments $arguments
    if ($exitCode -ne 0) { throw "No se pudo guardar el atajo $Index (dev.exe salió con $exitCode)." }
    $label = if ([string]::IsNullOrWhiteSpace($Alias)) { $Command } else { $Alias }
    Write-Host "Atajo $Index guardado: $label" -ForegroundColor Green
}

function Remove-DevShortcut {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateRange(1, 9)]
        [int] $Index
    )

    Set-DevShortcut -Index $Index -Clear -Confirm:$false
}

function Invoke-DevShortcutCommand {
    # Parses the `dev shortcut <args>` form. Kept separate from
    # Invoke-DevNavigator so the parsing is unit-testable in isolation.
    param([Parameter(Mandatory)][ValidateNotNullOrEmpty()][string[]] $Items)

    switch ($Items.Count) {
        1 { Remove-DevShortcut -Index $Items[0] }
        2 { Set-DevShortcut -Index $Items[0] -Command $Items[1] }
        3 { Set-DevShortcut -Index $Items[0] -Alias $Items[1] -Command $Items[2] }
        default {
            throw "Uso: dev shortcut <1..9> [alias] <comando>`nPara eliminar: dev shortcut <1..9>"
        }
    }
}

function Update-DevNavigator {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    if (Test-DevManagedInstallation) {
        Write-Host 'Esta instalación la gestiona Scoop; DevNav no se actualiza a sí mismo.' -ForegroundColor Yellow
        Write-Host 'Para actualizar, ejecuta: scoop update devnav' -ForegroundColor Cyan
        return
    }
    $ErrorActionPreference = 'Stop'
    if (-not $PSCmdlet.ShouldProcess('DevNav installation', 'Download and install the selected release')) { return }
    $currentVersion = Get-DevInstalledVersion
    $currentText = $currentVersion.ToString()
    Write-Host "Versión instalada: v$currentText"
    Write-Host 'Comprobando la última versión publicada...'
    $release = Get-DevLatestRelease
    $latestText = ([string]$release.tag_name).TrimStart('v')
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
    $moduleChanged = $false
    $backupExecutable = Join-Path $installRoot ("dev-{0}.bak" -f [guid]::NewGuid().ToString('N'))
    $backupModule = Join-Path $installRoot ("DevNav-{0}.bak" -f [guid]::NewGuid().ToString('N'))
    $replacementCommitted = $false
    New-Item -ItemType Directory -Path $temporaryRoot, $installRoot -Force | Out-Null

    try {
        Write-Host "Descargando DevNav v$latestText..."
        foreach ($assetName in $requiredAssets) {
            Invoke-DevDownload -Uri $downloads[$assetName] -OutFile (Join-Path $temporaryRoot $assetName)
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

        $currentModuleHash = if (Test-Path -LiteralPath $installedModule -PathType Leaf) {
            (Get-FileHash -LiteralPath $installedModule -Algorithm SHA256).Hash
        }
        $downloadedModuleHash = (Get-FileHash -LiteralPath (Join-Path $temporaryRoot 'DevNav.psm1') -Algorithm SHA256).Hash
        $moduleChanged = $currentModuleHash -ne $downloadedModuleHash

        $stagedExecutable = Join-Path $installRoot ("dev-{0}.new" -f [guid]::NewGuid().ToString('N'))
        $stagedModule = Join-Path $installRoot ("DevNav-{0}.new" -f [guid]::NewGuid().ToString('N'))
        Copy-Item -LiteralPath (Join-Path $temporaryRoot $executableAsset) -Destination $stagedExecutable
        Copy-Item -LiteralPath (Join-Path $temporaryRoot 'DevNav.psm1') -Destination $stagedModule
        try {
            if (Test-Path -LiteralPath $installedExecutable -PathType Leaf) {
                Copy-Item -LiteralPath $installedExecutable -Destination $backupExecutable -Force
            }
            if (Test-Path -LiteralPath $installedModule -PathType Leaf) {
                Copy-Item -LiteralPath $installedModule -Destination $backupModule -Force
            }
            Remove-Item -LiteralPath $installedExecutable, $installedModule -Force -ErrorAction SilentlyContinue
            Move-Item -LiteralPath $stagedExecutable -Destination $installedExecutable -Force
            Move-Item -LiteralPath $stagedModule -Destination $installedModule -Force
            $versionOutput = (& $installedExecutable --version | Out-String).Trim()
            $expectedVersionOutput = "dev-nav $latestText"
            if ($LASTEXITCODE -ne 0 -or $versionOutput -ne $expectedVersionOutput) {
                throw "El ejecutable actualizado no corresponde a v$latestText."
            }
            $replacementCommitted = $true
        }
        catch {
            Remove-Item -LiteralPath $installedExecutable, $installedModule -Force -ErrorAction SilentlyContinue
            if (Test-Path -LiteralPath $backupExecutable -PathType Leaf) {
                Copy-Item -LiteralPath $backupExecutable -Destination $installedExecutable -Force
            }
            if (Test-Path -LiteralPath $backupModule -PathType Leaf) {
                Copy-Item -LiteralPath $backupModule -Destination $installedModule -Force
            }
            Remove-Item -LiteralPath $backupExecutable, $backupModule -Force -ErrorAction SilentlyContinue
            throw
        }
        Write-Host "DevNav actualizado correctamente: v$currentText → v$latestText." -ForegroundColor Green
        if ($moduleChanged) {
            $script:DevNavRestartRequired = $true
            Write-Warning 'DevNav.psm1 también cambió. Reinicia PowerShell para cargar el módulo actualizado.'
        }
        else {
            Write-Host 'Ejecuta dev de nuevo para continuar.' -ForegroundColor Cyan
        }
        $script:DevNavUpdateCompleted = $true
    }
    finally {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
        if ($stagedExecutable) { Remove-Item -LiteralPath $stagedExecutable -Force -ErrorAction SilentlyContinue }
        if ($stagedModule) { Remove-Item -LiteralPath $stagedModule -Force -ErrorAction SilentlyContinue }
        if ($replacementCommitted) {
            Remove-Item -LiteralPath $backupExecutable, $backupModule -Force -ErrorAction SilentlyContinue
        }
    }
}

function Invoke-DevNavigator {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]] $Command = @()
    )

    if ($Command.Count -eq 1 -and $Command[0] -eq 'update') {
        $script:DevNavUpdateCompleted = $false
        Update-DevNavigator
        return
    }
    if ($Command.Count -ge 1 -and $Command[0] -eq 'shortcut') {
        $items = @($Command | Select-Object -Skip 1)
        if ($items.Count -eq 0) {
            throw "Uso: dev shortcut <1..9> [alias] <comando>`nPara eliminar: dev shortcut <1..9>"
        }
        Invoke-DevShortcutCommand -Items $items
        return
    }
    $script:DevNavUpdateCompleted = $false
    Invoke-DevStartupUpdateCheck
    if ($script:DevNavUpdateCompleted) {
        return
    }
    if ($script:DevNavRestartRequired) {
        Write-Warning 'DevNav se ha actualizado. Reinicia PowerShell para cargar el módulo actualizado.'
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
    $encodedRoot = Get-DevConfigValue -Name 'root'
    if ($null -ne $encodedRoot) {
        return $encodedRoot.Replace('%0A', "`n").Replace('%09', "`t").Replace('%25', '%')
    }
    if ($env:DEV_HOME) { return $env:DEV_HOME }
    return $HOME
}

function Set-DevRoot {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Path
    )

    $resolvedRoot = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    if (-not (Test-Path -LiteralPath $resolvedRoot -PathType Container)) {
        throw "La ruta no es una carpeta: $resolvedRoot"
    }
    if (-not $PSCmdlet.ShouldProcess($resolvedRoot, 'Save as DevNav startup directory')) { return }
    $encodedRoot = $resolvedRoot.Replace('%', '%25').Replace("`t", '%09').Replace("`n", '%0A')
    Set-DevConfigValue -Name 'root' -Value $encodedRoot
    Write-Host "Ruta de inicio guardada: $resolvedRoot" -ForegroundColor Green
}

Set-Alias -Name dev -Value Invoke-DevNavigator -Scope Global
Export-ModuleMember -Function Invoke-DevNavigator, Update-DevNavigator, Get-DevRoot, Set-DevRoot, Set-DevUpdateCheck, Set-DevShortcut, Remove-DevShortcut -Alias dev
