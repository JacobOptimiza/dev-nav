BeforeAll {
    $repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $scriptPath = Join-Path $repositoryRoot 'installer\ProfileIntegration.ps1'
    $realProfilePath = $PROFILE.CurrentUserCurrentHost
    $realProfileSnapshot = if (Test-Path -LiteralPath $realProfilePath -PathType Leaf) {
        [pscustomobject]@{ Exists = $true; Hash = (Get-FileHash -LiteralPath $realProfilePath -Algorithm SHA256).Hash }
    }
    else {
        [pscustomobject]@{ Exists = $false; Hash = $null }
    }
    Set-Item Function:\global:Invoke-ProfileIntegrationRegression {
        param([switch] $Install, [switch] $Uninstall, [string] $ModulePath)
        $arguments = @{ ModulePath = $ModulePath }
        if ($Install) { $arguments.Install = $true }
        if ($Uninstall) { $arguments.Uninstall = $true }
        & $global:profileIntegrationScriptPath @arguments
        [pscustomobject]@{
            Content = @($global:profileSetContent)
            Encoding = $global:profileSetEncoding
            NewItemPaths = @($global:profileNewItemPaths)
            RemovedPaths = @($global:profileRemovedPaths)
        }
    }
}

AfterAll {
    $currentSnapshot = if (Test-Path -LiteralPath $realProfilePath -PathType Leaf) {
        [pscustomobject]@{ Exists = $true; Hash = (Get-FileHash -LiteralPath $realProfilePath -Algorithm SHA256).Hash }
    }
    else {
        [pscustomobject]@{ Exists = $false; Hash = $null }
    }
    $currentSnapshot.Exists | Should -Be $realProfileSnapshot.Exists
    $currentSnapshot.Hash | Should -Be $realProfileSnapshot.Hash
    Remove-Item Function:\global:Invoke-ProfileIntegrationRegression -ErrorAction SilentlyContinue
}

