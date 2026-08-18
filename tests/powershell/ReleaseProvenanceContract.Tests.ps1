BeforeAll {
    $script:workflowPath = Join-Path $PSScriptRoot '..\..\.github\workflows\release.yml'
    $script:workflow = Get-Content -LiteralPath $script:workflowPath -Raw
}

Describe 'release provenance publication contract' {
    It 'generates Scoop manifests with Scoop canonical four-space formatting' {
        $script:workflow | Should -Match 'jq\s+--indent\s+4\s+--arg version'
    }

    It 'produces a Scorecard-recognizable intoto jsonl artifact per architecture' {
        $script:workflow |
            Should -Match 'DevNav-build-provenance-\$\{\{ matrix\.architecture \}\}\.intoto\.jsonl'

        $script:workflow |
            Should -Match 'convert-attestation-to-intoto\.ps1'
    }

    It 'preflights both provenance assets against the final publication artifacts' {
        $script:workflow |
            Should -Match 'verify_provenance\s+\\?\s*x64\s+\\?\s*dev-windows-x86_64\.exe\s+\\?\s*DevNavSetup-x64\.exe\s+\\?\s*DevNav-scoop-x64\.zip'

        $script:workflow |
            Should -Match 'verify_provenance\s+\\?\s*arm64\s+\\?\s*dev-windows-aarch64\.exe\s+\\?\s*DevNavSetup-arm64\.exe\s+\\?\s*DevNav-scoop-arm64\.zip'
    }

    It 'runs the provenance preflight before creating the GitHub release' {
        $preflightIndex = $script:workflow.IndexOf('- name: Verify release provenance assets')
        $releaseIndex = $script:workflow.IndexOf('gh release create')

        $preflightIndex | Should -BeGreaterThan -1
        $releaseIndex | Should -BeGreaterThan $preflightIndex
    }

    It 'publishes intoto jsonl files as GitHub Release assets' {
        $script:workflow |
            Should -Match 'artifacts/\*\.intoto\.jsonl'
    }
}
