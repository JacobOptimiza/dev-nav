[CmdletBinding()]
param(
    [string] $RepositoryRoot = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$settingsPath = Join-Path $RepositoryRoot 'PSScriptAnalyzerSettings.psd1'
$powerShellFiles = @(
    Get-ChildItem -LiteralPath $RepositoryRoot -Recurse -File -Include '*.ps1', '*.psm1' |
        Where-Object FullName -notmatch '\\target\\|\\.git\\|\\tests\\'
)
$modulePath = Join-Path $RepositoryRoot 'powershell\DevNav.psm1'
$parseErrors = $null
$tokens = $null
[System.Management.Automation.Language.Parser]::ParseFile(
    $modulePath,
    [ref] $tokens,
    [ref] $parseErrors
) | Out-Null
if ($parseErrors.Count -gt 0) {
    $details = $parseErrors | ForEach-Object { $_.Message }
    throw "PowerShell syntax errors:`n$($details -join "`n")"
}

$manifestPath = Join-Path $RepositoryRoot 'powershell\DevNav.psd1'
Test-ModuleManifest -Path $manifestPath -ErrorAction Stop | Out-Null

$diagnostics = @(
    foreach ($file in $powerShellFiles) {
        Invoke-ScriptAnalyzer -Path ([string] $file.FullName) -Settings $settingsPath
    }
)
$blocking = @($diagnostics | Where-Object Severity -in @('Error', 'Warning'))
if ($blocking.Count -gt 0) {
    $blocking | Format-List | Out-String | Write-Error
    exit 1
}

Write-Output 'PowerShell parser and PSScriptAnalyzer validation passed.'
