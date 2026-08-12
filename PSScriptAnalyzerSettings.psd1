@{
    Severity = @('Error', 'Warning')

    # These rules are intentionally scoped out:
    # - Write-Host is the explicit terminal UI/status channel for this module.
    # - Invoke-Expression is required for the user-requested arbitrary command
    #   launcher and receives text only after the user selects it in the TUI.
    # - BOM is not required for PowerShell 7 UTF-8 source files and would add
    #   unnecessary bytes to a public cross-editor module.
    ExcludeRules = @(
        'PSAvoidUsingWriteHost',
        'PSAvoidUsingInvokeExpression',
        'PSUseBOMForUnicodeEncodedFile'
    )
}
