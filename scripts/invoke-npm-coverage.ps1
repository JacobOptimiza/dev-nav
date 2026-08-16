<#
.SYNOPSIS
    Runs the npm bootstrap tests with Node's native test coverage and enforces
    the coverage gate.

.DESCRIPTION
    Single `node --test --experimental-test-coverage` run over tests/npm.
    Node's test runner reports *line* coverage (not statement coverage); that
    is the metric this gate enforces, per covered source file. Exits non-zero
    if the tests fail or any covered file drops below the threshold
    (default 80%). No extra npm dependencies are required.

.EXAMPLE
    ./scripts/invoke-npm-coverage.ps1
#>
[CmdletBinding()]
param(
    [double]$Threshold = 80.0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$output = & node --test --experimental-test-coverage "tests/npm/**/*.test.mjs" 2>&1
$testsExit = $LASTEXITCODE
$output | ForEach-Object { $_ }

if ($testsExit -ne 0) {
    Write-Host "FAIL: npm bootstrap tests failed (exit $testsExit)."
    exit 1
}

$rows = @()
foreach ($line in $output) {
    $text = $line -replace '^[^a-zA-Z0-9]*', ''
    if ($text -match '^\s*(\S+\.(?:mjs|cjs|js))\s*\|\s*([\d.]+)\s*\|\s*([\d.]+)\s*\|\s*([\d.]+)\s*\|') {
        $rows += [pscustomobject]@{
            File     = $Matches[1]
            LinePct  = [double]$Matches[2]
            BranchPct = [double]$Matches[3]
            FuncPct  = [double]$Matches[4]
        }
    }
}

if ($rows.Count -eq 0) {
    Write-Host "FAIL: no coverage rows found in node --test output."
    exit 1
}

foreach ($row in $rows) {
    Write-Host ("JavaScript coverage: {0} lines {1}%, branches {2}%, functions {3}%" -f
        $row.File, $row.LinePct, $row.BranchPct, $row.FuncPct)
}

$below = @($rows | Where-Object { $_.LinePct -lt $Threshold })
if ($below.Count -gt 0) {
    foreach ($row in $below) {
        Write-Host "FAIL: line coverage for $($row.File) is $($row.LinePct)% < $Threshold%"
    }
    exit 1
}
Write-Host "OK: npm bootstrap tests pass and line coverage meets the $Threshold% threshold."
exit 0
