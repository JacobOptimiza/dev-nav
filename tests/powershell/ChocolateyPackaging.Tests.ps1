BeforeAll {
    $script:repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:helperPath = Join-Path $repositoryRoot 'packaging\chocolatey\tools\DevNavChocolatey.ps1'
    $script:installPath = Join-Path $repositoryRoot 'packaging\chocolatey\tools\chocolateyInstall.ps1'
    $script:materializerPath = Join-Path $repositoryRoot 'scripts\New-DevNavChocolateyPackage.ps1'
    . $script:helperPath
}

Describe 'Chocolatey native architecture routing' {
    It 'routes native x64 to x64' {
        Get-DevNavNativeArchitecture -ProcessorArchitecture AMD64 -ProcessorArchW6432 '' | Should -Be 'x64'
    }
    It 'routes an x86 process on x64 to x64' {
        Get-DevNavNativeArchitecture -ProcessorArchitecture x86 -ProcessorArchW6432 AMD64 | Should -Be 'x64'
    }
    It 'routes native ARM64 to arm64' {
        Get-DevNavNativeArchitecture -ProcessorArchitecture ARM64 -ProcessorArchW6432 '' | Should -Be 'arm64'
    }
    It 'routes an x86 process on ARM64 to arm64' {
        Get-DevNavNativeArchitecture -ProcessorArchitecture x86 -ProcessorArchW6432 ARM64 | Should -Be 'arm64'
    }
    It 'rejects real x86' {
        { Get-DevNavNativeArchitecture -ProcessorArchitecture x86 -ProcessorArchW6432 '' } | Should -Throw '*does not support x86*'
    }
    It 'rejects forcex86 on a native supported OS' {
        { Get-DevNavNativeArchitecture -ProcessorArchitecture AMD64 -ProcessorArchW6432 '' -ForceX86 $true } | Should -Throw '*forcex86*'
    }
}

Describe 'Chocolatey package source contract' {
    It 'uses official direct assets and the machine-owned marker' {
        $source = (Get-Content -LiteralPath $script:installPath -Raw) + (Get-Content -LiteralPath $script:helperPath -Raw)
        $source | Should -Match 'Get-ChocolateyWebFile'
        $source | Should -Match '\.devnav-managed-by-chocolatey'
        $source | Should -Not -Match 'DevNavSetup|Get-OSArchitectureWidth|Get-ProcessorBits'
        $source | Should -Match 'PSModulePath'
    }

    It 'materializes versioned URLs and hashes from a release manifest' {
        $root = Join-Path ([IO.Path]::GetTempPath()) ('devnav-choco-materialize-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $root | Out-Null
        try {
            $manifest = [ordered]@{
                schemaVersion = 1
                version = '9.8.7'
                artifacts = [ordered]@{
                    'binary-x64' = @{ file = 'dev-windows-x86_64.exe'; sha256 = ('a' * 64) }
                    'binary-arm64' = @{ file = 'dev-windows-aarch64.exe'; sha256 = ('b' * 64) }
                    module = @{ file = 'DevNav.psm1'; sha256 = ('c' * 64) }
                    'module-manifest' = @{ file = 'DevNav.psd1'; sha256 = ('d' * 64) }
                }
            }
            $manifestPath = Join-Path $root 'release-manifest.json'
            $manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath -Encoding utf8NoBOM
            $output = Join-Path $root 'package'
            & $script:materializerPath -Version '9.8.7' -ReleaseManifest $manifestPath -OutputDirectory $output | Out-Null
            $nuspec = Get-Content (Join-Path $output 'devnav.nuspec') -Raw
            $install = Get-Content (Join-Path $output 'tools\chocolateyInstall.ps1') -Raw
            $nuspec | Should -Match '<version>9\.8\.7</version>'
            $nuspec | Should -Match '<copyright>Copyright \(c\) 2026 JacobOptimiza</copyright>'
            $install | Should -Match 'releases/download/v9\.8\.7/dev-windows-x86_64\.exe'
            $install | Should -Match ('a' * 64)
            $install | Should -Not -Match '__[A-Z0-9_]+__'
        }
        finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'rejects a tampered file checksum' {
        $path = Join-Path ([IO.Path]::GetTempPath()) ('devnav-choco-tamper-' + [guid]::NewGuid().ToString('N'))
        'original' | Set-Content -LiteralPath $path -NoNewline
        try {
            { Assert-DevNavSha256 -Path $path -Expected ('0' * 64) } | Should -Throw '*SHA-256 mismatch*'
        }
        finally { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue }
    }

    It 'uses the supported package path API and no CPMR0072 private variables' {
        $root = Join-Path ([IO.Path]::GetTempPath()) ('devnav-choco-contract-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $root | Out-Null
        try {
            $manifest = [ordered]@{
                schemaVersion = 1
                version = '9.8.7'
                artifacts = [ordered]@{
                    'binary-x64' = @{ file = 'dev-windows-x86_64.exe'; sha256 = ('a' * 64) }
                    'binary-arm64' = @{ file = 'dev-windows-aarch64.exe'; sha256 = ('b' * 64) }
                    module = @{ file = 'DevNav.psm1'; sha256 = ('c' * 64) }
                    'module-manifest' = @{ file = 'DevNav.psd1'; sha256 = ('d' * 64) }
                }
            }
            $manifestPath = Join-Path $root 'release-manifest.json'
            $manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath -Encoding utf8NoBOM
            $output = Join-Path $root 'package'
            & $script:materializerPath -Version '9.8.7' -ReleaseManifest $manifestPath -OutputDirectory $output | Out-Null
            $scripts = Get-ChildItem (Join-Path $output 'tools') -File -Filter '*.ps*' -Recurse |
                ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }
            $scripts -join "`n" | Should -Match 'Get-ChocolateyPath -PathType ''PackagePath'''
            foreach ($variable in @(
                'chocolateyToolsLocation', 'chocolateyBinRoot', 'chocolatey_bin_root',
                'chocolateyPackageFolder', 'packageFolder', 'chocolateyChecksum32',
                'chocolateyChecksum64', 'chocolateyChecksumType32',
                'chocolateyChecksumType64', 'downloadCacheAvailable'
            )) {
                $scripts -join "`n" | Should -Not -Match ([regex]::Escape("`$env:$variable"))
            }
        }
        finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
