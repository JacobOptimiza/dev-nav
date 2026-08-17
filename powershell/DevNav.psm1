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
    $english = (Get-DevLanguage) -eq 'en-US'
    $state = if ($english) { if ($Enabled) { 'enabled' } else { 'disabled' } } else { if ($Enabled) { 'activada' } else { 'desactivada' } }
    if ($english) { Write-Host "Startup update checks: $state." -ForegroundColor Green }
    else { Write-Host "Comprobación de actualizaciones al iniciar: $state." -ForegroundColor Green }
}

function Get-DevLanguage {
    $value = Get-DevConfigValue -Name 'language'
    if ($value -in @('es-ES', 'en-US')) { return $value }
    return $null
}

function Get-DevSystemLanguage {
    try {
        # Avoid passing the new diagnostic switch to an older installed binary;
        # that binary would interpret it as a TUI invocation. The native
        # detector is used once the executable supports it, with the Windows UI
        # culture as a safe bootstrap fallback for older installations.
        $version = Get-DevInstalledVersion
        if ($version -ge [version]'0.10.0') {
            $output = (& (Get-DevExecutable) --detect-language | Out-String).Trim()
            if ($output -in @('es-ES', 'en-US')) { return $output }
        }
        $uiLanguage = (Get-UICulture).Name
        if ($uiLanguage -match '^es(?:-|$)') { return 'es-ES' }
        if ($uiLanguage -match '^en(?:-|$)') { return 'en-US' }
    }
    catch { Write-Verbose "System language detection failed: $($_.Exception.Message)" }
    return 'en-US'
}

function Set-DevLanguage {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory, Position = 0)][ValidateSet('es', 'en', 'es-ES', 'en-US')][string] $Language)
    $canonical = if ($Language -in @('es', 'es-ES')) { 'es-ES' } else { 'en-US' }
    if (-not $PSCmdlet.ShouldProcess('DevNav language', "Set language to $canonical")) { return }
    $exitCode = Invoke-DevCli -Arguments @('--set-language', $canonical)
    if ($exitCode -ne 0) {
        if ($canonical -eq 'en-US') { throw "Could not save language '$canonical'." }
        throw "No se pudo guardar el idioma '$canonical'."
    }
    if ($canonical -eq 'en-US') { Write-Host 'Language: English (en-US)' -ForegroundColor Green }
    else { Write-Host 'Idioma: Español (es-ES)' -ForegroundColor Green }
}

function Initialize-DevLanguage {
    $saved = Get-DevLanguage
    if ($saved) { return $saved }
    $detected = Get-DevSystemLanguage
    if ([Console]::IsInputRedirected) {
        Set-DevLanguage -Language $detected -Confirm:$false
        return $detected
    }
    if ($detected -eq 'es-ES') {
        Write-Host 'Idioma detectado / Detected language: Español' -ForegroundColor Cyan
        Write-Host '[1] Seguir en Español'
        Write-Host '[2] Switch to English'
    }
    else {
        Write-Host 'Detected language / Idioma detectado: English' -ForegroundColor Cyan
        Write-Host '[1] Continue in English'
        Write-Host '[2] Cambiar a Español'
    }
    Write-Host 'Elige / Choose: ' -NoNewline
    $key = [Console]::ReadKey($true)
    if ($key.Key -eq [ConsoleKey]::Escape) {
        Write-Host 'Esc'
        return $null
    }
    $answer = $key.KeyChar.ToString()
    Write-Host $answer
    $selected = if ($answer -eq '2') { if ($detected -eq 'es-ES') { 'en-US' } else { 'es-ES' } } else { $detected }
    Set-DevLanguage -Language $selected -Confirm:$false
    return $selected
}

