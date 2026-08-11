Set-StrictMode -Version Latest

function Invoke-DevNavigator {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]] $Command = @()
    )

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

    $resultFile = Join-Path ([System.IO.Path]::GetTempPath()) ("devnav-{0}.result" -f [guid]::NewGuid().ToString('N'))
    try {
        & $executable --root (Get-DevRoot) --result $resultFile
        if ($LASTEXITCODE -ne 0) { return }
        if (-not (Test-Path -LiteralPath $resultFile)) { return }

        $parts = [System.IO.File]::ReadAllText($resultFile).Split([char]0)
        if ($parts.Count -lt 2) { throw 'DevNav devolvió un resultado no válido.' }
        $kind, $directory = $parts[0], $parts[1]
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
    if ($env:DEV_HOME) { return $env:DEV_HOME }
    return (Join-Path $HOME 'programacion')
}

Set-Alias -Name dev -Value Invoke-DevNavigator -Scope Global
Export-ModuleMember -Function Invoke-DevNavigator, Get-DevRoot -Alias dev
