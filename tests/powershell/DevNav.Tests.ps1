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

Describe 'DevNav executable and installed version resolution' {
    It 'prefers the installed DevNav executable when present' {
        $moduleDirectory = Split-Path -Parent $modulePath
        $expectedInstalledExecutable = Join-Path $moduleDirectory 'dev.exe'
        $expectedDevelopmentExecutable = [System.IO.Path]::GetFullPath((Join-Path $moduleDirectory '..\target\release\dev.exe'))
        $global:DevNavExpectedInstalledExecutable = $expectedInstalledExecutable
        $global:DevNavExpectedDevelopmentExecutable = $expectedDevelopmentExecutable
        $global:DevNavTestPathRecords = [System.Collections.Generic.List[object]]::new()
        try {
            $result = $devModule.Invoke({
                Mock Test-Path {
                    param($LiteralPath, $PathType)
                    [void] $global:DevNavTestPathRecords.Add([pscustomobject]@{ LiteralPath = $LiteralPath; PathType = $PathType })
                    $LiteralPath -eq $global:DevNavExpectedInstalledExecutable
                }
                Get-DevExecutable
            })

            $result | Should -Be $expectedInstalledExecutable
            @($global:DevNavTestPathRecords).Count | Should -Be 2
            $global:DevNavTestPathRecords[0].LiteralPath | Should -Be $expectedInstalledExecutable
            $global:DevNavTestPathRecords[0].PathType | Should -Be 'Leaf'
            $global:DevNavTestPathRecords[1].LiteralPath | Should -Be $expectedInstalledExecutable
            $global:DevNavTestPathRecords[1].PathType | Should -Be 'Leaf'
        }
        finally {
            Remove-Variable DevNavExpectedInstalledExecutable, DevNavExpectedDevelopmentExecutable, DevNavTestPathRecords -Scope Global -ErrorAction SilentlyContinue
        }
    }

    It 'falls back to the development executable when the installed executable is absent' {
        $moduleDirectory = Split-Path -Parent $modulePath
        $expectedInstalledExecutable = Join-Path $moduleDirectory 'dev.exe'
        $expectedDevelopmentExecutable = [System.IO.Path]::GetFullPath((Join-Path $moduleDirectory '..\target\release\dev.exe'))
        $global:DevNavExpectedInstalledExecutable = $expectedInstalledExecutable
        $global:DevNavExpectedDevelopmentExecutable = $expectedDevelopmentExecutable
        $global:DevNavTestPathRecords = [System.Collections.Generic.List[object]]::new()
        try {
            $result = $devModule.Invoke({
                Mock Test-Path {
                    param($LiteralPath, $PathType)
                    [void] $global:DevNavTestPathRecords.Add([pscustomobject]@{ LiteralPath = $LiteralPath; PathType = $PathType })
                    $LiteralPath -eq $global:DevNavExpectedDevelopmentExecutable
                }
                Get-DevExecutable
            })

            $result | Should -Be $expectedDevelopmentExecutable
            @($global:DevNavTestPathRecords).Count | Should -Be 2
            $global:DevNavTestPathRecords[0].LiteralPath | Should -Be $expectedInstalledExecutable
            $global:DevNavTestPathRecords[0].PathType | Should -Be 'Leaf'
            $global:DevNavTestPathRecords[1].LiteralPath | Should -Be $expectedDevelopmentExecutable
            $global:DevNavTestPathRecords[1].PathType | Should -Be 'Leaf'
        }
        finally {
            Remove-Variable DevNavExpectedInstalledExecutable, DevNavExpectedDevelopmentExecutable, DevNavTestPathRecords -Scope Global -ErrorAction SilentlyContinue
        }
    }

    It 'reports an English error when no DevNav executable exists' {
        $moduleDirectory = Split-Path -Parent $modulePath
        $global:DevNavExpectedInstalledExecutable = Join-Path $moduleDirectory 'dev.exe'
        $global:DevNavExpectedDevelopmentExecutable = [System.IO.Path]::GetFullPath((Join-Path $moduleDirectory '..\target\release\dev.exe'))
        try {
            $devModule.Invoke({
                Mock Test-Path { $false }
                Mock Get-DevLanguage { 'en-US' }
                { Get-DevExecutable } | Should -Throw 'dev.exe was not found. Run install.ps1 from the DevNav repository root.'
            })
        }
        finally {
            Remove-Variable DevNavExpectedInstalledExecutable, DevNavExpectedDevelopmentExecutable -Scope Global -ErrorAction SilentlyContinue
        }
    }

    It 'reports a Spanish error when no DevNav executable exists' {
        $moduleDirectory = Split-Path -Parent $modulePath
        $global:DevNavExpectedInstalledExecutable = Join-Path $moduleDirectory 'dev.exe'
        $global:DevNavExpectedDevelopmentExecutable = [System.IO.Path]::GetFullPath((Join-Path $moduleDirectory '..\target\release\dev.exe'))
        try {
            $devModule.Invoke({
                Mock Test-Path { $false }
                Mock Get-DevLanguage { 'es-ES' }
                { Get-DevExecutable } | Should -Throw 'No se encuentra dev.exe. Ejecuta install.ps1 desde la raíz de DevNav.'
            })
        }
        finally {
            Remove-Variable DevNavExpectedInstalledExecutable, DevNavExpectedDevelopmentExecutable -Scope Global -ErrorAction SilentlyContinue
        }
    }

    It 'parses a valid installed DevNav version from a controlled executable' {
        $shimPath = Join-Path ([System.IO.Path]::GetTempPath()) ('devnav-version-' + [guid]::NewGuid().ToString('N') + '.cmd')
        $logPath = Join-Path ([System.IO.Path]::GetTempPath()) ('devnav-version-' + [guid]::NewGuid().ToString('N') + '.log')
        $global:DevNavTestVersionShim = $shimPath
        try {
            @("@echo off", "echo %*>>`"$logPath`"", 'echo dev-nav 1.2.3', 'exit /b 0') | Set-Content -LiteralPath $shimPath -Encoding ascii
            $result = $devModule.Invoke({
                Mock Get-DevExecutable { $global:DevNavTestVersionShim }
                Get-DevInstalledVersion
            })

            $result | Should -Be ([version]'1.2.3')
            (Get-Content -LiteralPath $logPath -Raw).Trim() | Should -Be '--version'
        }
        finally {
            Remove-Item -LiteralPath $shimPath, $logPath -Force -ErrorAction SilentlyContinue
            Remove-Variable DevNavTestVersionShim -Scope Global -ErrorAction SilentlyContinue
        }
    }

    It 'rejects invalid installed DevNav version output' {
        $shimPath = Join-Path ([System.IO.Path]::GetTempPath()) ('devnav-version-' + [guid]::NewGuid().ToString('N') + '.cmd')
        $global:DevNavTestVersionShim = $shimPath
        try {
            @('@echo off', 'echo dev-nav invalid', 'exit /b 0') | Set-Content -LiteralPath $shimPath -Encoding ascii
            $devModule.Invoke({
                Mock Get-DevExecutable { $global:DevNavTestVersionShim }
                Mock Get-DevLanguage { 'en-US' }
                { Get-DevInstalledVersion } | Should -Throw 'Unable to determine the installed DevNav version.'
            })
        }
        finally {
            Remove-Item -LiteralPath $shimPath -Force -ErrorAction SilentlyContinue
            Remove-Variable DevNavTestVersionShim -Scope Global -ErrorAction SilentlyContinue
        }
    }

    It 'rejects a nonzero installed DevNav version command' {
        $shimPath = Join-Path ([System.IO.Path]::GetTempPath()) ('devnav-version-' + [guid]::NewGuid().ToString('N') + '.cmd')
        $global:DevNavTestVersionShim = $shimPath
        try {
            @('@echo off', 'echo dev-nav 1.2.3', 'exit /b 7') | Set-Content -LiteralPath $shimPath -Encoding ascii
            $devModule.Invoke({
                Mock Get-DevExecutable { $global:DevNavTestVersionShim }
                Mock Get-DevLanguage { 'es-ES' }
                { Get-DevInstalledVersion } | Should -Throw 'No se pudo determinar la versión instalada de DevNav.'
            })
        }
        finally {
            Remove-Item -LiteralPath $shimPath -Force -ErrorAction SilentlyContinue
            Remove-Variable DevNavTestVersionShim -Scope Global -ErrorAction SilentlyContinue
        }
    }
}

Describe 'DevNav configuration and deterministic language behavior' {
    BeforeEach {
        $configPath = Join-Path $testLocalAppData 'DevNav\config.tsv'
        Remove-Item -LiteralPath $configPath -Force -ErrorAction SilentlyContinue
    }

    It 'returns null when the requested configuration does not exist' {
        $result = $devModule.Invoke({ Get-DevConfigValue -Name 'language' })
        $result | Should -BeNullOrEmpty
    }

    It 'returns null when the requested key is absent from an existing configuration' {
        New-Item -ItemType Directory -Path (Split-Path -Parent $configPath) -Force | Out-Null
        "root`tC:\fixture" | Set-Content -LiteralPath $configPath -Encoding utf8NoBOM
        $result = $devModule.Invoke({ Get-DevConfigValue -Name 'language' })
        $result | Should -BeNullOrEmpty
    }

    It 'reads only the requested configuration value' {
        New-Item -ItemType Directory -Path (Split-Path -Parent $configPath) -Force | Out-Null
        @("root`tC:\fixture", "language`tes-ES", "check_updates`ttrue") | Set-Content -LiteralPath $configPath -Encoding utf8NoBOM
        $result = $devModule.Invoke({ Get-DevConfigValue -Name 'language' })
        $result | Should -Be 'es-ES'
    }

    It 'upserts a configuration value without losing unrelated entries' {
        New-Item -ItemType Directory -Path (Split-Path -Parent $configPath) -Force | Out-Null
        @("root`tC:\fixture", "language`tes-ES", "check_updates`tfalse") | Set-Content -LiteralPath $configPath -Encoding utf8NoBOM
        $devModule.Invoke({ Set-DevConfigValue -Name 'language' -Value 'en-US' -Confirm:$false })
        $lines = @(Get-Content -LiteralPath $configPath)
        @($lines | Where-Object { $_ -eq "language`ten-US" }).Count | Should -Be 1
        @($lines | Where-Object { $_ -eq "language`tes-ES" }).Count | Should -Be 0
        $lines | Should -Contain "root`tC:\fixture"
        $lines | Should -Contain "check_updates`tfalse"
    }

    It 'honors WhatIf when setting a configuration value' {
        New-Item -ItemType Directory -Path (Split-Path -Parent $configPath) -Force | Out-Null
        @("root`tC:\fixture", "language`tes-ES") | Set-Content -LiteralPath $configPath -Encoding utf8NoBOM
        $before = [System.IO.File]::ReadAllText($configPath)
        $devModule.Invoke({ Set-DevConfigValue -Name 'language' -Value 'en-US' -WhatIf })
        [System.IO.File]::ReadAllText($configPath) | Should -Be $before
    }

    It 'returns a saved supported DevNav language' {
        New-Item -ItemType Directory -Path (Split-Path -Parent $configPath) -Force | Out-Null
        "language`tes-ES" | Set-Content -LiteralPath $configPath -Encoding utf8NoBOM
        $devModule.Invoke({ Get-DevLanguage }) | Should -Be 'es-ES'
    }

    It 'treats an unsupported saved language as unset' {
        New-Item -ItemType Directory -Path (Split-Path -Parent $configPath) -Force | Out-Null
        "language`tfr-FR" | Set-Content -LiteralPath $configPath -Encoding utf8NoBOM
        $devModule.Invoke({ Get-DevLanguage }) | Should -BeNullOrEmpty
    }

    It 'canonicalizes en to en-US and invokes the DevNav CLI' {
        $global:DevNavLanguageCliArguments = [System.Collections.Generic.List[object]]::new()
        $global:DevNavLanguageMessages = [System.Collections.Generic.List[string]]::new()
        try {
            $devModule.Invoke({
                Mock Invoke-DevCli { [void] $global:DevNavLanguageCliArguments.Add(@($Arguments)); 0 }
                Mock Write-Host { [void] $global:DevNavLanguageMessages.Add([string]$Object) }
                Set-DevLanguage -Language en -Confirm:$false
            })
            @($global:DevNavLanguageCliArguments).Count | Should -Be 1
            @($global:DevNavLanguageCliArguments[0]) | Should -Be @('--set-language', 'en-US')
            $global:DevNavLanguageMessages | Should -Contain 'Language: English (en-US)'
        }
        finally {
            Remove-Variable DevNavLanguageCliArguments, DevNavLanguageMessages -Scope Global -ErrorAction SilentlyContinue
        }
    }

    It 'canonicalizes es to es-ES and invokes the DevNav CLI' {
        $global:DevNavLanguageCliArguments = [System.Collections.Generic.List[object]]::new()
        $global:DevNavLanguageMessages = [System.Collections.Generic.List[string]]::new()
        try {
            $devModule.Invoke({
                Mock Invoke-DevCli { [void] $global:DevNavLanguageCliArguments.Add(@($Arguments)); 0 }
                Mock Write-Host { [void] $global:DevNavLanguageMessages.Add([string]$Object) }
                Set-DevLanguage -Language es -Confirm:$false
            })
            @($global:DevNavLanguageCliArguments).Count | Should -Be 1
            @($global:DevNavLanguageCliArguments[0]) | Should -Be @('--set-language', 'es-ES')
            $global:DevNavLanguageMessages | Should -Contain 'Idioma: Español (es-ES)'
        }
        finally {
            Remove-Variable DevNavLanguageCliArguments, DevNavLanguageMessages -Scope Global -ErrorAction SilentlyContinue
        }
    }

    It 'reports an English error when saving the language fails' {
        $devModule.Invoke({
            Mock Invoke-DevCli { 9 }
            { Set-DevLanguage -Language en -Confirm:$false } | Should -Throw "Could not save language 'en-US'."
        })
    }

    It 'reports a Spanish error when saving the language fails' {
        $devModule.Invoke({
            Mock Invoke-DevCli { 9 }
            { Set-DevLanguage -Language es -Confirm:$false } | Should -Throw "No se pudo guardar el idioma 'es-ES'."
        })
    }

    It 'honors WhatIf when setting the DevNav language' {
        $global:DevNavLanguageCliCalls = 0
        try {
            $devModule.Invoke({
                Mock Invoke-DevCli { $global:DevNavLanguageCliCalls++; 0 }
                Mock Write-Host {}
                Set-DevLanguage -Language en -WhatIf
            })
            $global:DevNavLanguageCliCalls | Should -Be 0
        }
        finally {
            Remove-Variable DevNavLanguageCliCalls -Scope Global -ErrorAction SilentlyContinue
        }
    }

    It 'persists enabled startup update checks with the English confirmation' {
        $global:DevNavLanguageMessages = [System.Collections.Generic.List[string]]::new()
        try {
            $devModule.Invoke({
                Mock Get-DevLanguage { 'en-US' }
                Mock Write-Host { [void] $global:DevNavLanguageMessages.Add([string]$Object) }
                Set-DevUpdateCheck -Enabled $true -Confirm:$false
            })
            (Get-Content -LiteralPath $configPath) | Should -Contain "check_updates`ttrue"
            $global:DevNavLanguageMessages | Should -Contain 'Startup update checks: enabled.'
        }
        finally {
            Remove-Variable DevNavLanguageMessages -Scope Global -ErrorAction SilentlyContinue
        }
    }

    It 'persists disabled startup update checks with the Spanish confirmation' {
        $global:DevNavLanguageMessages = [System.Collections.Generic.List[string]]::new()
        try {
            $devModule.Invoke({
                Mock Get-DevLanguage { 'es-ES' }
                Mock Write-Host { [void] $global:DevNavLanguageMessages.Add([string]$Object) }
                Set-DevUpdateCheck -Enabled $false -Confirm:$false
            })
            (Get-Content -LiteralPath $configPath) | Should -Contain "check_updates`tfalse"
            $global:DevNavLanguageMessages | Should -Contain 'Comprobación de actualizaciones al iniciar: desactivada.'
        }
        finally {
            Remove-Variable DevNavLanguageMessages -Scope Global -ErrorAction SilentlyContinue
        }
    }

    It 'honors WhatIf when changing startup update checks' {
        New-Item -ItemType Directory -Path (Split-Path -Parent $configPath) -Force | Out-Null
        "check_updates`tfalse" | Set-Content -LiteralPath $configPath -Encoding utf8NoBOM
        $before = [System.IO.File]::ReadAllText($configPath)
        $devModule.Invoke({
            Mock Get-DevLanguage { 'en-US' }
            Mock Write-Host {}
            Set-DevUpdateCheck -Enabled $true -WhatIf
        })
        [System.IO.File]::ReadAllText($configPath) | Should -Be $before
    }

    It 'prefers a supported native system language detection result' {
        $shimPath = Join-Path ([System.IO.Path]::GetTempPath()) ('devnav-language-' + [guid]::NewGuid().ToString('N') + '.cmd')
        $logPath = Join-Path ([System.IO.Path]::GetTempPath()) ('devnav-language-' + [guid]::NewGuid().ToString('N') + '.log')
        $global:DevNavLanguageShim = $shimPath
        try {
            @('@echo off', "echo %*>>`"$logPath`"", 'echo es-ES', 'exit /b 0') | Set-Content -LiteralPath $shimPath -Encoding ascii
            $result = $devModule.Invoke({
                Mock Get-DevInstalledVersion { [version]'0.10.0' }
                Mock Get-DevExecutable { $global:DevNavLanguageShim }
                Mock Get-UICulture { throw 'UI culture should not be consulted after supported native detection.' }
                Get-DevSystemLanguage
            })
            $result | Should -Be 'es-ES'
            (Get-Content -LiteralPath $logPath -Raw).Trim() | Should -Be '--detect-language'
        }
        finally {
            Remove-Item -LiteralPath $shimPath, $logPath -Force -ErrorAction SilentlyContinue
            Remove-Variable DevNavLanguageShim -Scope Global -ErrorAction SilentlyContinue
        }
    }

    It 'falls back to Spanish UI culture when native detection is unsupported' {
        $shimPath = Join-Path ([System.IO.Path]::GetTempPath()) ('devnav-language-' + [guid]::NewGuid().ToString('N') + '.cmd')
        $logPath = Join-Path ([System.IO.Path]::GetTempPath()) ('devnav-language-' + [guid]::NewGuid().ToString('N') + '.log')
        $global:DevNavLanguageShim = $shimPath
        try {
            @('@echo off', "echo %*>>`"$logPath`"", 'echo fr-FR', 'exit /b 0') | Set-Content -LiteralPath $shimPath -Encoding ascii
            $result = $devModule.Invoke({
                Mock Get-DevInstalledVersion { [version]'0.10.0' }
                Mock Get-DevExecutable { $global:DevNavLanguageShim }
                Mock Get-UICulture { [pscustomobject]@{ Name = 'es-MX' } }
                Get-DevSystemLanguage
            })
            $result | Should -Be 'es-ES'
            (Get-Content -LiteralPath $logPath -Raw).Trim() | Should -Be '--detect-language'
        }
        finally {
            Remove-Item -LiteralPath $shimPath, $logPath -Force -ErrorAction SilentlyContinue
            Remove-Variable DevNavLanguageShim -Scope Global -ErrorAction SilentlyContinue
        }
    }

    It 'skips native language detection for DevNav versions older than 0.10.0' {
        $global:DevNavExecutableCalls = 0
        try {
            $result = $devModule.Invoke({
                Mock Get-DevInstalledVersion { [version]'0.9.9' }
                Mock Get-DevExecutable { $global:DevNavExecutableCalls++; 'unused' }
                Mock Get-UICulture { [pscustomobject]@{ Name = 'en-GB' } }
                Get-DevSystemLanguage
            })
            $result | Should -Be 'en-US'
            $global:DevNavExecutableCalls | Should -Be 0
        }
        finally {
            Remove-Variable DevNavExecutableCalls -Scope Global -ErrorAction SilentlyContinue
        }
    }

    It 'defaults to en-US for an unsupported Windows UI culture' {
        $global:DevNavExecutableCalls = 0
        try {
            $result = $devModule.Invoke({
                Mock Get-DevInstalledVersion { [version]'0.9.9' }
                Mock Get-DevExecutable { $global:DevNavExecutableCalls++; 'unused' }
                Mock Get-UICulture { [pscustomobject]@{ Name = 'fr-FR' } }
                Get-DevSystemLanguage
            })
            $result | Should -Be 'en-US'
            $global:DevNavExecutableCalls | Should -Be 0
        }
        finally {
            Remove-Variable DevNavExecutableCalls -Scope Global -ErrorAction SilentlyContinue
        }
    }

    It 'defaults to en-US when system language detection throws' {
        $global:DevNavVerboseMessages = [System.Collections.Generic.List[string]]::new()
        try {
            $result = $devModule.Invoke({
                Mock Get-DevInstalledVersion { throw 'simulated detection failure' }
                Mock Write-Verbose { [void] $global:DevNavVerboseMessages.Add([string]$Message) }
                Get-DevSystemLanguage
            })
            $result | Should -Be 'en-US'
            ($global:DevNavVerboseMessages -join "`n") | Should -Match 'System language detection failed:.*simulated detection failure'
        }
        finally {
            Remove-Variable DevNavVerboseMessages -Scope Global -ErrorAction SilentlyContinue
        }
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
