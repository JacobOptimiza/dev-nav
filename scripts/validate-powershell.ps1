[CmdletBinding()]
param(
    [string] $RepositoryRoot = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$settingsPath = Join-Path $RepositoryRoot 'PSScriptAnalyzerSettings.psd1'
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

$diagnostics = @(Invoke-ScriptAnalyzer -Path $modulePath -Settings $settingsPath)
$blocking = @($diagnostics | Where-Object Severity -in @('Error', 'Warning'))
if ($blocking.Count -gt 0) {
    $blocking | Format-List | Out-String | Write-Error
    exit 1
}

Write-Output 'PowerShell parser and PSScriptAnalyzer validation passed.'
