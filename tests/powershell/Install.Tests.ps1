BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $repositoryRoot = Split-Path -Parent $repositoryRoot
    $installScriptPath = Join-Path $repositoryRoot 'install.ps1'
    $originalLocalAppData = $env:LOCALAPPDATA
    $realProfilePath = $PROFILE
    $realProfileSnapshot = if (Test-Path -LiteralPath $realProfilePath -PathType Leaf) {
        [pscustomobject]@{ Exists = $true; Hash = (Get-FileHash -LiteralPath $realProfilePath -Algorithm SHA256).Hash }
    }
    else {
        [pscustomobject]@{ Exists = $false; Hash = $null }
    }
}

AfterAll {
    $env:LOCALAPPDATA = $originalLocalAppData
    $currentSnapshot = if (Test-Path -LiteralPath $realProfilePath -PathType Leaf) {
        [pscustomobject]@{ Exists = $true; Hash = (Get-FileHash -LiteralPath $realProfilePath -Algorithm SHA256).Hash }
    }
    else {
        [pscustomobject]@{ Exists = $false; Hash = $null }
    }
    $currentSnapshot.Exists | Should -Be $realProfileSnapshot.Exists
    $currentSnapshot.Hash | Should -Be $realProfileSnapshot.Hash
}

Describe 'install.ps1 release bootstrap behavior' {
    BeforeEach {
        $env:LOCALAPPDATA = "C:\Users\Profile'Test\AppData\Local"
        $global:installDownloadUris = [System.Collections.Generic.List[string]]::new()
        $global:installDownloadPaths = [System.Collections.Generic.List[string]]::new()
        $global:installCopyRecords = [System.Collections.Generic.List[object]]::new()
        $global:installRemovedPaths = [System.Collections.Generic.List[string]]::new()
        $global:installNewItemPaths = [System.Collections.Generic.List[string]]::new()
        $global:installContentPaths = [System.Collections.Generic.List[string]]::new()
        $global:installHashRecords = [System.Collections.Generic.List[object]]::new()
        $global:installImportRecords = [System.Collections.Generic.List[object]]::new()
        $global:installProfileAdds = [System.Collections.Generic.List[object]]::new()
        $global:installProfileExists = $false
        $global:installExistingProfileContent = @()
        $global:installHashMismatchCall = 0
        $global:installHashCall = 0
        $global:installHostArchitecture = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
        $global:installExpectedAsset = switch ($global:installHostArchitecture) {
            'X64' { 'dev-windows-x86_64.exe' }
            'Arm64' { 'dev-windows-aarch64.exe' }
            default { throw "Unsupported test host architecture: $global:installHostArchitecture" }
        }

        Mock Invoke-WebRequest {
            param($Uri, $OutFile)
            [void] $global:installDownloadUris.Add($Uri)
            [void] $global:installDownloadPaths.Add($OutFile)
        }
        Mock Get-Content {
            param($LiteralPath, $Raw)
            [void] $global:installContentPaths.Add($LiteralPath)
            if ($LiteralPath -like '*.sha256') {
                return @(
                    "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA $($global:installExpectedAsset)",
                    'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB DevNav.psm1'
                )
            }
            if ($global:installProfileExists) { return $global:installExistingProfileContent }
            return ''
        }
        Mock Get-FileHash {
            param($LiteralPath, $Algorithm)
            $global:installHashCall++
            [void] $global:installHashRecords.Add([pscustomobject]@{ LiteralPath = $LiteralPath; Algorithm = $Algorithm })
            if ($global:installHashMismatchCall -eq $global:installHashCall) {
                return [pscustomobject]@{ Hash = 'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC' }
            }
            if ($LiteralPath -like '*.psm1') { return [pscustomobject]@{ Hash = 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB' } }
            return [pscustomobject]@{ Hash = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA' }
        }
        Mock New-Item {
            param($Path)
            [void] $global:installNewItemPaths.Add($Path)
            [pscustomobject]@{ FullName = $Path }
        }
        Mock Copy-Item {
            param($LiteralPath, $Destination, $Force)
            [void] $global:installCopyRecords.Add([pscustomobject]@{ LiteralPath = $LiteralPath; Destination = $Destination; Force = $Force })
        }
        Mock Remove-Item {
            param($LiteralPath)
            [void] $global:installRemovedPaths.Add($LiteralPath)
        }
        Mock Import-Module {
            param($Name, $Force)
            [void] $global:installImportRecords.Add([pscustomobject]@{ Name = $Name; Force = $Force })
        }
        Mock Test-Path {
            param($LiteralPath, $PathType)
            return $global:installProfileExists
        }
        Mock Add-Content {
            param($LiteralPath, $Value)
            [void] $global:installProfileAdds.Add([pscustomobject]@{ LiteralPath = $LiteralPath; Value = $Value })
        }
    }

    It 'downloads and installs the verified host-architecture release with SHA-256 checks' {
        & $installScriptPath -ModifyProfile:$false

        $global:installDownloadUris | Should -Be @(
            "https://github.com/JacobOptimiza/dev-nav/releases/latest/download/$($global:installExpectedAsset)",
            'https://github.com/JacobOptimiza/dev-nav/releases/latest/download/DevNav.psm1',
            'https://github.com/JacobOptimiza/dev-nav/releases/latest/download/SHA256SUMS.txt'
        )
        $global:installDownloadPaths.Count | Should -Be 3
        $global:installHashRecords.Count | Should -Be 2
        $global:installHashRecords.Algorithm | Should -Be @('SHA256', 'SHA256')
        $global:installHashRecords.LiteralPath | Should -Be @($global:installDownloadPaths[0], $global:installDownloadPaths[1])
        $global:installCopyRecords.Count | Should -Be 2
        $global:installCopyRecords.LiteralPath | Should -Be @($global:installDownloadPaths[0], $global:installDownloadPaths[1])
        $global:installCopyRecords.Destination | Should -Be @(
            "C:\Users\Profile'Test\AppData\Local\Programs\DevNav\dev.exe",
            "C:\Users\Profile'Test\AppData\Local\Programs\DevNav\DevNav.psm1"
        )
        $global:installCopyRecords.Force | Should -Be @($true, $true)
        $global:installImportRecords.Count | Should -Be 1
        $global:installImportRecords.Name | Should -Be "C:\Users\Profile'Test\AppData\Local\Programs\DevNav\DevNav.psm1"
        $global:installImportRecords.Force | Should -BeTrue
        $global:installProfileAdds.Count | Should -Be 0
        $global:installRemovedPaths | Should -Be $global:installDownloadPaths
        Should -Invoke Test-Path -Times 0 -Scope It
        $global:installContentPaths | Should -Not -Contain $PROFILE
        Should -Invoke Add-Content -Times 0 -Scope It
        $global:installNewItemPaths | Should -Not -Contain (Split-Path -Parent $PROFILE)
    }

    It 'imports the installed module with a safely quoted profile path' {
        & $installScriptPath

        $global:installProfileAdds.Count | Should -Be 1
        $global:installProfileAdds[0].LiteralPath | Should -Be $PROFILE
        $global:installProfileAdds[0].Value | Should -Be "`nImport-Module 'C:\Users\Profile''Test\AppData\Local\Programs\DevNav\DevNav.psm1'"
        $global:installRemovedPaths | Should -Be $global:installDownloadPaths
    }

    It 'does not append a duplicate import when the profile already contains it' {
        $global:installProfileExists = $true
        $global:installExistingProfileContent = "Import-Module 'C:\Users\Profile''Test\AppData\Local\Programs\DevNav\DevNav.psm1'"

        & $installScriptPath

        $global:installProfileAdds.Count | Should -Be 0
    }

    It 'builds from source with a discovered Cargo executable' {
        $locationBefore = (Get-Location).Path
        $cargoShimPath = Join-Path ([System.IO.Path]::GetTempPath()) ("devnav-cargo-{0}.cmd" -f [guid]::NewGuid().ToString('N'))
        $cargoLogPath = Join-Path ([System.IO.Path]::GetTempPath()) ("devnav-cargo-{0}.log" -f [guid]::NewGuid().ToString('N'))
        $cargoShim = "@echo off`r`n>>`"$cargoLogPath`" echo %*`r`nexit /b 0`r`n"
        [System.IO.File]::WriteAllText($cargoShimPath, $cargoShim)

        try {
            Mock Get-Command { [pscustomobject]@{ Source = $cargoShimPath } }
            Mock Test-Path {
                param($LiteralPath, $PathType)
                return $LiteralPath -eq $cargoShimPath
            }
            Mock Push-Location { param($Path) }
            Mock Pop-Location { }

            & $installScriptPath -BuildFromSource -ModifyProfile:$false

            $cargoInvocations = [System.IO.File]::ReadAllLines($cargoLogPath)
            $cargoInvocations | Should -Be @('test', 'build --release')
            Should -Invoke Get-Command -ParameterFilter { $Name -eq 'cargo' } -Times 1 -Scope It
            $global:installCopyRecords.LiteralPath | Should -Be @(
                (Join-Path $repositoryRoot 'target\release\dev.exe'),
                (Join-Path $repositoryRoot 'powershell\DevNav.psm1')
            )
            $global:installCopyRecords.Destination | Should -Be @(
                "C:\Users\Profile'Test\AppData\Local\Programs\DevNav\dev.exe",
                "C:\Users\Profile'Test\AppData\Local\Programs\DevNav\DevNav.psm1"
            )
            $global:installCopyRecords.Force | Should -Be @($true, $true)
            $global:installImportRecords.Name | Should -Be "C:\Users\Profile'Test\AppData\Local\Programs\DevNav\DevNav.psm1"
            $global:installDownloadUris.Count | Should -Be 0
            (Get-Location).Path | Should -Be $locationBefore
        }
        finally {
            if ([System.IO.File]::Exists($cargoShimPath)) { [System.IO.File]::Delete($cargoShimPath) }
            if ([System.IO.File]::Exists($cargoLogPath)) { [System.IO.File]::Delete($cargoLogPath) }
        }
    }

    It 'fails when the executable checksum entry is missing' {
        Mock Get-Content {
            param($LiteralPath, $Raw)
            if ($LiteralPath -like '*.sha256') { return 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB DevNav.psm1' }
            return ''
        }

        { & $installScriptPath -ModifyProfile:$false } | Should -Throw "*No se encontró el checksum publicado para $($global:installExpectedAsset).*"
        $global:installCopyRecords | Should -BeNullOrEmpty
        $global:installImportRecords.Count | Should -Be 0
        $global:installRemovedPaths | Should -Be $global:installDownloadPaths
    }

    It 'fails when the module checksum entry is missing' {
        Mock Get-Content {
            param($LiteralPath, $Raw)
            if ($LiteralPath -like '*.sha256') { return "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA $($global:installExpectedAsset)" }
            return ''
        }

        { & $installScriptPath -ModifyProfile:$false } | Should -Throw '*No se encontró el checksum publicado para DevNav.psm1.*'
        $global:installCopyRecords | Should -BeNullOrEmpty
        $global:installImportRecords.Count | Should -Be 0
        $global:installRemovedPaths | Should -Be $global:installDownloadPaths
    }

    It 'fails when the executable checksum does not match' {
        $global:installHashMismatchCall = 1

        { & $installScriptPath -ModifyProfile:$false } | Should -Throw "*El checksum de $($global:installExpectedAsset) no coincide*"
        $global:installCopyRecords | Should -BeNullOrEmpty
        $global:installImportRecords.Count | Should -Be 0
        $global:installRemovedPaths | Should -Be $global:installDownloadPaths
    }

    It 'fails when the module checksum does not match' {
        $global:installHashMismatchCall = 2

        { & $installScriptPath -ModifyProfile:$false } | Should -Throw '*El checksum de DevNav.psm1 no coincide*'
        $global:installCopyRecords | Should -BeNullOrEmpty
        $global:installImportRecords.Count | Should -Be 0
        $global:installRemovedPaths | Should -Be $global:installDownloadPaths
    }
}