Describe 'ProfileIntegration.ps1 regression behavior' {
    BeforeEach {
        $global:profileIntegrationScriptPath = $scriptPath
        $global:profileExists = $true
        $global:profileExistingContent = @()
        $global:profileSetContent = $null
        $global:profileSetEncoding = $null
        $global:profileNewItemPaths = [System.Collections.Generic.List[string]]::new()
        $global:profileRemovedPaths = [System.Collections.Generic.List[string]]::new()

        Mock Test-Path {
            param($LiteralPath, $PathType)
            if ($LiteralPath -eq $PROFILE.CurrentUserCurrentHost) { return $global:profileExists }
            return $false
        }
        Mock Get-Content {
            param($LiteralPath)
            if ($LiteralPath -eq $PROFILE.CurrentUserCurrentHost) { return $global:profileExistingContent }
            throw "Unexpected Get-Content path: $LiteralPath"
        }
        Mock New-Item {
            param($Path)
            [void] $global:profileNewItemPaths.Add($Path)
            [pscustomobject]@{ FullName = $Path }
        }
        Mock Set-Content {
            param($LiteralPath, $Value, $Encoding)
            $global:profileSetContent = @($Value | ForEach-Object { $_ })
            $global:profileSetEncoding = $Encoding
        }
        Mock Remove-Item {
            param($LiteralPath)
            [void] $global:profileRemovedPaths.Add($LiteralPath)
        }
    }

    It 'rejects invocation when neither mode is selected' {
        { Invoke-ProfileIntegrationRegression -ModulePath 'C:\DevNav.psm1' } |
            Should -Throw 'Specify exactly one of -Install or -Uninstall.'
        Should -Invoke New-Item -Times 0 -Scope It
        Should -Invoke Set-Content -Times 0 -Scope It
        Should -Invoke Remove-Item -Times 0 -Scope It
    }

    It 'rejects invocation when both modes are selected' {
        { Invoke-ProfileIntegrationRegression -Install -Uninstall -ModulePath 'C:\DevNav.psm1' } |
            Should -Throw 'Specify exactly one of -Install or -Uninstall.'
        Should -Invoke New-Item -Times 0 -Scope It
        Should -Invoke Set-Content -Times 0 -Scope It
        Should -Invoke Remove-Item -Times 0 -Scope It
    }

    It 'installs successfully when the profile does not exist' {
        $global:profileExists = $false
        $modulePath = 'C:\Program Files\DevNav\DevNav.psm1'
        $result = Invoke-ProfileIntegrationRegression -Install -ModulePath $modulePath

        $result.Encoding | Should -BeOfType ([System.Text.UTF8Encoding])
        $result.Encoding.GetPreamble().Length | Should -Be 0
        $result.Content | Should -Contain '# >>> DevNav >>>'
        $result.Content | Should -Contain "Import-Module '$modulePath'"
        $result.Content | Should -Contain '# <<< DevNav <<<'
        @($result.Content | Where-Object { $_ -eq '# >>> DevNav >>>' }).Count | Should -Be 1
        @($result.Content | Where-Object { $_ -eq '# <<< DevNav <<<' }).Count | Should -Be 1
        Should -Invoke New-Item -Times 2 -Scope It
        Should -Invoke Set-Content -Times 1 -Scope It
    }

    It 'preserves a single-line profile and appends one DevNav block' {
        $global:profileExistingContent = @('Set-Alias foo bar')
        $modulePath = 'C:\Program Files\DevNav\DevNav.psm1'
        $result = Invoke-ProfileIntegrationRegression -Install -ModulePath $modulePath

        $result.Content | Should -Contain 'Set-Alias foo bar'
        @($result.Content | Where-Object { $_ -eq '# >>> DevNav >>>' }).Count | Should -Be 1
        @($result.Content | Where-Object { $_ -eq '# <<< DevNav <<<' }).Count | Should -Be 1
        $result.Content | Should -Contain "Import-Module '$modulePath'"
    }

    It 'preserves a small multi-line profile and appends one DevNav block' {
        $global:profileExistingContent = @('line before', 'line after')
        $result = Invoke-ProfileIntegrationRegression -Install -ModulePath 'C:\Program Files\DevNav\DevNav.psm1'

        $result.Content | Should -Contain 'line before'
        $result.Content | Should -Contain 'line after'
        @($result.Content | Where-Object { $_ -eq '# >>> DevNav >>>' }).Count | Should -Be 1
        @($result.Content | Where-Object { $_ -eq '# <<< DevNav <<<' }).Count | Should -Be 1
    }

    It 'replaces an existing DevNav block during installation' {
        $global:profileExistingContent = @(
            'user content before',
            '# >>> DevNav >>>',
            "Import-Module 'old.psm1'",
            '# <<< DevNav <<<',
            'user content after'
        )
        $result = Invoke-ProfileIntegrationRegression -Install -ModulePath "C:\Program Files\DevNav\new's.psm1"

        $result.Content | Should -Contain 'user content before'
        $result.Content | Should -Contain 'user content after'
        $result.Content | Should -Contain "Import-Module 'C:\Program Files\DevNav\new''s.psm1'"
        $result.Content | Should -Not -Contain "Import-Module 'old.psm1'"
        @($result.Content | Where-Object { $_ -eq '# >>> DevNav >>>' }).Count | Should -Be 1
        @($result.Content | Where-Object { $_ -eq '# <<< DevNav <<<' }).Count | Should -Be 1
    }

    It 'uninstalls a DevNav block while preserving unrelated profile content' {
        $global:profileExistingContent = @(
            'before',
            '# >>> DevNav >>>',
            "Import-Module 'DevNav.psm1'",
            '# <<< DevNav <<<',
            'after'
        )
        $result = Invoke-ProfileIntegrationRegression -Uninstall -ModulePath 'C:\DevNav.psm1'

        $result.Content | Should -Contain 'before'
        $result.Content | Should -Contain 'after'
        $result.Content | Should -Not -Contain '# >>> DevNav >>>'
        $result.Content | Should -Not -Contain '# <<< DevNav <<<'
        Should -Invoke Set-Content -Times 1 -Scope It
        Should -Invoke Remove-Item -Times 0 -Scope It
    }

    It 'uninstalls a DevNav block at the start while preserving following content' {
        $global:profileExistingContent = @(
            '# >>> DevNav >>>',
            "Import-Module 'DevNav.psm1'",
            '# <<< DevNav <<<',
            'after'
        )
        $result = Invoke-ProfileIntegrationRegression -Uninstall -ModulePath 'C:\DevNav.psm1'

        $result.Content | Should -Be 'after'
        Should -Invoke Set-Content -Times 1 -Scope It
    }

    It 'uninstalls a DevNav block at the end while preserving preceding content' {
        $global:profileExistingContent = @(
            'before',
            '# >>> DevNav >>>',
            "Import-Module 'DevNav.psm1'",
            '# <<< DevNav <<<'
        )
        $result = Invoke-ProfileIntegrationRegression -Uninstall -ModulePath 'C:\DevNav.psm1'

        $result.Content | Should -Be 'before'
        Should -Invoke Set-Content -Times 1 -Scope It
    }

    It 'preserves a malformed marker pair according to current semantics' {
        $global:profileExistingContent = @(
            '# >>> DevNav >>>',
            'user content'
        )
        $result = Invoke-ProfileIntegrationRegression -Uninstall -ModulePath 'C:\DevNav.psm1'

        $result.Content | Should -Contain '# >>> DevNav >>>'
        $result.Content | Should -Contain 'user content'
        Should -Invoke Set-Content -Times 1 -Scope It
    }
}
