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

Describe 'DevNav root fallback and validation behavior' {
    BeforeEach {
        $configPath = Join-Path $testLocalAppData 'DevNav\config.tsv'
        Remove-Item -LiteralPath $configPath -Force -ErrorAction SilentlyContinue
    }

    It 'uses DEV_HOME when no startup root is configured' {
        $fallbackPath = Join-Path $testLocalAppData 'dev-home-fallback'
        New-Item -ItemType Directory -Path $fallbackPath -Force | Out-Null
        $previousDevHome = [System.Environment]::GetEnvironmentVariable('DEV_HOME', 'Process')
        try {
            $env:DEV_HOME = $fallbackPath
            $result = $devModule.Invoke({
                Mock Get-DevConfigValue { $null }
                Get-DevRoot
            })
            $result | Should -Be $fallbackPath
        }
        finally {
            if ($null -eq $previousDevHome) { Remove-Item Env:DEV_HOME -ErrorAction SilentlyContinue }
            else { $env:DEV_HOME = $previousDevHome }
            Remove-Item -LiteralPath $fallbackPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'falls back to HOME when no startup root or DEV_HOME is configured' {
        $previousDevHome = [System.Environment]::GetEnvironmentVariable('DEV_HOME', 'Process')
        try {
            Remove-Item Env:DEV_HOME -ErrorAction SilentlyContinue
            $result = $devModule.Invoke({
                Mock Get-DevConfigValue { $null }
                Get-DevRoot
            })
            $result | Should -Be $HOME
        }
        finally {
            if ($null -eq $previousDevHome) { Remove-Item Env:DEV_HOME -ErrorAction SilentlyContinue }
            else { $env:DEV_HOME = $previousDevHome }
        }
    }

    It 'rejects a startup root that resolves to a file' {
        $filePath = Join-Path $testLocalAppData ('root-file-' + [guid]::NewGuid().ToString('N') + '.txt')
        New-Item -ItemType File -Path $filePath -Force | Out-Null
        $resolvedPath = (Resolve-Path -LiteralPath $filePath).Path
        $global:DevNavRootFile = $filePath
        $global:DevNavRootResolved = $resolvedPath
        $global:DevNavRootPersistCalls = 0
        try {
            $devModule.Invoke({
                Mock Set-DevConfigValue { $global:DevNavRootPersistCalls++ }
                { Set-DevRoot -Path $global:DevNavRootFile -Confirm:$false } | Should -Throw "La ruta no es una carpeta: $global:DevNavRootResolved"
            })
            $global:DevNavRootPersistCalls | Should -Be 0
        }
        finally {
            Remove-Item -LiteralPath $filePath -Force -ErrorAction SilentlyContinue
            Remove-Variable DevNavRootFile, DevNavRootResolved, DevNavRootPersistCalls -Scope Global -ErrorAction SilentlyContinue
        }
    }

    It 'does not persist the startup root with WhatIf' {
        $directoryPath = Join-Path $testLocalAppData ('root-whatif-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $directoryPath -Force | Out-Null
        $global:DevNavRootWhatIf = $directoryPath
        $global:DevNavRootPersistCalls = 0
        $global:DevNavRootConfirmationCalls = 0
        try {
            $devModule.Invoke({
                Mock Set-DevConfigValue { $global:DevNavRootPersistCalls++ }
                Mock Write-Host { $global:DevNavRootConfirmationCalls++ }
                Set-DevRoot -Path $global:DevNavRootWhatIf -WhatIf
            })
            $global:DevNavRootPersistCalls | Should -Be 0
            $global:DevNavRootConfirmationCalls | Should -Be 0
        }
        finally {
            Remove-Item -LiteralPath $directoryPath -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Variable DevNavRootWhatIf, DevNavRootPersistCalls, DevNavRootConfirmationCalls -Scope Global -ErrorAction SilentlyContinue
        }
    }

    It 'reports the English confirmation when saving the startup root' {
        $directoryPath = Join-Path $testLocalAppData ('root-english-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $directoryPath -Force | Out-Null
        $resolvedPath = (Resolve-Path -LiteralPath $directoryPath).Path
        $global:DevNavRootDirectory = $directoryPath
        $global:DevNavRootMessages = [System.Collections.Generic.List[string]]::new()
        try {
            $devModule.Invoke({
                Mock Get-DevLanguage { 'en-US' }
                Mock Write-Host { [void]$global:DevNavRootMessages.Add([string]$Object) }
                Set-DevRoot -Path $global:DevNavRootDirectory -Confirm:$false
            })
            $global:DevNavRootMessages | Should -Contain "Startup folder saved: $resolvedPath"
            $devModule.Invoke({ Get-DevRoot }) | Should -Be $resolvedPath
            (Split-Path -Parent $configPath) | Should -Be (Join-Path $testLocalAppData 'DevNav')
        }
        finally {
            Remove-Item -LiteralPath $directoryPath -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Variable DevNavRootDirectory, DevNavRootMessages -Scope Global -ErrorAction SilentlyContinue
        }
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

    It 'does not query versions or releases when an update is skipped with WhatIf' {
        $global:DevNavWhatIfCalls = @{ Installed = 0; Release = 0; Download = 0 }
        try {
            $devModule.Invoke({
                Mock Test-DevManagedInstallation { $false }
                Mock Get-DevInstalledVersion { $global:DevNavWhatIfCalls.Installed++ }
                Mock Get-DevLatestRelease { $global:DevNavWhatIfCalls.Release++ }
                Mock Invoke-DevDownload { $global:DevNavWhatIfCalls.Download++ }
                Update-DevNavigator -WhatIf
            })
            $global:DevNavWhatIfCalls.Installed | Should -Be 0
            $global:DevNavWhatIfCalls.Release | Should -Be 0
            $global:DevNavWhatIfCalls.Download | Should -Be 0
        }
        finally {
            Remove-Variable DevNavWhatIfCalls -Scope Global -ErrorAction SilentlyContinue
        }
    }

    It 'reports the English no-op when the installed version is already current' {
        $global:DevNavCurrentMessages = [System.Collections.Generic.List[string]]::new()
        $global:DevNavCurrentDownloadCalls = 0
        try {
            $devModule.Invoke({
                Mock Test-DevManagedInstallation { $false }
                Mock Get-DevInstalledVersion { [version]'0.13.0' }
                Mock Get-DevLatestRelease {
                    [pscustomobject]@{ tag_name = 'v0.13.0'; assets = @() }
                }
                Mock Get-DevLanguage { 'en-US' }
                Mock Write-Host { [void]$global:DevNavCurrentMessages.Add([string]$Object) }
                Mock Invoke-DevDownload { $global:DevNavCurrentDownloadCalls++ }
                Update-DevNavigator -Confirm:$false
            })
            $global:DevNavCurrentMessages | Should -Contain 'Installed version: v0.13.0'
            $global:DevNavCurrentMessages | Should -Contain 'Checking the latest published version...'
            $global:DevNavCurrentMessages | Should -Contain 'Latest published: v0.13.0'
            $global:DevNavCurrentMessages | Should -Contain 'You already have the latest version (v0.13.0). No update is needed.'
            $global:DevNavCurrentDownloadCalls | Should -Be 0
        }
        finally {
            Remove-Variable DevNavCurrentMessages, DevNavCurrentDownloadCalls -Scope Global -ErrorAction SilentlyContinue
        }
    }

    It 'reports the Spanish no-op when the installed version is newer than the latest release' {
        $global:DevNavNewerMessages = [System.Collections.Generic.List[string]]::new()
        $global:DevNavNewerDownloadCalls = 0
        try {
            $devModule.Invoke({
                Mock Test-DevManagedInstallation { $false }
                Mock Get-DevInstalledVersion { [version]'0.14.0' }
                Mock Get-DevLatestRelease {
                    [pscustomobject]@{ tag_name = 'v0.13.0'; assets = @() }
                }
                Mock Get-DevLanguage { 'es-ES' }
                Mock Write-Host { [void]$global:DevNavNewerMessages.Add([string]$Object) }
                Mock Invoke-DevDownload { $global:DevNavNewerDownloadCalls++ }
                Update-DevNavigator -Confirm:$false
            })
            $global:DevNavNewerMessages | Should -Contain 'Versión instalada: v0.14.0'
            $global:DevNavNewerMessages | Should -Contain 'Comprobando la última versión publicada...'
            $global:DevNavNewerMessages | Should -Contain 'Última publicada: v0.13.0'
            $global:DevNavNewerMessages | Should -Contain 'La versión instalada es más reciente que la última release publicada; no se modificó nada.'
            $global:DevNavNewerDownloadCalls | Should -Be 0
        }
        finally {
            Remove-Variable DevNavNewerMessages, DevNavNewerDownloadCalls -Scope Global -ErrorAction SilentlyContinue
        }
    }

    It 'rejects a release missing DevNav.psm1 before downloading anything' {
        $global:DevNavMissingModuleDownloadCalls = 0
        try {
            $devModule.Invoke({
                Mock Test-DevManagedInstallation { $false }
                Mock Get-DevInstalledVersion { [version]'0.12.0' }
                Mock Get-DevLatestRelease {
                    [pscustomobject]@{
                        tag_name = 'v0.13.0'
                        assets = @(
                            [pscustomobject]@{ name = 'dev-windows-x86_64.exe' }
                            [pscustomobject]@{ name = 'dev-windows-aarch64.exe' }
                            [pscustomobject]@{ name = 'SHA256SUMS.txt' }
                        )
                    }
                }
                Mock Invoke-DevDownload { $global:DevNavMissingModuleDownloadCalls++ }
                { Update-DevNavigator -Confirm:$false } | Should -Throw 'La release v0.13.0 no contiene DevNav.psm1.'
            })
            $global:DevNavMissingModuleDownloadCalls | Should -Be 0
        }
        finally {
            Remove-Variable DevNavMissingModuleDownloadCalls -Scope Global -ErrorAction SilentlyContinue
        }
    }

    It 'requests the latest GitHub release with the expected updater headers' {
        $global:DevNavLatestReleaseRequest = $null
        $global:DevNavLatestReleaseResponse = [pscustomobject]@{ tag_name = 'v9.8.7' }
        try {
            $result = $devModule.Invoke({
                Mock Invoke-RestMethod {
                    param($Uri, $ConnectionTimeoutSeconds, $Headers)
                    $global:DevNavLatestReleaseRequest = [pscustomobject]@{
                        Uri = $Uri
                        TimeoutSec = $ConnectionTimeoutSeconds
                        Headers = $Headers
                    }
                    $global:DevNavLatestReleaseResponse
                }
                Get-DevLatestRelease -TimeoutSeconds 7
            })
            $result | Should -Be $global:DevNavLatestReleaseResponse
            $global:DevNavLatestReleaseRequest.Uri | Should -Be 'https://api.github.com/repos/JacobOptimiza/dev-nav/releases/latest'
            $global:DevNavLatestReleaseRequest.TimeoutSec | Should -Be 7
            $global:DevNavLatestReleaseRequest.Headers.Accept | Should -Be 'application/vnd.github+json'
            $global:DevNavLatestReleaseRequest.Headers.'User-Agent' | Should -Be 'DevNav-Updater'
            $devModule.Invoke({ Should -Invoke Invoke-RestMethod -Times 1 -Scope It })
        }
        finally {
            Remove-Variable DevNavLatestReleaseRequest, DevNavLatestReleaseResponse -Scope Global -ErrorAction SilentlyContinue
        }
    }

    It 'returns true from a saved enabled update-check preference without prompting' {
        $configPath = Join-Path $testLocalAppData 'DevNav\config.tsv'
        New-Item -ItemType Directory -Path (Split-Path -Parent $configPath) -Force | Out-Null
        Set-Content -LiteralPath $configPath -Value "check_updates`ttrue" -Encoding utf8NoBOM
        $global:DevNavPreferenceCalls = @{ ReadHost = 0; WriteHost = 0; Language = 0; SetConfig = 0 }
        try {
            $result = $devModule.Invoke({
                Mock Read-Host { $global:DevNavPreferenceCalls.ReadHost++ }
                Mock Write-Host { $global:DevNavPreferenceCalls.WriteHost++ }
                Mock Get-DevLanguage { $global:DevNavPreferenceCalls.Language++ }
                Mock Set-DevConfigValue { $global:DevNavPreferenceCalls.SetConfig++ }
                Initialize-DevUpdateCheckPreference
            })
            $result | Should -BeTrue
            $global:DevNavPreferenceCalls.ReadHost | Should -Be 0
            $global:DevNavPreferenceCalls.WriteHost | Should -Be 0
            $global:DevNavPreferenceCalls.Language | Should -Be 0
            $global:DevNavPreferenceCalls.SetConfig | Should -Be 0
        }
        finally {
            Remove-Item -LiteralPath $configPath -Force -ErrorAction SilentlyContinue
            Remove-Variable DevNavPreferenceCalls -Scope Global -ErrorAction SilentlyContinue
        }
    }

    It 'returns false from a saved disabled update-check preference without prompting' {
        $configPath = Join-Path $testLocalAppData 'DevNav\config.tsv'
        New-Item -ItemType Directory -Path (Split-Path -Parent $configPath) -Force | Out-Null
        Set-Content -LiteralPath $configPath -Value "check_updates`tfalse" -Encoding utf8NoBOM
        $global:DevNavPreferenceCalls = @{ ReadHost = 0; WriteHost = 0; Language = 0; SetConfig = 0 }
        try {
            $result = $devModule.Invoke({
                Mock Read-Host { $global:DevNavPreferenceCalls.ReadHost++ }
                Mock Write-Host { $global:DevNavPreferenceCalls.WriteHost++ }
                Mock Get-DevLanguage { $global:DevNavPreferenceCalls.Language++ }
                Mock Set-DevConfigValue { $global:DevNavPreferenceCalls.SetConfig++ }
                Initialize-DevUpdateCheckPreference
            })
            $result | Should -BeFalse
            $global:DevNavPreferenceCalls.ReadHost | Should -Be 0
            $global:DevNavPreferenceCalls.WriteHost | Should -Be 0
            $global:DevNavPreferenceCalls.Language | Should -Be 0
            $global:DevNavPreferenceCalls.SetConfig | Should -Be 0
        }
        finally {
            Remove-Item -LiteralPath $configPath -Force -ErrorAction SilentlyContinue
            Remove-Variable DevNavPreferenceCalls -Scope Global -ErrorAction SilentlyContinue
        }
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

    It 'reports the English error after all download attempts fail' {
        $downloadPath = Join-Path $testLocalAppData 'failed-en.bin'
        $global:DevNavEnglishDownloadAttempts = 0
        $global:DevNavEnglishDownloadPath = $downloadPath
        try {
            $devModule.Invoke({
                Mock Get-DevLanguage { 'en-US' }
                Mock Start-Sleep {}
                Mock Invoke-WebRequest {
                    $global:DevNavEnglishDownloadAttempts++
                    throw [System.Net.WebException]::new('simulated transport failure')
                }
                { Invoke-DevDownload -Uri 'https://example.test/failed-en.bin' -OutFile $global:DevNavEnglishDownloadPath -Attempts 2 } | Should -Throw "Could not download 'https://example.test/failed-en.bin' after 2 attempts: simulated transport failure"
            })
            $global:DevNavEnglishDownloadAttempts | Should -Be 2
            $devModule.Invoke({ Should -Invoke Start-Sleep -Times 1 -Scope It })
            Test-Path -LiteralPath $downloadPath | Should -BeFalse
        }
        finally {
            Remove-Variable DevNavEnglishDownloadAttempts, DevNavEnglishDownloadPath -Scope Global -ErrorAction SilentlyContinue
        }
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

    It 'reports the English Scoop-managed update instructions without querying GitHub' {
        $global:DevNavScoopEnglishMessages = [System.Collections.Generic.List[string]]::new()
        $global:DevNavScoopLatestCalls = 0
        $global:DevNavScoopDownloadCalls = 0
        try {
            $scoopModule.Invoke({
                Mock Get-DevLanguage { 'en-US' }
                Mock Get-DevLatestRelease { $global:DevNavScoopLatestCalls++ }
                Mock Invoke-DevDownload { $global:DevNavScoopDownloadCalls++ }
                Mock Write-Host { [void]$global:DevNavScoopEnglishMessages.Add([string]$Object) }
                Update-DevNavigator -Confirm:$false
            })
            $global:DevNavScoopEnglishMessages | Should -Contain 'This installation is managed by Scoop; DevNav will not self-update.'
            $global:DevNavScoopEnglishMessages | Should -Contain 'Update it with: scoop update devnav'
            $global:DevNavScoopLatestCalls | Should -Be 0
            $global:DevNavScoopDownloadCalls | Should -Be 0
        }
        finally {
            Remove-Variable DevNavScoopEnglishMessages, DevNavScoopLatestCalls, DevNavScoopDownloadCalls -Scope Global -ErrorAction SilentlyContinue
        }
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

Describe 'DevNav shortcut failure and confirmation behavior' {
    It 'does not invoke the CLI when clearing a shortcut with WhatIf' {
        $global:DevNavShortcutCliCalls = 0
        try {
            $devModule.Invoke({
                Mock Invoke-DevCli { $global:DevNavShortcutCliCalls++; 0 }
                Set-DevShortcut -Index 3 -Clear -WhatIf
            })
            $global:DevNavShortcutCliCalls | Should -Be 0
        }
        finally {
            Remove-Variable DevNavShortcutCliCalls -Scope Global -ErrorAction SilentlyContinue
        }
    }

    It 'reports the English error when clearing a shortcut fails' {
        $global:DevNavShortcutCliArguments = [System.Collections.Generic.List[object]]::new()
        try {
            $devModule.Invoke({
                Mock Get-DevLanguage { 'en-US' }
                Mock Invoke-DevCli {
                    [void]$global:DevNavShortcutCliArguments.Add(@($Arguments))
                    7
                }
                { Set-DevShortcut -Index 3 -Clear -Confirm:$false } | Should -Throw 'Could not remove shortcut 3 (dev.exe exited with 7).'
            })
            @($global:DevNavShortcutCliArguments).Count | Should -Be 1
            @($global:DevNavShortcutCliArguments[0]) | Should -Be @('--clear-shortcut', '3')
        }
        finally {
            Remove-Variable DevNavShortcutCliArguments -Scope Global -ErrorAction SilentlyContinue
        }
    }

    It 'reports the Spanish error when clearing a shortcut fails' {
        $devModule.Invoke({
            Mock Get-DevLanguage { 'es-ES' }
            Mock Invoke-DevCli { 7 }
            { Set-DevShortcut -Index 3 -Clear -Confirm:$false } | Should -Throw 'No se pudo eliminar el atajo 3 (dev.exe salió con 7).'
        })
    }

    It 'reports the English confirmation when clearing succeeds' {
        $global:DevNavShortcutCliArguments = [System.Collections.Generic.List[object]]::new()
        $global:DevNavShortcutMessages = [System.Collections.Generic.List[string]]::new()
        try {
            $devModule.Invoke({
                Mock Get-DevLanguage { 'en-US' }
                Mock Invoke-DevCli {
                    [void]$global:DevNavShortcutCliArguments.Add(@($Arguments))
                    0
                }
                Mock Write-Host { [void]$global:DevNavShortcutMessages.Add([string]$Object) }
                Set-DevShortcut -Index 3 -Clear -Confirm:$false
            })
            @($global:DevNavShortcutCliArguments).Count | Should -Be 1
            @($global:DevNavShortcutCliArguments[0]) | Should -Be @('--clear-shortcut', '3')
            $global:DevNavShortcutMessages | Should -Contain 'Shortcut 3 removed.'
        }
        finally {
            Remove-Variable DevNavShortcutCliArguments, DevNavShortcutMessages -Scope Global -ErrorAction SilentlyContinue
        }
    }

    It 'rejects a whitespace-only shortcut command in English' {
        $global:DevNavShortcutCliCalls = 0
        try {
            $devModule.Invoke({
                Mock Get-DevLanguage { 'en-US' }
                Mock Invoke-DevCli { $global:DevNavShortcutCliCalls++; 0 }
                { Set-DevShortcut -Index 3 -Command '   ' -Confirm:$false } | Should -Throw 'Specify the shortcut command, or use -Clear to remove it.'
            })
            $global:DevNavShortcutCliCalls | Should -Be 0
        }
        finally {
            Remove-Variable DevNavShortcutCliCalls -Scope Global -ErrorAction SilentlyContinue
        }
    }

    It 'rejects a whitespace-only shortcut command in Spanish' {
        $global:DevNavShortcutCliCalls = 0
        try {
            $devModule.Invoke({
                Mock Get-DevLanguage { 'es-ES' }
                Mock Invoke-DevCli { $global:DevNavShortcutCliCalls++; 0 }
                { Set-DevShortcut -Index 3 -Command "`t  " -Confirm:$false } | Should -Throw 'Debes indicar el comando del atajo, o usar -Clear para eliminarlo.'
            })
            $global:DevNavShortcutCliCalls | Should -Be 0
        }
        finally {
            Remove-Variable DevNavShortcutCliCalls -Scope Global -ErrorAction SilentlyContinue
        }
    }

    It 'does not invoke the CLI when binding a shortcut with WhatIf' {
        $global:DevNavShortcutCliCalls = 0
        try {
            $devModule.Invoke({
                Mock Invoke-DevCli { $global:DevNavShortcutCliCalls++; 0 }
                Set-DevShortcut -Index 4 -Command 'cargo test' -Alias 'Tests' -WhatIf
            })
            $global:DevNavShortcutCliCalls | Should -Be 0
        }
        finally {
            Remove-Variable DevNavShortcutCliCalls -Scope Global -ErrorAction SilentlyContinue
        }
    }

    It 'reports the English error when saving a shortcut fails' {
        $global:DevNavShortcutCliArguments = [System.Collections.Generic.List[object]]::new()
        try {
            $devModule.Invoke({
                Mock Get-DevLanguage { 'en-US' }
                Mock Invoke-DevCli {
                    [void]$global:DevNavShortcutCliArguments.Add(@($Arguments))
                    9
                }
                { Set-DevShortcut -Index 4 -Command 'cargo test' -Confirm:$false } | Should -Throw 'Could not save shortcut 4 (dev.exe exited with 9).'
            })
            @($global:DevNavShortcutCliArguments).Count | Should -Be 1
            @($global:DevNavShortcutCliArguments[0]) | Should -Be @('--set-shortcut', '4', 'cargo test')
            @($global:DevNavShortcutCliArguments[0]) | Should -Not -Contain '--alias'
        }
        finally {
            Remove-Variable DevNavShortcutCliArguments -Scope Global -ErrorAction SilentlyContinue
        }
    }

    It 'reports the Spanish error when saving a shortcut fails' {
        $global:DevNavShortcutCliArguments = [System.Collections.Generic.List[object]]::new()
        try {
            $devModule.Invoke({
                Mock Get-DevLanguage { 'es-ES' }
                Mock Invoke-DevCli {
                    [void]$global:DevNavShortcutCliArguments.Add(@($Arguments))
                    9
                }
                { Set-DevShortcut -Index 4 -Alias 'Pruebas' -Command 'cargo test' -Confirm:$false } | Should -Throw 'No se pudo guardar el atajo 4 (dev.exe salió con 9).'
            })
            @($global:DevNavShortcutCliArguments).Count | Should -Be 1
            @($global:DevNavShortcutCliArguments[0]) | Should -Be @('--set-shortcut', '4', 'cargo test', '--alias', 'Pruebas')
        }
        finally {
            Remove-Variable DevNavShortcutCliArguments -Scope Global -ErrorAction SilentlyContinue
        }
    }

    It 'reports the English confirmation when saving succeeds' {
        $global:DevNavShortcutCliArguments = [System.Collections.Generic.List[object]]::new()
        $global:DevNavShortcutMessages = [System.Collections.Generic.List[string]]::new()
        try {
            $devModule.Invoke({
                Mock Get-DevLanguage { 'en-US' }
                Mock Invoke-DevCli {
                    [void]$global:DevNavShortcutCliArguments.Add(@($Arguments))
                    0
                }
                Mock Write-Host { [void]$global:DevNavShortcutMessages.Add([string]$Object) }
                Set-DevShortcut -Index 4 -Command 'cargo test' -Confirm:$false
            })
            @($global:DevNavShortcutCliArguments).Count | Should -Be 1
            @($global:DevNavShortcutCliArguments[0]) | Should -Be @('--set-shortcut', '4', 'cargo test')
            $global:DevNavShortcutMessages | Should -Contain 'Shortcut 4 saved: cargo test'
        }
        finally {
            Remove-Variable DevNavShortcutCliArguments, DevNavShortcutMessages -Scope Global -ErrorAction SilentlyContinue
        }
    }
}
Describe 'DevNav navigator early dispatch behavior' {
    BeforeAll {
        $navigatorModule = Get-Module -Name DevNav | Select-Object -First 1
        $navigatorModulePath = $navigatorModule.Path
    }

    BeforeEach {
        Get-Module -Name DevNav | Remove-Module -Force -ErrorAction SilentlyContinue
        Import-Module $navigatorModulePath -Force
        $navigatorModule = Get-Module -Name DevNav | Select-Object -First 1
        $global:DevNavNavigatorCalls = [System.Collections.Generic.List[string]]::new()
        $global:DevNavNavigatorWarnings = [System.Collections.Generic.List[string]]::new()
        $global:DevNavNavigatorLanguage = $null
    }

    AfterEach {
        Remove-Variable -Name DevNavNavigatorCalls, DevNavNavigatorWarnings, DevNavNavigatorLanguage -Scope Global -ErrorAction SilentlyContinue
        Get-Module -Name DevNav | Remove-Module -Force -ErrorAction SilentlyContinue
        Import-Module $navigatorModulePath -Force
        $navigatorModule = Get-Module -Name DevNav | Select-Object -First 1
    }

    It 'reports the saved English language without system detection' {
        $result = InModuleScope DevNav {
            function Get-DevLanguage { 'en-US' }
            function Get-DevSystemLanguage { throw 'system detection should not run' }
            Invoke-DevNavigator language
        }

        $result | Should -Be 'English (en-US)'
    }

    It 'falls back to the Spanish system language when no language is saved' {
        $result = InModuleScope DevNav {
            function Get-DevLanguage { $null }
            function Get-DevSystemLanguage { 'es-ES' }
            Invoke-DevNavigator language
        }

        $result | Should -Be 'Español (es-ES)'
    }

    It 'delegates an explicit language change to Set-DevLanguage' {
        InModuleScope DevNav {
            function Set-DevLanguage { param([string]$Language) $global:DevNavNavigatorLanguage = $Language }
            function Initialize-DevLanguage { throw 'initialization should not run' }
            Invoke-DevNavigator language es
        }

        $global:DevNavNavigatorLanguage | Should -Be 'es'
    }

    It 'delegates the update command before initialization' {
        InModuleScope DevNav {
            function Update-DevNavigator { $global:DevNavNavigatorCalls.Add('update') }
            function Initialize-DevLanguage { throw 'initialization should not run' }
            function Get-DevExecutable { throw 'executable lookup should not run' }
            Invoke-DevNavigator update
        }

        $global:DevNavNavigatorCalls.Count | Should -Be 1
    }

    It 'returns when language initialization does not select a language' {
        InModuleScope DevNav {
            function Initialize-DevLanguage { $null }
            function Invoke-DevStartupUpdateCheck { throw 'startup update should not run' }
            function Get-DevExecutable { throw 'executable lookup should not run' }
            Invoke-DevNavigator
        }

    }

    It 'returns when the startup update completes' {
        InModuleScope DevNav {
            $script:DevNavUpdateCompleted = $false
            $script:DevNavRestartRequired = $false
            function Initialize-DevLanguage { 'en-US' }
            function Invoke-DevStartupUpdateCheck {
                $script:DevNavUpdateCompleted = $true
                $script:DevNavRestartRequired = $false
            }
            function Get-DevExecutable { throw 'executable lookup should not run' }
            Invoke-DevNavigator
        }

    }

    It 'reports the English restart warning and does not launch the navigator' {
        InModuleScope DevNav {
            $script:DevNavUpdateCompleted = $false
            $script:DevNavRestartRequired = $false
            function Initialize-DevLanguage { 'en-US' }
            function Invoke-DevStartupUpdateCheck {
                $script:DevNavUpdateCompleted = $false
                $script:DevNavRestartRequired = $true
            }
            function Get-DevLanguage { 'en-US' }
            function Write-Warning { param($Message) $global:DevNavNavigatorWarnings.Add($Message) }
            function Get-DevExecutable { throw 'executable lookup should not run' }
            Invoke-DevNavigator
        }

        $global:DevNavNavigatorWarnings | Should -Contain 'DevNav was updated. Restart PowerShell to load the updated module.'
    }

    It 'reports the Spanish restart warning and does not launch the navigator' {
        InModuleScope DevNav {
            $script:DevNavUpdateCompleted = $false
            $script:DevNavRestartRequired = $false
            function Initialize-DevLanguage { 'es-ES' }
            function Invoke-DevStartupUpdateCheck {
                $script:DevNavUpdateCompleted = $false
                $script:DevNavRestartRequired = $true
            }
            function Get-DevLanguage { 'es-ES' }
            function Write-Warning { param($Message) $global:DevNavNavigatorWarnings.Add($Message) }
            function Get-DevExecutable { throw 'executable lookup should not run' }
            Invoke-DevNavigator
        }

        $global:DevNavNavigatorWarnings | Should -Contain 'DevNav se ha actualizado. Reinicia PowerShell para cargar el módulo actualizado.'
    }
}

Describe 'DevNav navigator native result dispatch behavior' {
    BeforeAll {
        $nativeModule = Get-Module -Name DevNav | Select-Object -First 1
        $nativeModulePath = $nativeModule.Path
        $nativeFixtureRoot = Join-Path $testLocalAppData ('navigator-native-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $nativeFixtureRoot -Force | Out-Null
        $nativeShimPath = Join-Path $nativeFixtureRoot 'devnav-shim.cmd'
        $nativeShimScript = Join-Path $nativeFixtureRoot 'devnav-shim.ps1'
        $nativeArgsLog = Join-Path $nativeFixtureRoot 'args.log'
        $nativeResultDirectory = Join-Path $nativeFixtureRoot 'selected'
        New-Item -ItemType Directory -Path $nativeResultDirectory -Force | Out-Null
        $nativeShimTemplate = @'
param([string[]]$Args)
if ($env:DEVNAV_NATIVE_ARGS_LOG) {
    [System.IO.File]::WriteAllText($env:DEVNAV_NATIVE_ARGS_LOG, [string]::Join("`n", $Args))
}
$resultIndex = [array]::IndexOf($Args, '--result')
if ($resultIndex -ge 0 -and $env:DEVNAV_NATIVE_RESULT_BASE64) {
    $content = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($env:DEVNAV_NATIVE_RESULT_BASE64))
    [System.IO.File]::WriteAllText($Args[$resultIndex + 1], $content)
}
exit ([int]$env:DEVNAV_NATIVE_EXIT_CODE)
'@
        Set-Content -LiteralPath $nativeShimScript -Value $nativeShimTemplate -Encoding utf8NoBOM
        Set-Content -LiteralPath $nativeShimPath -Value "@echo off`r`npwsh -NoProfile -ExecutionPolicy Bypass -File `"%~dp0devnav-shim.ps1`" %*`r`n" -Encoding ascii
        function Assert-NativeInvocation {
            $invocation = @(Get-Content -LiteralPath $nativeArgsLog)
            $invocation | Should -Contain '--root'
            $rootIndex = [array]::IndexOf($invocation, '--root')
            $invocation[$rootIndex + 1] | Should -Be $nativeFixtureRoot
            $resultIndex = [array]::IndexOf($invocation, '--result')
            $resultIndex | Should -BeGreaterOrEqual 0
            $resultPath = $invocation[$resultIndex + 1]
            (Test-Path -LiteralPath $resultPath) | Should -BeFalse
            return $resultPath
        }
    }

    BeforeEach {
        Get-Module -Name DevNav | Remove-Module -Force -ErrorAction SilentlyContinue
        Import-Module $nativeModulePath -Force
        $nativeModule = Get-Module -Name DevNav | Select-Object -First 1
        $env:DEVNAV_NATIVE_ARGS_LOG = $nativeArgsLog
        $env:DEVNAV_NATIVE_EXIT_CODE = '0'
        $global:DevNavNativeShim = $nativeShimPath
        $global:DevNavNativeRoot = $nativeFixtureRoot
        Remove-Item -LiteralPath $nativeArgsLog -Force -ErrorAction SilentlyContinue
        Remove-Item Env:DEVNAV_NATIVE_RESULT_BASE64 -ErrorAction SilentlyContinue
        $global:DevNavNativeCalls = [System.Collections.Generic.List[string]]::new()
        $global:DevNavNativeResultFile = $null
    }

    AfterEach {
        Remove-Item Env:DEVNAV_NATIVE_ARGS_LOG, Env:DEVNAV_NATIVE_EXIT_CODE, Env:DEVNAV_NATIVE_RESULT_BASE64 -ErrorAction SilentlyContinue
        Remove-Variable DevNavNativeCalls, DevNavNativeResultFile, DevNavNativeShim, DevNavNativeRoot -Scope Global -ErrorAction SilentlyContinue
        Get-Module -Name DevNav | Remove-Module -Force -ErrorAction SilentlyContinue
        Import-Module $nativeModulePath -Force
        $nativeModule = Get-Module -Name DevNav | Select-Object -First 1
    }

    AfterAll {
        Remove-Item -LiteralPath $nativeFixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'returns cleanly when the native navigator exits with a nonzero code' {
        $env:DEVNAV_NATIVE_EXIT_CODE = '7'
        $result = $nativeModule.Invoke({
            function Initialize-DevLanguage { 'en-US' }
            function Invoke-DevStartupUpdateCheck { $script:DevNavUpdateCompleted = $false; $script:DevNavRestartRequired = $false }
            function Get-DevRoot { $global:DevNavNativeRoot }
            function Get-DevExecutable { $global:DevNavNativeShim }
            function Set-Location { throw 'Set-Location should not run' }
            function Invoke-Expression { throw 'Invoke-Expression should not run' }
            Invoke-DevNavigator
        })
        $result | Should -BeNullOrEmpty
        Assert-NativeInvocation | Should -Not -BeNullOrEmpty
    }

    It 'returns cleanly when the native navigator creates no result file' {
        $result = $nativeModule.Invoke({
            function Initialize-DevLanguage { 'en-US' }
            function Invoke-DevStartupUpdateCheck { $script:DevNavUpdateCompleted = $false; $script:DevNavRestartRequired = $false }
            function Get-DevRoot { $global:DevNavNativeRoot }
            function Get-DevExecutable { $global:DevNavNativeShim }
            function Set-Location { throw 'Set-Location should not run' }
            function Invoke-Expression { throw 'Invoke-Expression should not run' }
            Invoke-DevNavigator
        })
        $result | Should -BeNullOrEmpty
        Assert-NativeInvocation | Should -Not -BeNullOrEmpty
    }

    It 'reports the English error for an invalid native result' {
        $env:DEVNAV_NATIVE_RESULT_BASE64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('invalid'))
        $global:DevNavNativeLanguage = 'en-US'
        try {
            $nativeModule.Invoke({
                function Initialize-DevLanguage { 'en-US' }
                function Invoke-DevStartupUpdateCheck { $script:DevNavUpdateCompleted = $false; $script:DevNavRestartRequired = $false }
                function Get-DevRoot { $global:DevNavNativeRoot }
                function Get-DevExecutable { $global:DevNavNativeShim }
                function Get-DevLanguage { $global:DevNavNativeLanguage }
                { Invoke-DevNavigator } | Should -Throw 'DevNav returned an invalid result.'
            })
            Assert-NativeInvocation | Should -Not -BeNullOrEmpty
        }
        finally { Remove-Variable DevNavNativeLanguage -Scope Global -ErrorAction SilentlyContinue }
    }

    It 'reports the Spanish error for an invalid native result' {
        $env:DEVNAV_NATIVE_RESULT_BASE64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('invalid'))
        $global:DevNavNativeLanguage = 'es-ES'
        try {
            $nativeModule.Invoke({
                function Initialize-DevLanguage { 'es-ES' }
                function Invoke-DevStartupUpdateCheck { $script:DevNavUpdateCompleted = $false; $script:DevNavRestartRequired = $false }
                function Get-DevRoot { $global:DevNavNativeRoot }
                function Get-DevExecutable { $global:DevNavNativeShim }
                function Get-DevLanguage { $global:DevNavNativeLanguage }
                { Invoke-DevNavigator } | Should -Throw 'DevNav devolvió un resultado no válido.'
            })
            Assert-NativeInvocation | Should -Not -BeNullOrEmpty
        }
        finally { Remove-Variable DevNavNativeLanguage -Scope Global -ErrorAction SilentlyContinue }
    }

    It 'dispatches an update result without changing location' {
        $env:DEVNAV_NATIVE_RESULT_BASE64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("update`0$nativeResultDirectory"))
        $nativeModule.Invoke({
            function Initialize-DevLanguage { 'en-US' }
            function Invoke-DevStartupUpdateCheck { $script:DevNavUpdateCompleted = $false; $script:DevNavRestartRequired = $false }
            function Get-DevRoot { $global:DevNavNativeRoot }
            function Get-DevExecutable { $global:DevNavNativeShim }
            function Update-DevNavigator { $global:DevNavNativeCalls.Add('update') }
            function Set-Location { throw 'Set-Location should not run' }
            Invoke-DevNavigator
        })
        $global:DevNavNativeCalls | Should -Be @('update')
        Assert-NativeInvocation | Should -Not -BeNullOrEmpty
    }

    It 'navigates to a normal result without evaluating a command' {
        $env:DEVNAV_NATIVE_RESULT_BASE64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("navigate`0$nativeResultDirectory"))
        $nativeModule.Invoke({
            function Initialize-DevLanguage { 'en-US' }
            function Invoke-DevStartupUpdateCheck { $script:DevNavUpdateCompleted = $false; $script:DevNavRestartRequired = $false }
            function Get-DevRoot { $global:DevNavNativeRoot }
            function Get-DevExecutable { $global:DevNavNativeShim }
            function Set-Location { param($LiteralPath) $global:DevNavNativeCalls.Add("location:$LiteralPath") }
            function Invoke-Expression { throw 'Invoke-Expression should not run' }
            Invoke-DevNavigator
        })
        $global:DevNavNativeCalls | Should -Be @("location:$nativeResultDirectory")
        Assert-NativeInvocation | Should -Not -BeNullOrEmpty
    }

    It 'evaluates the command returned by the native result' {
        $env:DEVNAV_NATIVE_RESULT_BASE64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("exec`0$nativeResultDirectory`0cargo test"))
        $nativeModule.Invoke({
            function Initialize-DevLanguage { 'en-US' }
            function Invoke-DevStartupUpdateCheck { $script:DevNavUpdateCompleted = $false; $script:DevNavRestartRequired = $false }
            function Get-DevRoot { $global:DevNavNativeRoot }
            function Get-DevExecutable { $global:DevNavNativeShim }
            function Set-Location { param($LiteralPath) $global:DevNavNativeCalls.Add("location:$LiteralPath") }
            function Invoke-Expression { param($Command) $global:DevNavNativeCalls.Add("command:$Command") }
            Invoke-DevNavigator
        })
        $global:DevNavNativeCalls | Should -Contain 'command:cargo test'
        Assert-NativeInvocation | Should -Not -BeNullOrEmpty
    }

    It 'prefers an explicit command over the native result command' {
        $env:DEVNAV_NATIVE_RESULT_BASE64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("exec`0$nativeResultDirectory`0embedded command"))
        $nativeModule.Invoke({
            function Initialize-DevLanguage { 'en-US' }
            function Invoke-DevStartupUpdateCheck { $script:DevNavUpdateCompleted = $false; $script:DevNavRestartRequired = $false }
            function Get-DevRoot { $global:DevNavNativeRoot }
            function Get-DevExecutable { $global:DevNavNativeShim }
            function Set-Location { param($LiteralPath) $global:DevNavNativeCalls.Add("location:$LiteralPath") }
            function Invoke-Expression { param($Command) $global:DevNavNativeCalls.Add("command:$Command") }
            Invoke-DevNavigator git status
        })
        $global:DevNavNativeCalls | Should -Contain 'command:git status'
        $global:DevNavNativeCalls | Should -Not -Contain 'command:embedded command'
        Assert-NativeInvocation | Should -Not -BeNullOrEmpty
    }

    It 'does not evaluate an empty or whitespace native command' {
        $env:DEVNAV_NATIVE_RESULT_BASE64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("exec`0$nativeResultDirectory`0   "))
        $nativeModule.Invoke({
            function Initialize-DevLanguage { 'en-US' }
            function Invoke-DevStartupUpdateCheck { $script:DevNavUpdateCompleted = $false; $script:DevNavRestartRequired = $false }
            function Get-DevRoot { $global:DevNavNativeRoot }
            function Get-DevExecutable { $global:DevNavNativeShim }
            function Set-Location { param($LiteralPath) $global:DevNavNativeCalls.Add("location:$LiteralPath") }
            function Invoke-Expression { param($Command) $global:DevNavNativeCalls.Add("command:$Command") }
            Invoke-DevNavigator '   '
        })
        @($global:DevNavNativeCalls | Where-Object { $_ -like 'command:*' }).Count | Should -Be 0
        Assert-NativeInvocation | Should -Not -BeNullOrEmpty
    }
}
