@{
    RootModule        = 'DevNav.psm1'
    ModuleVersion     = '0.11.0'
    GUID              = '5e631432-751b-46ce-bfa6-8a0051bc9bd1'
    Author            = 'Jacob Optimiza'
    CompanyName       = 'Jacob Optimiza'
    Copyright         = '(c) 2026 Jacob Optimiza. All rights reserved.'
    Description       = 'Native high-performance workspace navigator for PowerShell 7 on Windows.'
    PowerShellVersion = '7.0'

    FunctionsToExport = @(
        'Invoke-DevNavigator'
        'Update-DevNavigator'
        'Get-DevRoot'
        'Set-DevRoot'
        'Set-DevUpdateCheck'
        'Get-DevLanguage'
        'Set-DevLanguage'
        'Set-DevShortcut'
        'Remove-DevShortcut'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @('dev')

    PrivateData       = @{
        PSData = @{
            Tags       = @('navigation', 'terminal', 'tui', 'workspace')
            LicenseUri = 'https://github.com/JacobOptimiza/dev-nav/blob/main/LICENSE'
            ProjectUri = 'https://github.com/JacobOptimiza/dev-nav'
        }
    }
}
