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
        param([switch] $Install, [string] $ModulePath)
        $arguments = @{ Install = $Install; ModulePath = $ModulePath }
        & $global:profileIntegrationScriptPath @arguments
        [pscustomobject]@{
            Content = @($global:profileSetContent)
            Encoding = $global:profileSetEncoding
            NewItemPaths = @($global:profileNewItemPaths)
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
        Mock Remove-Item { param($LiteralPath) }
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
}