function Get-DevInstalledVersion {
    $versionOutput = (& (Get-DevExecutable) --version | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $versionOutput -notmatch '^dev-nav\s+(?<Version>\d+\.\d+\.\d+)$') {
        if ((Get-DevLanguage) -eq 'en-US') { throw 'Unable to determine the installed DevNav version.' }
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

function Get-DevReleaseTag {
    param([Parameter(Mandatory)][string] $Tag)

    if ($Tag -notmatch '^v(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)$') {
        throw "La release publicada tiene un tag no compatible: $Tag"
    }
    return $Tag
}

function Get-DevReleaseAssetUrl {
    param(
        [Parameter(Mandatory)][string] $Tag,
        [Parameter(Mandatory)][string] $AssetName
    )

    $allowedAssets = @(
        'dev-windows-x86_64.exe',
        'dev-windows-aarch64.exe',
        'DevNav.psm1',
        'SHA256SUMS.txt'
    )
    if ($AssetName -notin $allowedAssets) {
        throw "El asset de release no está permitido: $AssetName"
    }

    $releaseTag = Get-DevReleaseTag -Tag $Tag
    return "https://github.com/$script:DevNavRepository/releases/download/$releaseTag/$AssetName"
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
    if ((Get-DevLanguage) -eq 'en-US') { throw "Could not download '$Uri' after $Attempts attempts: $($lastError.Exception.Message)" }
    throw "No se pudo descargar '$Uri' tras $Attempts intentos: $($lastError.Exception.Message)"
}

function Initialize-DevUpdateCheckPreference {
    $saved = Get-DevConfigValue -Name 'check_updates'
    if ($null -ne $saved) { return $saved -eq 'true' }
    if ([Console]::IsInputRedirected) { return $false }

    $english = (Get-DevLanguage) -eq 'en-US'
    if ($english) {
        Write-Host 'DevNav can check GitHub for new versions at startup.' -ForegroundColor Cyan
        Write-Host 'It only checks: it never downloads or installs without your explicit confirmation.'
        $answer = (Read-Host 'Keep startup update checks enabled? [Y/n]').Trim()
        $enabled = $answer -notmatch '^(?i:n|no)$'
    }
    else {
        Write-Host 'DevNav puede comprobar en GitHub si existe una versión nueva al iniciar.' -ForegroundColor Cyan
        Write-Host 'Sólo comprueba: nunca descarga ni instala sin tu confirmación explícita.'
        $answer = (Read-Host '¿Mantener esta comprobación activada? [S/n]').Trim()
        $enabled = $answer -notmatch '^(?i:n|no)$'
    }
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
    Initialize-DevLanguage | Out-Null
    if (-not (Initialize-DevUpdateCheckPreference)) { return }

    try {
        $installedVersion = Get-DevInstalledVersion
        $release = Get-DevLatestRelease -TimeoutSeconds 5
        $releaseTag = Get-DevReleaseTag -Tag ([string]$release.tag_name)
        $latestText = $releaseTag.Substring(1)
        $latestVersion = [version]$latestText
    }
    catch {
        # The optional startup check must never block normal navigation.
        return
    }

    if ($latestVersion -le $installedVersion) { return }
    $english = (Get-DevLanguage) -eq 'en-US'
    if ($english) {
        Write-Host "New version available: v$installedVersion → v$latestVersion" -ForegroundColor Yellow
        $answer = (Read-Host 'Update now? [y/N]').Trim()
    }
    else {
        Write-Host "Nueva versión disponible: v$installedVersion → v$latestVersion" -ForegroundColor Yellow
        $answer = (Read-Host '¿Quieres actualizar ahora? [s/N]').Trim()
    }
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
        if ((Get-DevLanguage) -eq 'en-US') { throw 'dev.exe was not found. Run install.ps1 from the DevNav repository root.' }
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
        if ($exitCode -ne 0) {
            if ((Get-DevLanguage) -eq 'en-US') { throw "Could not remove shortcut $Index (dev.exe exited with $exitCode)." }
            throw "No se pudo eliminar el atajo $Index (dev.exe salió con $exitCode)."
        }
        if ((Get-DevLanguage) -eq 'en-US') { Write-Host "Shortcut $Index removed." -ForegroundColor Green }
        else { Write-Host "Atajo $Index eliminado." -ForegroundColor Green }
        return
    }

    if ([string]::IsNullOrWhiteSpace($Command)) {
        if ((Get-DevLanguage) -eq 'en-US') { throw 'Specify the shortcut command, or use -Clear to remove it.' }
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
    if ($exitCode -ne 0) {
        if ((Get-DevLanguage) -eq 'en-US') { throw "Could not save shortcut $Index (dev.exe exited with $exitCode)." }
        throw "No se pudo guardar el atajo $Index (dev.exe salió con $exitCode)."
    }
    $label = if ([string]::IsNullOrWhiteSpace($Alias)) { $Command } else { $Alias }
    if ((Get-DevLanguage) -eq 'en-US') { Write-Host "Shortcut $Index saved: $label" -ForegroundColor Green }
    else { Write-Host "Atajo $Index guardado: $label" -ForegroundColor Green }
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

function Resolve-DevShortcutUsageError {
    # Single source for the `dev shortcut` usage contract so the dispatch
    # entry points cannot drift apart.
    if ((Get-DevLanguage) -eq 'en-US') {
        throw "Usage: dev shortcut <1..9> [alias] <command>`nTo remove: dev shortcut <1..9>"
    }
    throw "Uso: dev shortcut <1..9> [alias] <comando>`nPara eliminar: dev shortcut <1..9>"
}

function Invoke-DevShortcutCommand {
    # Parses the `dev shortcut <args>` form. Kept separate from
    # Invoke-DevNavigator so the parsing is unit-testable in isolation.
    param([Parameter(Mandatory)][ValidateNotNullOrEmpty()][string[]] $Items)

    switch ($Items.Count) {
        1 { Remove-DevShortcut -Index $Items[0] }
        2 { Set-DevShortcut -Index $Items[0] -Command $Items[1] }
        3 { Set-DevShortcut -Index $Items[0] -Alias $Items[1] -Command $Items[2] }
        default { Resolve-DevShortcutUsageError }
    }
}

function Update-DevNavigator {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    if (Test-DevManagedInstallation) {
        if ((Get-DevLanguage) -eq 'en-US') {
            Write-Host 'This installation is managed by Scoop; DevNav will not self-update.' -ForegroundColor Yellow
            Write-Host 'Update it with: scoop update devnav' -ForegroundColor Cyan
        } else {
            Write-Host 'Esta instalación la gestiona Scoop; DevNav no se actualiza a sí mismo.' -ForegroundColor Yellow
            Write-Host 'Para actualizar, ejecuta: scoop update devnav' -ForegroundColor Cyan
        }
        return
    }
    $ErrorActionPreference = 'Stop'
    if (-not $PSCmdlet.ShouldProcess('DevNav installation', 'Download and install the selected release')) { return }
    $currentVersion = Get-DevInstalledVersion
    $currentText = $currentVersion.ToString()
    if ((Get-DevLanguage) -eq 'en-US') {
        Write-Host "Installed version: v$currentText"
        Write-Host 'Checking the latest published version...'
    } else {
        Write-Host "Versión instalada: v$currentText"
        Write-Host 'Comprobando la última versión publicada...'
    }
    $release = Get-DevLatestRelease
    $releaseTag = Get-DevReleaseTag -Tag ([string]$release.tag_name)
    $latestText = $releaseTag.Substring(1)
    $latestVersion = [version]$latestText
    if ((Get-DevLanguage) -eq 'en-US') { Write-Host "Latest published: v$latestText" }
    else { Write-Host "Última publicada: v$latestText" }

    if ($currentVersion -ge $latestVersion) {
        if ($currentVersion -eq $latestVersion) {
            if ((Get-DevLanguage) -eq 'en-US') { Write-Host "You already have the latest version (v$currentText). No update is needed." -ForegroundColor Green }
            else { Write-Host "Ya tienes la última versión (v$currentText). No hace falta actualizar." -ForegroundColor Green }
        }
        else {
            if ((Get-DevLanguage) -eq 'en-US') { Write-Host 'The installed version is newer than the latest published release; nothing changed.' -ForegroundColor Yellow }
            else { Write-Host 'La versión instalada es más reciente que la última release publicada; no se modificó nada.' -ForegroundColor Yellow }
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
        $downloads[$assetName] = Get-DevReleaseAssetUrl -Tag $releaseTag -AssetName $assetName
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
        if ((Get-DevLanguage) -eq 'en-US') { Write-Host "Downloading DevNav v$latestText..." }
        else { Write-Host "Descargando DevNav v$latestText..." }
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
        if ((Get-DevLanguage) -eq 'en-US') { Write-Host "DevNav updated successfully: v$currentText → v$latestText." -ForegroundColor Green }
        else { Write-Host "DevNav actualizado correctamente: v$currentText → v$latestText." -ForegroundColor Green }
        if ($moduleChanged) {
            $script:DevNavRestartRequired = $true
            if ((Get-DevLanguage) -eq 'en-US') { Write-Warning 'DevNav.psm1 also changed. Restart PowerShell to load the updated module.' }
            else { Write-Warning 'DevNav.psm1 también cambió. Reinicia PowerShell para cargar el módulo actualizado.' }
        }
        else {
            if ((Get-DevLanguage) -eq 'en-US') { Write-Host 'Run dev again to continue.' -ForegroundColor Cyan }
            else { Write-Host 'Ejecuta dev de nuevo para continuar.' -ForegroundColor Cyan }
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

function Set-DevAgentWindowTitle {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string] $Agent,
        [Parameter(Mandatory)][string] $Repository,
        [object] $HostObject = $Host
    )

    if ([string]::IsNullOrWhiteSpace($Agent) -or [string]::IsNullOrWhiteSpace($Repository)) {
        return $null
    }
    if (-not $PSCmdlet.ShouldProcess("$Agent/$Repository", 'Set console title')) {
        return $null
    }
    try {
        $original = $HostObject.UI.RawUI.WindowTitle
        $HostObject.UI.RawUI.WindowTitle = "$Agent/$Repository"
        return $original
    } catch {
        # Window titles are cosmetic and vary by host. Never block navigation.
        return $null
    }
}

function Restore-DevWindowTitle {
    [CmdletBinding()]
    param(
        [AllowEmptyString()][AllowNull()][string] $OriginalTitle,
        [object] $HostObject = $Host
    )

    if ($null -eq $OriginalTitle) { return }
    try { $HostObject.UI.RawUI.WindowTitle = $OriginalTitle } catch { Write-Verbose 'Host does not support title restoration.' }
}

function Get-DevAgentTitlePolicy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('Codex', 'Claude', 'OpenCode', 'Kimi')][string] $Agent,
        [string] $LaunchPolicy
    )

    # Accept the pre-0.14 spellings so result files produced by older DevNav
    # builds remain executable. New results make ownership explicit.
    switch ($LaunchPolicy) {
        'native-agent-title' { return 'native-agent-title' }
        'keep-agent-title' { return 'native-agent-title' }
        'devnav-managed-title' { return 'devnav-managed-title' }
        'disable-agent-title' { return 'devnav-managed-title' }
        default {
            if ($Agent -eq 'Kimi') { return 'native-agent-title' }
            return 'devnav-managed-title'
        }
    }
}

function Invoke-DevAgentCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $CommandText,
        [Parameter(Mandatory)][ValidateSet('Codex', 'Claude', 'OpenCode', 'Kimi')][string] $Agent,
        [string] $LaunchPolicy
    )

    # The native result identifies the agent; this adapter never guesses it
    # from arbitrary command text. These settings are process-local and are
    # restored immediately after the child exits.
    $policy = Get-DevAgentTitlePolicy -Agent $Agent -LaunchPolicy $LaunchPolicy
    $environmentNames = switch ($Agent) {
        'Claude' { @('CLAUDE_CODE_DISABLE_TERMINAL_TITLE') }
        'OpenCode' { @('OPENCODE_DISABLE_TERMINAL_TITLE') }
        default { @() }
    }
    $savedEnvironment = @{}
    foreach ($name in $environmentNames) {
        $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
        if ($policy -eq 'devnav-managed-title') {
            Set-Item -Path "Env:$name" -Value '1'
        }
    }

    # Codex exposes its title policy as an official per-invocation config
    # override. Keep the user's command semantics and add only that title
    # setting to the known DevNav launch forms.
    $launchCommand = $CommandText
    if ($Agent -eq 'Codex' -and $policy -eq 'devnav-managed-title') {
        $launchCommand = switch ($CommandText) {
            'codex' { "codex -c 'tui.terminal_title=[]'" }
            'codex resume --last' { "codex -c 'tui.terminal_title=[]' resume --last" }
            default { $CommandText }
        }
    }

    try {
        Invoke-Expression $launchCommand
    }
    finally {
        foreach ($name in $environmentNames) {
            if ($null -eq $savedEnvironment[$name]) {
                Remove-Item -Path "Env:$name" -ErrorAction SilentlyContinue
            }
            else {
                Set-Item -Path "Env:$name" -Value $savedEnvironment[$name]
            }
        }
    }
}

