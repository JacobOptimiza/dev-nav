<#
.SYNOPSIS
    Runs the DevNav Pester suite once and enforces the coverage gate.

.DESCRIPTION
    Single Pester 6.1.0 run over tests/powershell with code coverage measured
    against exactly these production files:

        powershell/DevNav.psm1
        install.ps1
        installer/ProfileIntegration.ps1

    Prints commands/lines coverage and exits non-zero if the tests fail or if
    either metric drops below the threshold (default 80%).

.EXAMPLE
    ./scripts/invoke-pester-coverage.ps1
#>
[CmdletBinding()]
param(
    [double]$Threshold = 80.0,
    [string]$CoverageOutputPath = 'TestResults/pester-coverage.xml'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module Pester -MinimumVersion 6.0 -Force

$config = New-PesterConfiguration
$config.Run.Path = './tests/powershell'
$config.Run.PassThru = $true
$config.Output.Verbosity = 'Detailed'
$config.CodeCoverage.Enabled = $true
$config.CodeCoverage.Path = @(
    'powershell/DevNav.psm1'
    'install.ps1'
    'installer/ProfileIntegration.ps1'
)
$config.CodeCoverage.OutputPath = $CoverageOutputPath

$result = Invoke-Pester -Configuration $config

$cc = $result.CodeCoverage
$commandsCovered = $cc.CommandsExecutedCount
$commandsTotal = $cc.CommandsAnalyzedCount
$commandsPercent = [math]::Round(100.0 * $commandsCovered / $commandsTotal, 2)

# Parse the JaCoCo report written to disk (the in-memory CoverageReport
# string includes a DOCTYPE that [xml] rejects; the file copy parses fine).
$xml = [xml](Get-Content $CoverageOutputPath -Raw)
# XPath is StrictMode-safe (adapted XML properties are not).
$lineCounter = $xml.SelectNodes('/report/counter') | Where-Object { $_.type -eq 'LINE' }
$linesCovered = [int]$lineCounter.covered
$linesTotal = $linesCovered + [int]$lineCounter.missed
$linesPercent = [math]::Round(100.0 * $linesCovered / $linesTotal, 2)

Write-Host "PowerShell coverage: commands $commandsCovered/$commandsTotal ($commandsPercent%), lines $linesCovered/$linesTotal ($linesPercent%)"

$failed = $false
if ($result.FailedCount -gt 0) {
    Write-Host "FAIL: $($result.FailedCount) Pester test(s) failed."
    $failed = $true
}
if ($commandsPercent -lt $Threshold) {
    Write-Host "FAIL: command coverage $commandsPercent% < $Threshold%"
    $failed = $true
}
if ($linesPercent -lt $Threshold) {
    Write-Host "FAIL: line coverage $linesPercent% < $Threshold%"
    $failed = $true
}
if ($failed) {
    exit 1
}
Write-Host "OK: PowerShell tests pass and coverage meets the $Threshold% threshold."
exit 0
