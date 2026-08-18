Set-StrictMode -Version Latest

function Get-DevNavNativeArchitecture {
    [CmdletBinding()]
    param(
        [string] $ProcessorArchitecture = $env:PROCESSOR_ARCHITECTURE,
        [string] $ProcessorArchW6432 = $env:PROCESSOR_ARCHITEW6432,
        [bool] $ForceX86 = ($env:ChocolateyForceX86 -eq 'true')
    )

    $process = ([string]$ProcessorArchitecture).Trim().ToUpperInvariant()
    $wow = ([string]$ProcessorArchW6432).Trim().ToUpperInvariant()
    $native = if ($process -eq 'ARM64' -or $wow -eq 'ARM64') {
        'arm64'
    }
    elseif ($process -eq 'AMD64' -or $wow -eq 'AMD64') {
        'x64'
    }
    elseif ($process -eq 'X86' -and [string]::IsNullOrWhiteSpace($wow)) {
        'x86'
    }
    else {
        throw "Unsupported Windows architecture environment: PROCESSOR_ARCHITECTURE='$process', PROCESSOR_ARCHITEW6432='$wow'."
    }

    if ($ForceX86 -and $native -ne 'x86') {
        throw "Chocolatey --forcex86 is unsafe for DevNav: the native OS architecture is $native. DevNav does not provide x86 assets."
    }
    if ($native -eq 'x86') {
        throw 'DevNav does not support x86 Windows. Use a native x64 or ARM64 system.'
    }
    return $native
}

function Get-DevNavAssetSet {
    param(
        [Parameter(Mandatory)][ValidateSet('x64', 'arm64')][string] $Architecture,
        [Parameter(Mandatory)][hashtable] $Assets
    )

    $selected = $Assets[$Architecture]
    if ($null -eq $selected) { throw "No DevNav release assets were supplied for $Architecture." }
    foreach ($name in @('dev', 'module', 'manifest')) {
        if ([string]::IsNullOrWhiteSpace([string]$selected[$name].url) -or
            [string]::IsNullOrWhiteSpace([string]$selected[$name].sha256)) {
            throw "The $Architecture DevNav asset '$name' is missing its URL or SHA-256."
        }
    }
    return $selected
}

function Assert-DevNavSha256 {
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][ValidatePattern('^[A-Fa-f0-9]{64}$')][string] $Expected
    )
    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    if ($actual -ne $Expected) { throw "SHA-256 mismatch for '$Path'." }
}

function Add-DevNavMachineModulePath {
    param([Parameter(Mandatory)][string] $PackageTools)

    $machine = [Environment]::GetEnvironmentVariable('PSModulePath', 'Machine')
    $entries = @($machine -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($entries -notcontains $PackageTools) {
        [Environment]::SetEnvironmentVariable('PSModulePath', (($entries + $PackageTools) -join ';'), 'Machine')
    }
}

function Remove-DevNavMachineModulePath {
    param([Parameter(Mandatory)][string] $PackageTools)

    $machine = [Environment]::GetEnvironmentVariable('PSModulePath', 'Machine')
    $entries = @($machine -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and $_ -ne $PackageTools })
    [Environment]::SetEnvironmentVariable('PSModulePath', ($entries -join ';'), 'Machine')
}
