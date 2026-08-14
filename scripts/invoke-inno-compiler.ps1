[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('x64', 'arm64')][string]$Architecture,
    [Parameter(Mandatory)][string]$Version
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$assets = @{
    x64 = @{ Name = 'innosetup-7.1.0-x64.exe'; Sha256 = '0362A383ED217D4C4239B5933866DD96D3EB2102737DA92F80F6057A4B40DF2F' }
    arm64 = @{ Name = 'innosetup-7.1.0-x86.exe'; Sha256 = 'F9671174E0D15BA9B4F6B56564C6AED32EA8DB9C3CB9BF6F2AF0850FE7894F60' }
}
$asset = $assets[$Architecture]
$downloadRoot = Join-Path ([IO.Path]::GetTempPath()) ('devnav-inno-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $downloadRoot | Out-Null
$installer = Join-Path $downloadRoot $asset.Name
$url = "https://github.com/jrsoftware/issrc/releases/download/is-7_1_0/$($asset.Name)"

for ($attempt = 1; $attempt -le 5; $attempt++) {
    try {
        Invoke-WebRequest -Uri $url -OutFile $installer -ErrorAction Stop
        break
    } catch {
        if ($attempt -eq 5) { throw }
        Start-Sleep -Seconds ([Math]::Min($attempt * 2, 10))
    }
}

$actual = (Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash.ToUpperInvariant()
if ($actual -ne $asset.Sha256) { throw "Inno Setup checksum mismatch for $($asset.Name): $actual" }

$installRoot = Join-Path $downloadRoot 'install'
Start-Process -FilePath $installer -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', ("/DIR=$installRoot") -Wait -NoNewWindow
$iscc = Get-ChildItem -LiteralPath $installRoot -Filter 'ISCC.exe' -File -Recurse | Select-Object -First 1
if ($null -eq $iscc) { throw 'Verified Inno Setup compiler was not found.' }

$scriptRoot = Split-Path -Parent $PSScriptRoot
$output = Join-Path $scriptRoot "release-assets\DevNavSetup-$Architecture.exe"
& $iscc.FullName '/Qp' "/DMyAppVersion=$Version" "/DArchitecture=$Architecture" (Join-Path $scriptRoot 'installer\DevNav.iss')
if ($LASTEXITCODE -ne 0) { throw "Inno Setup compilation failed for $Architecture." }
if (-not (Test-Path -LiteralPath $output -PathType Leaf)) { throw "Expected installer was not generated: $output" }
Write-Output "Inno Setup 7.1.0 $Architecture PASS ($($iscc.FullName))"
