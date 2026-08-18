BeforeAll {
    $script:workflowPath = Join-Path $PSScriptRoot '..\..\.github\workflows\release.yml'
    $script:workflow = Get-Content -LiteralPath $script:workflowPath -Raw
}

Describe 'release workflow mode contract' {
    It 'runs normal build, publish and npm packaging only for push events' {
        $script:workflow | Should -Match '(?ms)build:\s+if:\s+\$\{\{ github\.event_name == ''push'' \}\}'
        $script:workflow | Should -Match '(?ms)publish:\s+if:\s+\$\{\{ github\.event_name == ''push'' \}\}'
        $script:workflow | Should -Match '(?ms)npm-package:\s+if:\s+\$\{\{ github\.event_name == ''push'' \}\}'
        $script:workflow | Should -Match '(?ms)npm-publish:\s+if:\s+\$\{\{ github\.event_name == ''push'' && vars\.NPM_TRUSTED_PUBLISHING_ENABLED == ''true'' \}\}'
    }

    It 'keeps workflow dispatch limited to npm recovery' {
        $script:workflow | Should -Match '(?ms)npm-recovery-package:\s+if:\s+\$\{\{ github\.event_name == ''workflow_dispatch'' \}\}'
        $script:workflow | Should -Match '(?ms)npm-recovery-publish:\s+if:\s+\$\{\{ github\.event_name == ''workflow_dispatch'' && vars\.NPM_TRUSTED_PUBLISHING_ENABLED == ''true'' \}\}'
        $script:workflow | Should -Not -Match 'inputs\.tag == ''v0\.14\.0'''
    }

    It 'cannot reach release creation from workflow dispatch or a hardcoded release version' {
        $script:workflow | Should -Not -Match 'v0\.14\.0'
        $script:workflow | Should -Match 'gh release create "\$\{GITHUB_REF_NAME\}"'
        $script:workflow | Should -Match '--verify-tag'
    }
}
