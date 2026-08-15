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
        $cargoVersion = (Get-Content (Join-Path $repositoryRoot 'Cargo.toml') | Select-String '^version = "([0-9.]+)"$').Matches.Groups[1].Value
        $latestVersion = [version]$cargoVersion
        # Derive a strictly-lower installed version from the current release so
        # the updater path is always exercised without hardcoding a version that
        # can drift. The decrement walks patch -> minor -> major.
        $previousVersion = if ($latestVersion.Build -gt 0) {
            [version]::new($latestVersion.Major, $latestVersion.Minor, $latestVersion.Build - 1)
        }
        elseif ($latestVersion.Minor -gt 0) {
            [version]::new($latestVersion.Major, $latestVersion.Minor - 1, 0)
        }
        elseif ($latestVersion.Major -gt 0) {
            [version]::new($latestVersion.Major - 1, 0, 0)
        }
        else {
            [version]::new(0, 0, 0)
        }
        # Self-verify the fixture: the updater only runs when installed < latest,
        # so a non-strictly-lower value would make these tests silently vacuous.
        if (-not ($previousVersion -lt $latestVersion)) {
            throw "Updater fixture is invalid: previous version '$previousVersion' is not strictly lower than release version '$latestVersion' (Cargo.toml $cargoVersion)."
        }
        $release = [pscustomobject]@{
            tag_name = "v$cargoVersion"
            assets = @(
                [pscustomobject]@{name = 'dev-windows-x86_64.exe'; browser_download_url = 'https://example.test/dev-windows-x86_64.exe'},
                [pscustomobject]@{name = 'DevNav.psm1'; browser_download_url = 'https://example.test/DevNav.psm1'},
                [pscustomobject]@{name = 'SHA256SUMS.txt'; browser_download_url = 'https://example.test/SHA256SUMS.txt'}
            )
        }
        $global:DevNavTestSourceRoot = $sourceRoot
        $global:DevNavTestRelease = $release
        $global:DevNavTestPreviousVersion = $previousVersion
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
            Mock Get-DevInstalledVersion { $global:DevNavTestPreviousVersion }
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

    It 'downloads x64 release assets only from canonical GitHub URLs' {
        $global:DevNavDownloadUris = [System.Collections.Generic.List[string]]::new()
        $devModule.Invoke({
            Mock Get-DevInstalledVersion { $global:DevNavTestPreviousVersion }
            Mock Get-DevLatestRelease { $global:DevNavTestRelease }
            Mock Invoke-WebRequest {
                $global:DevNavDownloadUris.Add($Uri)
                Copy-Item (Join-Path $global:DevNavTestSourceRoot ([IO.Path]::GetFileName(([uri]$Uri).AbsolutePath))) $OutFile
            }
            Update-DevNavigator -Confirm:$false
        })
        $expectedBase = "https://github.com/JacobOptimiza/dev-nav/releases/download/v$($global:DevNavTestRelease.tag_name.TrimStart('v'))"
        $global:DevNavDownloadUris | Should -Be @(
            "$expectedBase/dev-windows-x86_64.exe",
            "$expectedBase/DevNav.psm1",
            "$expectedBase/SHA256SUMS.txt"
        )
    }

    It 'constructs the canonical ARM64 release asset URL' {
        $devModule.Invoke({
            Get-DevReleaseAssetUrl -Tag 'v0.13.0' -AssetName 'dev-windows-aarch64.exe'
        }) | Should -Be 'https://github.com/JacobOptimiza/dev-nav/releases/download/v0.13.0/dev-windows-aarch64.exe'
    }

    It 'rejects a release tag outside the supported vMAJOR.MINOR.PATCH format before downloading' {
        $invalidRelease = [pscustomobject]@{
            tag_name = 'v0.13.0-preview'
            assets = $global:DevNavTestRelease.assets
        }
        $global:DevNavInvalidRelease = $invalidRelease
        $global:DevNavDownloadAttempted = $false
        $devModule.Invoke({
            Mock Get-DevInstalledVersion { $global:DevNavTestPreviousVersion }
            Mock Get-DevLatestRelease { $global:DevNavInvalidRelease }
            Mock Invoke-WebRequest { $global:DevNavDownloadAttempted = $true }
            { Update-DevNavigator -Confirm:$false } | Should -Throw '*tag no compatible*'
        })
        $global:DevNavDownloadAttempted | Should -BeFalse
    }

    It 'ignores malicious metadata URLs and never constructs a download for an unallowlisted asset' {
        $global:DevNavDownloadUris = [System.Collections.Generic.List[string]]::new()
        $maliciousRelease = [pscustomobject]@{
            tag_name = $global:DevNavTestRelease.tag_name
            assets = @(
                [pscustomobject]@{name = 'dev-windows-x86_64.exe'; browser_download_url = 'https://evil.example/payload.exe'},
                [pscustomobject]@{name = 'DevNav.psm1'; browser_download_url = 'http://github.com/DevNav.psm1'},
                [pscustomobject]@{name = 'SHA256SUMS.txt'; browser_download_url = 'https://github.com.evil.example/SHA256SUMS.txt'},
                [pscustomobject]@{name = 'payload.exe'; browser_download_url = 'https://github.com/other/repo/releases/download/v9.9.9/payload.exe'}
            )
        }
        $global:DevNavMaliciousRelease = $maliciousRelease
        $devModule.Invoke({
            Mock Get-DevInstalledVersion { $global:DevNavTestPreviousVersion }
            Mock Get-DevLatestRelease { $global:DevNavMaliciousRelease }
            Mock Invoke-WebRequest {
                $global:DevNavDownloadUris.Add($Uri)
                Copy-Item (Join-Path $global:DevNavTestSourceRoot ([IO.Path]::GetFileName(([uri]$Uri).AbsolutePath))) $OutFile
            }
            Update-DevNavigator -Confirm:$false
            { Get-DevReleaseAssetUrl -Tag 'v0.13.0' -AssetName 'payload.exe' } | Should -Throw '*no está permitido*'
        })
        $global:DevNavDownloadUris | Should -Not -Contain 'https://evil.example/payload.exe'
        $global:DevNavDownloadUris | Should -Not -Contain 'http://github.com/DevNav.psm1'
        $global:DevNavDownloadUris | Should -Not -Contain 'https://github.com.evil.example/SHA256SUMS.txt'
        $global:DevNavDownloadUris | Should -Not -Match 'other/repo|payload.exe'
        @($global:DevNavDownloadUris | Where-Object { $_ -notmatch '^https://github\.com/JacobOptimiza/dev-nav/releases/download/v\d+\.\d+\.\d+/(dev-windows-x86_64\.exe|DevNav\.psm1|SHA256SUMS\.txt)$' }).Count | Should -Be 0
    }

    It 'marks restart required when the module changes' {
        Add-Content -LiteralPath (Join-Path $sourceRoot 'DevNav.psm1') -Value "`n# update marker"
        $moduleHash = (Get-FileHash (Join-Path $sourceRoot 'DevNav.psm1') -Algorithm SHA256).Hash
        (Get-Content (Join-Path $sourceRoot 'SHA256SUMS.txt')) -replace '^[0-9A-Fa-f]+  DevNav.psm1$', "$moduleHash  DevNav.psm1" | Set-Content (Join-Path $sourceRoot 'SHA256SUMS.txt')
        $devModule.Invoke({
            Mock Get-DevInstalledVersion { $global:DevNavTestPreviousVersion }
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
            Mock Get-DevInstalledVersion { $global:DevNavTestPreviousVersion }
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
            Mock Get-DevInstalledVersion { $global:DevNavTestPreviousVersion }
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
            Mock Get-DevInstalledVersion { $global:DevNavTestPreviousVersion }
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

Describe 'DevNav Scoop-managed installation' {
    BeforeAll {
        $scoopModuleRoot = Join-Path $testLocalAppData 'scoop-module'
        New-Item -ItemType Directory -Path $scoopModuleRoot -Force | Out-Null
        $scoopModulePath = Join-Path $scoopModuleRoot 'DevNav.psm1'
        Copy-Item -LiteralPath $modulePath -Destination $scoopModulePath
        New-Item -ItemType File -Path (Join-Path $scoopModuleRoot '.devnav-managed-by-scoop') -Force | Out-Null
        Import-Module $scoopModulePath -Force
        $scoopModule = Get-Module | Where-Object { $_.Path -eq $scoopModulePath } | Select-Object -First 1
    }

    It 'detects the marker file next to the module' {
        $scoopModule.Invoke({ Test-DevManagedInstallation }) | Should -BeTrue
        $devModule.Invoke({ Test-DevManagedInstallation }) | Should -BeFalse
    }

    It 'refuses to self-update and points to scoop update' {
        $global:DevNavScoopMessageShown = $false
        $scoopModule.Invoke({
            Mock Get-DevLatestRelease { throw 'A managed installation must not query GitHub.' }
            Mock Write-Host {
                if ($Object -match 'scoop update devnav') { $global:DevNavScoopMessageShown = $true }
            }
            Update-DevNavigator -Confirm:$false
        })
        $global:DevNavScoopMessageShown | Should -BeTrue
    }

    It 'never initializes the startup update check' {
        $scoopModule.Invoke({
            Mock Initialize-DevUpdateCheckPreference { throw 'A managed installation must not prompt for update checks.' }
            { Invoke-DevStartupUpdateCheck } | Should -Not -Throw
        })
    }

    It 'keeps the managed-installation guard wired in the module source' {
        $source = Get-Content -LiteralPath $modulePath -Raw
        $source | Should -Match '\.devnav-managed-by-scoop'
        $source | Should -Match 'scoop update devnav'
    }
}

Describe 'DevNav shortcut commands' {
    BeforeAll {
        cargo build --quiet --manifest-path (Join-Path $repositoryRoot 'Cargo.toml')
        $global:DevNavTestDevExe = (Join-Path $repositoryRoot 'target\debug\dev.exe')
        $script:shortcutConfigPath = Join-Path $testLocalAppData 'DevNav\config.tsv'

        function InvokeShortcutViaDev {
            param([string[]] $Tokens)
            $global:DevNavShortcutTokens = $Tokens
            $devModule.Invoke({
                $tokens = $global:DevNavShortcutTokens
                Mock Invoke-DevCli {
                [void]$global:DevNavCliCalls.Add(($Arguments -join '|'))
                return 0
            }
                Mock Write-Host {}
                Invoke-DevNavigator @tokens
            })
        }
    }

    BeforeEach {
        Remove-Item -LiteralPath $script:shortcutConfigPath -Force -ErrorAction SilentlyContinue
        $global:DevNavCliCalls = [System.Collections.Generic.List[string]]::new()
    }

    It 'binds slot 1 with alias and command via: dev shortcut 1 Dev "bun run dev"' {
        InvokeShortcutViaDev -Tokens 'shortcut', '1', 'Dev', 'bun run dev'
        $global:DevNavCliCalls.Count | Should -Be 1
        $global:DevNavCliCalls[0] | Should -Be '--set-shortcut|1|bun run dev|--alias|Dev'
    }

    It 'binds slot 9 with a command only via: dev shortcut 9 "cargo test"' {
        InvokeShortcutViaDev -Tokens 'shortcut', '9', 'cargo test'
        $global:DevNavCliCalls[0] | Should -Be '--set-shortcut|9|cargo test'
    }

    It 'binds an intermediate slot via: dev shortcut 5 Tests "bun test"' {
        InvokeShortcutViaDev -Tokens 'shortcut', '5', 'Tests', 'bun test'
        $global:DevNavCliCalls[0] | Should -Be '--set-shortcut|5|bun test|--alias|Tests'
    }

    It 'clears a slot via: dev shortcut 3' {
        InvokeShortcutViaDev -Tokens 'shortcut', '3'
        $global:DevNavCliCalls[0] | Should -Be '--clear-shortcut|3'
    }

    It 'rejects an index below the supported range' {
        { InvokeShortcutViaDev -Tokens 'shortcut', '0', 'cmd' } | Should -Throw
    }

    It 'rejects an index above the supported range' {
        { InvokeShortcutViaDev -Tokens 'shortcut', '10', 'cmd' } | Should -Throw
    }

    It 'rejects a non-numeric index' {
        { InvokeShortcutViaDev -Tokens 'shortcut', 'x', 'cmd' } | Should -Throw
    }

    It 'rejects too many arguments and prints usage' {
        { InvokeShortcutViaDev -Tokens 'shortcut', '1', 'a', 'b', 'c' } | Should -Throw '*Uso*'
    }

    It 'persists, overwrites and clears shortcuts through dev.exe without corrupting existing config' {
        $devModule.Invoke({
            Mock Get-DevExecutable { $global:DevNavTestDevExe }
            Mock Write-Host {}
            Set-DevRoot -Path $HOME
            Set-DevShortcut -Index 1 -Alias 'Dev' -Command 'bun run dev' -Confirm:$false
            Set-DevShortcut -Index 9 -Command 'cargo test' -Confirm:$false
        })
        $lines = Get-Content -LiteralPath $script:shortcutConfigPath
        $lines | Should -Contain "shortcut`t1`tDev`tbun run dev"
        # An empty alias still reserves its field, so the line carries two tabs.
        $lines | Should -Contain "shortcut`t9`t`tcargo test"
        ($lines | Where-Object { $_ -match '^root\t' }) | Should -Not -BeNullOrEmpty

        # Overwrite slot 1: the previous binding must be replaced, not duplicated.
        $devModule.Invoke({
            Mock Get-DevExecutable { $global:DevNavTestDevExe }
            Mock Write-Host {}
            Set-DevShortcut -Index 1 -Alias 'Tests' -Command 'cargo test' -Confirm:$false
        })
        $lines = Get-Content -LiteralPath $script:shortcutConfigPath
        $lines | Should -Contain "shortcut`t1`tTests`tcargo test"
        ($lines | Where-Object { $_ -eq "shortcut`t1`tDev`tbun run dev" }) | Should -BeNullOrEmpty

        # Clear slot 1; slot 9 and the pre-existing root must survive.
        $devModule.Invoke({
            Mock Get-DevExecutable { $global:DevNavTestDevExe }
            Mock Write-Host {}
            Remove-DevShortcut -Index 1
        })
        $lines = Get-Content -LiteralPath $script:shortcutConfigPath
        ($lines | Where-Object { $_ -match '^shortcut`t1\t' }) | Should -BeNullOrEmpty
        $lines | Should -Contain "shortcut`t9`t`tcargo test"
        ($lines | Where-Object { $_ -match '^root\t' }) | Should -Not -BeNullOrEmpty
    }

    It 'preserves special characters (spaces, percent, quotes) round-trip' {
        $devModule.Invoke({
            Mock Get-DevExecutable { $global:DevNavTestDevExe }
            Mock Write-Host {}
            Set-DevShortcut -Index 2 -Alias '100% dev' -Command 'echo "hi there"' -Confirm:$false
        })
        $lines = Get-Content -LiteralPath $script:shortcutConfigPath
        # encode(): % -> %25, tabs/newlines encoded, spaces and quotes preserved.
        $lines | Should -Contain "shortcut`t2`t100%25 dev`techo `"hi there`""
    }
}
