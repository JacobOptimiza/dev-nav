BeforeAll {
    $repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $modulePath = Join-Path $repositoryRoot 'powershell\DevNav.psm1'
    $testLocalAppData = Join-Path ([System.IO.Path]::GetTempPath()) ('devnav-pester-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $testLocalAppData -Force | Out-Null
        $previousLocalAppData = $env:LOCALAPPDATA
        $env:LOCALAPPDATA = $testLocalAppData
        Import-Module $modulePath -Force
    $devModule = Get-Module | Where-Object { $_.Path -eq $modulePath } | Select-Object -First 1
}

AfterAll {
    $env:LOCALAPPDATA = $previousLocalAppData
    Remove-Item -LiteralPath $testLocalAppData -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'DevNav PowerShell module' {
    It 'exports the public commands and dev alias' {
        (Get-Command dev).CommandType | Should -Be 'Alias'
        (Get-Command Set-DevRoot).CommandType | Should -Be 'Function'
        (Get-Command Set-DevUpdateCheck).CommandType | Should -Be 'Function'
    }

    It 'round-trips startup root and update preference without path leakage' {
        Set-DevRoot -Path $HOME
        Set-DevUpdateCheck -Enabled $false

        (Get-DevRoot) | Should -Be ([System.IO.Path]::GetFullPath($HOME))
        $configPath = Join-Path $testLocalAppData 'DevNav\config.tsv'
        (Get-Content -LiteralPath $configPath) | Should -Contain "check_updates`tfalse"
        $configLines = @(Get-Content -LiteralPath $configPath)
        ($configLines | Where-Object { $_ -match '^root\t' }) | Should -Not -BeNullOrEmpty
    }

    It 'does not reload its own module during an update' {
        $source = Get-Content -LiteralPath $modulePath -Raw
        $source | Should -Not -Match 'Import-Module\s+\$installedModule'
        $source | Should -Match '\$script:DevNavRestartRequired'
        $source | Should -Match '\$script:DevNavUpdateCompleted'
        $source | Should -Match '\$backupExecutable'
        $source | Should -Match 'El ejecutable actualizado no corresponde a v\$latestText'
    }
}

Describe 'DevNav updater lifecycle' {
    BeforeAll {
        $sourceRoot = Join-Path $testLocalAppData 'update-source'
        $fixtureRoot = Join-Path $testLocalAppData 'update-fixture'
        New-Item -ItemType Directory -Path $sourceRoot -Force | Out-Null
        New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null
        cargo build --quiet --manifest-path (Join-Path $repositoryRoot 'Cargo.toml')
        $sourceBinary = Join-Path $repositoryRoot 'target\debug\dev.exe'
        Copy-Item -LiteralPath $sourceBinary -Destination (Join-Path $sourceRoot 'dev-windows-x86_64.exe') -Force
        Copy-Item -LiteralPath $modulePath -Destination (Join-Path $sourceRoot 'DevNav.psm1') -Force
        $binaryHash = (Get-FileHash (Join-Path $sourceRoot 'dev-windows-x86_64.exe') -Algorithm SHA256).Hash
        $moduleHash = (Get-FileHash (Join-Path $sourceRoot 'DevNav.psm1') -Algorithm SHA256).Hash
        "$binaryHash  dev-windows-x86_64.exe`n$moduleHash  DevNav.psm1" | Set-Content (Join-Path $sourceRoot 'SHA256SUMS.txt')
        Copy-Item (Join-Path $sourceRoot '*') $fixtureRoot -Force
        $release = [pscustomobject]@{
            tag_name = 'v0.9.5'
            assets = @(
                [pscustomobject]@{name = 'dev-windows-x86_64.exe'; browser_download_url = 'https://example.test/dev-windows-x86_64.exe'},
                [pscustomobject]@{name = 'DevNav.psm1'; browser_download_url = 'https://example.test/DevNav.psm1'},
                [pscustomobject]@{name = 'SHA256SUMS.txt'; browser_download_url = 'https://example.test/SHA256SUMS.txt'}
            )
        }
        $global:DevNavTestSourceRoot = $sourceRoot
        $global:DevNavTestRelease = $release
    }

    BeforeEach {
        Remove-Item -LiteralPath $sourceRoot -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Path $sourceRoot -Force | Out-Null
        Copy-Item (Join-Path $fixtureRoot '*') $sourceRoot -Force
        $installRoot = Join-Path $testLocalAppData 'Programs\DevNav'
        Remove-Item -LiteralPath $installRoot -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Path $installRoot -Force | Out-Null
        Copy-Item (Join-Path $sourceRoot 'dev-windows-x86_64.exe') (Join-Path $installRoot 'dev.exe')
        Copy-Item (Join-Path $sourceRoot 'DevNav.psm1') (Join-Path $installRoot 'DevNav.psm1')
    }

    It 'updates an identical module and leaves no staging files' {
        $devModule.Invoke({
            Mock Get-DevInstalledVersion { [version]'0.9.4' }
            Mock Get-DevLatestRelease { $global:DevNavTestRelease }
            Mock Invoke-WebRequest {
                Copy-Item (Join-Path $global:DevNavTestSourceRoot ([IO.Path]::GetFileName(([uri]$Uri).AbsolutePath))) $OutFile
            }
            Update-DevNavigator -Confirm:$false
            $script:DevNavUpdateCompleted | Should -BeTrue
            $script:DevNavRestartRequired | Should -BeFalse
        })
        Get-ChildItem $installRoot -Filter '*.new' | Should -BeNullOrEmpty
        Get-ChildItem $installRoot -Filter '*.bak' | Should -BeNullOrEmpty
    }

    It 'marks restart required when the module changes' {
        Add-Content -LiteralPath (Join-Path $sourceRoot 'DevNav.psm1') -Value "`n# update marker"
        $moduleHash = (Get-FileHash (Join-Path $sourceRoot 'DevNav.psm1') -Algorithm SHA256).Hash
        (Get-Content (Join-Path $sourceRoot 'SHA256SUMS.txt')) -replace '^[0-9A-Fa-f]+  DevNav.psm1$', "$moduleHash  DevNav.psm1" | Set-Content (Join-Path $sourceRoot 'SHA256SUMS.txt')
        $devModule.Invoke({
            Mock Get-DevInstalledVersion { [version]'0.9.4' }
            Mock Get-DevLatestRelease { $global:DevNavTestRelease }
            Mock Invoke-WebRequest {
                Copy-Item (Join-Path $global:DevNavTestSourceRoot ([IO.Path]::GetFileName(([uri]$Uri).AbsolutePath))) $OutFile
            }
            Update-DevNavigator -Confirm:$false
            $script:DevNavRestartRequired | Should -BeTrue
        })
    }

    It 'keeps the installation intact when a checksum is invalid' {
        (Get-Content (Join-Path $sourceRoot 'SHA256SUMS.txt')) -replace '^[0-9A-Fa-f]+  dev-windows-x86_64.exe$', ('0' * 64 + '  dev-windows-x86_64.exe') | Set-Content (Join-Path $sourceRoot 'SHA256SUMS.txt')
        $before = (Get-FileHash (Join-Path $installRoot 'dev.exe') -Algorithm SHA256).Hash
        $devModule.Invoke({
            Mock Get-DevInstalledVersion { [version]'0.9.4' }
            Mock Get-DevLatestRelease { $global:DevNavTestRelease }
            Mock Invoke-WebRequest {
                Copy-Item (Join-Path $global:DevNavTestSourceRoot ([IO.Path]::GetFileName(([uri]$Uri).AbsolutePath))) $OutFile
            }
            { Update-DevNavigator -Confirm:$false } | Should -Throw
        })
        (Get-FileHash (Join-Path $installRoot 'dev.exe') -Algorithm SHA256).Hash | Should -Be $before
        Get-ChildItem $installRoot -Filter '*.new' | Should -BeNullOrEmpty
        Get-ChildItem $installRoot -Filter '*.bak' | Should -BeNullOrEmpty
    }

    It 'rolls back when the downloaded executable reports the wrong version' {
        Set-Content -LiteralPath (Join-Path $sourceRoot 'dev-windows-x86_64.exe') -Value 'not an executable'
        $binaryHash = (Get-FileHash (Join-Path $sourceRoot 'dev-windows-x86_64.exe') -Algorithm SHA256).Hash
        (Get-Content (Join-Path $sourceRoot 'SHA256SUMS.txt')) -replace '^[0-9A-Fa-f]+  dev-windows-x86_64.exe$', "$binaryHash  dev-windows-x86_64.exe" | Set-Content (Join-Path $sourceRoot 'SHA256SUMS.txt')
        $before = (Get-FileHash (Join-Path $installRoot 'dev.exe') -Algorithm SHA256).Hash
        $devModule.Invoke({
            Mock Get-DevInstalledVersion { [version]'0.9.4' }
            Mock Get-DevLatestRelease { $global:DevNavTestRelease }
            Mock Invoke-WebRequest {
                Copy-Item (Join-Path $global:DevNavTestSourceRoot ([IO.Path]::GetFileName(([uri]$Uri).AbsolutePath))) $OutFile
            }
            { Update-DevNavigator -Confirm:$false } | Should -Throw
        })
        (Get-FileHash (Join-Path $installRoot 'dev.exe') -Algorithm SHA256).Hash | Should -Be $before
        Get-ChildItem $installRoot -Filter '*.new' | Should -BeNullOrEmpty
        Get-ChildItem $installRoot -Filter '*.bak' | Should -BeNullOrEmpty
    }

    It 'rolls back when the second file replacement fails' {
        $beforeExecutable = (Get-FileHash (Join-Path $installRoot 'dev.exe') -Algorithm SHA256).Hash
        $beforeModule = (Get-FileHash (Join-Path $installRoot 'DevNav.psm1') -Algorithm SHA256).Hash
        $global:DevNavMoveFailureInjected = $false
        $devModule.Invoke({
            Mock Get-DevInstalledVersion { [version]'0.9.4' }
            Mock Get-DevLatestRelease { $global:DevNavTestRelease }
            Mock Invoke-WebRequest {
                Copy-Item (Join-Path $global:DevNavTestSourceRoot ([IO.Path]::GetFileName(([uri]$Uri).AbsolutePath))) $OutFile
            }
            Mock Move-Item {
                if (-not $global:DevNavMoveFailureInjected -and $LiteralPath -like '*DevNav-*.new') {
                    $global:DevNavMoveFailureInjected = $true
                    throw 'simulated replacement failure'
                }
                Microsoft.PowerShell.Management\Move-Item -LiteralPath $LiteralPath -Destination $Destination -Force
            }
            { Update-DevNavigator -Confirm:$false } | Should -Throw
        })
        (Get-FileHash (Join-Path $installRoot 'dev.exe') -Algorithm SHA256).Hash | Should -Be $beforeExecutable
        (Get-FileHash (Join-Path $installRoot 'DevNav.psm1') -Algorithm SHA256).Hash | Should -Be $beforeModule
        Get-ChildItem $installRoot -Filter '*.new' | Should -BeNullOrEmpty
        Get-ChildItem $installRoot -Filter '*.bak' | Should -BeNullOrEmpty
    }

    It 'retries a transport failure and resumes a partial download' {
        $downloadPath = Join-Path $sourceRoot 'retry.bin'
        $global:DevNavDownloadPath = $downloadPath
        $global:DevNavDownloadAttempts = 0
        $global:DevNavResumeObserved = $false
        $devModule.Invoke({
            Mock Start-Sleep {}
            Mock Invoke-WebRequest {
                $global:DevNavDownloadAttempts++
                if ($PSBoundParameters.ContainsKey('Resume')) { $global:DevNavResumeObserved = $true }
                if ($global:DevNavDownloadAttempts -eq 1) {
                    Set-Content -LiteralPath $OutFile -Value 'partial'
                    throw [System.Net.WebException]::new('ResponseEnded')
                }
                Set-Content -LiteralPath $OutFile -Value 'complete'
            }
            Invoke-DevDownload -Uri 'https://example.test/retry.bin' -OutFile $global:DevNavDownloadPath -Attempts 3
        })
        $global:DevNavDownloadAttempts | Should -Be 2
        Get-Content -LiteralPath $downloadPath | Should -Be 'complete'
        (Get-Content -LiteralPath $modulePath -Raw) | Should -Match '\$parameters\.Resume = \$true'
    }

    It 'fails clearly after all download attempts fail' {
        $downloadPath = Join-Path $sourceRoot 'failed.bin'
        $global:DevNavDownloadPath = $downloadPath
        $global:DevNavDownloadAttempts = 0
        $devModule.Invoke({
            Mock Start-Sleep {}
            Mock Invoke-WebRequest {
                $global:DevNavDownloadAttempts++
                throw [System.Net.WebException]::new('ResponseEnded')
            }
            { Invoke-DevDownload -Uri 'https://example.test/failed.bin' -OutFile $global:DevNavDownloadPath -Attempts 3 } | Should -Throw '*tras 3 intentos*'
        })
        $global:DevNavDownloadAttempts | Should -Be 3
        Test-Path -LiteralPath $downloadPath | Should -BeFalse
    }
}
