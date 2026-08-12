[CmdletBinding()]
param(
    [switch] $Install,
    [switch] $Uninstall,
    [Parameter(Mandatory)][string] $ModulePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($Install -eq $Uninstall) { throw 'Specify exactly one of -Install or -Uninstall.' }
$profilePath = $PROFILE.CurrentUserCurrentHost
$profileDirectory = Split-Path -Parent $profilePath
$startMarker = '# >>> DevNav >>>'
$endMarker = '# <<< DevNav <<<'
$importLine = "Import-Module '$($ModulePath.Replace("'", "''"))'"
$block = @($startMarker, $importLine, $endMarker)
$content = if (Test-Path -LiteralPath $profilePath -PathType Leaf) {
    @(Get-Content -LiteralPath $profilePath)
}
else {
    @()
}

$start = [Array]::IndexOf($content, $startMarker)
$end = [Array]::IndexOf($content, $endMarker)
if ($start -ge 0 -and $end -ge $start) {
    $before = if ($start -gt 0) { @($content[0..($start - 1)]) } else { @() }
    $after = if ($end + 1 -lt $content.Count) { @($content[($end + 1)..($content.Count - 1)]) } else { @() }
    $content = @($before) + @($after)
}

if ($Install) {
    New-Item -ItemType Directory -Path $profileDirectory -Force | Out-Null
    $content = @($content) + @('', $block)
}

if ($content.Count -eq 0) {
    if (Test-Path -LiteralPath $profilePath) { Remove-Item -LiteralPath $profilePath -Force }
    exit 0
}

New-Item -ItemType Directory -Path $profileDirectory -Force | Out-Null
Set-Content -LiteralPath $profilePath -Value $content -Encoding utf8NoBOM
