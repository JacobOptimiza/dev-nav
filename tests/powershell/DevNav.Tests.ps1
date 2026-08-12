BeforeAll {
    $repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $modulePath = Join-Path $repositoryRoot 'powershell\DevNav.psm1'
    $testLocalAppData = Join-Path ([System.IO.Path]::GetTempPath()) ('devnav-pester-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $testLocalAppData -Force | Out-Null
    $previousLocalAppData = $env:LOCALAPPDATA
    $env:LOCALAPPDATA = $testLocalAppData
    Import-Module $modulePath -Force
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
}