function Invoke-DevNavigator {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]] $Command = @()
    )

    if ($Command.Count -ge 1 -and $Command[0] -eq 'language') {
        if ($Command.Count -eq 1) {
            $current = Get-DevLanguage
            if (-not $current) { $current = Get-DevSystemLanguage }
            if ($current -eq 'en-US') { Write-Output 'English (en-US)' } else { Write-Output 'Español (es-ES)' }
        } else {
            Set-DevLanguage -Language $Command[1]
        }
        return
    }
    if ($Command.Count -eq 1 -and $Command[0] -eq 'update') {
        $script:DevNavUpdateCompleted = $false
        Update-DevNavigator
        return
    }
    if ($Command.Count -ge 1 -and $Command[0] -eq 'shortcut') {
        $items = @($Command | Select-Object -Skip 1)
        if ($items.Count -eq 0) {
            Resolve-DevShortcutUsageError
        }
        Invoke-DevShortcutCommand -Items $items
        return
    }
    $script:DevNavUpdateCompleted = $false
    $selectedLanguage = Initialize-DevLanguage
    if (-not $selectedLanguage) { return }
    Invoke-DevStartupUpdateCheck
    if ($script:DevNavUpdateCompleted) {
        return
    }
    if ($script:DevNavRestartRequired) {
        if ((Get-DevLanguage) -eq 'en-US') { Write-Warning 'DevNav was updated. Restart PowerShell to load the updated module.' }
        else { Write-Warning 'DevNav se ha actualizado. Reinicia PowerShell para cargar el módulo actualizado.' }
        return
    }
    $executable = Get-DevExecutable

    $resultFile = Join-Path ([System.IO.Path]::GetTempPath()) ("devnav-{0}.result" -f [guid]::NewGuid().ToString('N'))
    try {
        & $executable --root (Get-DevRoot) --result $resultFile
        if ($LASTEXITCODE -ne 0) { return }
        if (-not (Test-Path -LiteralPath $resultFile)) { return }

        $parts = [System.IO.File]::ReadAllText($resultFile).Split([char]0)
        if ($parts.Count -lt 2) {
            if ((Get-DevLanguage) -eq 'en-US') { throw 'DevNav returned an invalid result.' }
            throw 'DevNav devolvió un resultado no válido.'
        }
        $kind, $directory = $parts[0], $parts[1]
        if ($kind -eq 'update') {
            Update-DevNavigator
            return
        }
        Set-Location -LiteralPath $directory

        $commandText = if ($Command.Count -gt 0) { $Command -join ' ' } elseif ($parts.Count -gt 2) { $parts[2] } else { '' }
        $originalWindowTitle = $null
        $windowTitleChanged = $false
        $agent = $null
        $launchPolicy = $null
        if ($Command.Count -eq 0 -and $kind -eq 'exec' -and $parts.Count -ge 5) {
            $agent = $parts[3]
            if ($parts.Count -ge 6) { $launchPolicy = $parts[5] }
            $effectiveTitlePolicy = Get-DevAgentTitlePolicy -Agent $agent -LaunchPolicy $launchPolicy
            if ($effectiveTitlePolicy -eq 'devnav-managed-title') {
                $originalWindowTitle = Set-DevAgentWindowTitle -Agent $agent -Repository $parts[4]
                $windowTitleChanged = $null -ne $originalWindowTitle
            }
        }
        if ($kind -eq 'exec' -or $Command.Count -gt 0) {
            try {
                if (-not [string]::IsNullOrWhiteSpace($commandText)) {
                    if ($null -ne $agent) {
                        Invoke-DevAgentCommand -CommandText $commandText -Agent $agent -LaunchPolicy $launchPolicy
                    }
                    else {
                        Invoke-Expression $commandText
                    }
                }
            } finally {
                if ($windowTitleChanged) {
                    Restore-DevWindowTitle -OriginalTitle $originalWindowTitle
                }
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
    if ((Get-DevLanguage) -eq 'en-US') { Write-Host "Startup folder saved: $resolvedRoot" -ForegroundColor Green }
    else { Write-Host "Ruta de inicio guardada: $resolvedRoot" -ForegroundColor Green }
}

Set-Alias -Name dev -Value Invoke-DevNavigator -Scope Global
Export-ModuleMember -Function Invoke-DevNavigator, Update-DevNavigator, Get-DevRoot, Set-DevRoot, Set-DevUpdateCheck, Set-DevLanguage, Get-DevLanguage, Set-DevShortcut, Remove-DevShortcut -Alias dev
