<#
.SYNOPSIS
    Verifies that DevNav's release build is bit-for-bit repeatable.

.DESCRIPTION
    Creates two isolated git worktrees from HEAD, performs a clean
    `cargo build --release --locked` in each with a separate target directory,
    and compares the SHA-256 of the produced dev.exe. Exits non-zero if the
    hashes differ. The working tree is never touched and all temporary
    worktrees are removed on exit.

.EXAMPLE
    ./scripts/verify-build-repeatability.ps1
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$runId = [guid]::NewGuid().ToString('N')
$worktreeA = Join-Path $env:TEMP "devnav-rep-a-$runId"
$worktreeB = Join-Path $env:TEMP "devnav-rep-b-$runId"

function Invoke-ReleaseBuild {
    param([string] $WorkTree)

    $previousLocation = Get-Location
    $previousTarget = $env:CARGO_TARGET_DIR
    try {
        $env:CARGO_TARGET_DIR = Join-Path $WorkTree 'target'
        Set-Location -LiteralPath $WorkTree
        & cargo build --release --locked
        if ($LASTEXITCODE -ne 0) {
            throw "cargo build --release --locked failed in $WorkTree (exit $LASTEXITCODE)."
        }
    }
    finally {
        Set-Location $previousLocation
        if ($null -ne $previousTarget) {
            $env:CARGO_TARGET_DIR = $previousTarget
        }
        else {
            Remove-Item Env:CARGO_TARGET_DIR -ErrorAction SilentlyContinue
        }
    }
}

try {
    Push-Location $repositoryRoot
    try {
        & git worktree add $worktreeA HEAD 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "git worktree add failed for $worktreeA." }
        & git worktree add $worktreeB HEAD 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "git worktree add failed for $worktreeB." }
    }
    finally {
        Pop-Location
    }

    Invoke-ReleaseBuild -WorkTree $worktreeA
    Invoke-ReleaseBuild -WorkTree $worktreeB

    $hashA = (Get-FileHash (Join-Path $worktreeA 'target\release\dev.exe') -Algorithm SHA256).Hash
    $hashB = (Get-FileHash (Join-Path $worktreeB 'target\release\dev.exe') -Algorithm SHA256).Hash
    Write-Host "build A: $hashA"
    Write-Host "build B: $hashB"

    if ($hashA -ne $hashB) {
        Write-Host 'FAIL: release builds from the same source are not bit-for-bit identical.'
        exit 1
    }
    Write-Host 'OK: release build is bit-for-bit repeatable.'
    exit 0
}
finally {
    Push-Location $repositoryRoot
    try {
        & git worktree remove $worktreeA --force 2>&1 | Out-Null
        & git worktree remove $worktreeB --force 2>&1 | Out-Null
        & git worktree prune 2>&1 | Out-Null
    }
    finally {
        Pop-Location
    }
}
