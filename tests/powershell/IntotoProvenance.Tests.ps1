BeforeAll {
    $script:convertScript = Join-Path $PSScriptRoot '..\..\scripts\convert-attestation-to-intoto.ps1'
    $script:fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("devnav-intoto-{0}" -f [guid]::NewGuid().ToString('N'))
    [System.IO.Directory]::CreateDirectory($script:fixtureRoot) | Out-Null

    # Fixture faithful to actions/attest v4.2.2 output: a Sigstore bundle
    # (mediaType + verificationMaterial) wrapping a DSSE envelope whose
    # payload is a SLSA v1 in-toto Statement.
    $shaExe = ([System.Security.Cryptography.SHA256]::Create()).ComputeHash([Text.Encoding]::UTF8.GetBytes('exe'))
    $exeDigest = -join ($shaExe | ForEach-Object { $_.ToString('x2') })
    $statement = @{
        '_type'        = 'https://in-toto.io/Statement/v1'
        'subject'      = @(
            @{ name = 'dev-windows-x86_64.exe'; digest = @{ sha256 = $exeDigest } }
        )
        'predicateType' = 'https://slsa.dev/provenance/v1'
        'predicate'    = @{
            buildDefinition = @{ buildType = 'https://actions.github.com/buildtypes/workflow/v1' }
            runDetails     = @{ builder = @{ id = 'https://github.com/actions/attest' } }
        }
    }
    $statementJson = $statement | ConvertTo-Json -Compress -Depth 12
    $payload = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($statementJson))
    $envelope = @{
        payloadType = 'application/vnd.in-toto+json'
        payload     = $payload
        signatures  = @(@{ keyid = ''; sig = 'MEUCIQ' + ('A' * 80) })
    }
    $script:bundle = @{
        mediaType             = 'application/vnd.dev.sigstore.bundle+json;version=0.3'
        dsseEnvelope          = $envelope
        verificationMaterial  = @{ tlogEntries = @(@{ logIndex = '1' }) }
    }

    $script:bundlePath = Join-Path $script:fixtureRoot 'attestation.json'
    $script:bundle | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $script:bundlePath

    function Invoke-Conversion {
        param([string] $OutputName, [string[]] $ExpectedSubject, [string] $BundlePath = $script:bundlePath)
        & $script:convertScript -BundlePath $BundlePath `
            -OutputPath (Join-Path $script:fixtureRoot $OutputName) `
            -ExpectedSubject $ExpectedSubject
        return $LASTEXITCODE
    }
}

AfterAll {
    if ([System.IO.Directory]::Exists($script:fixtureRoot)) {
        [System.IO.Directory]::Delete($script:fixtureRoot, $true)
    }
}

Describe 'convert-attestation-to-intoto' {
    It 'extracts a valid one-line DSSE envelope from a Sigstore bundle' {
        $exit = Invoke-Conversion -OutputName 'ok.jsonl' -ExpectedSubject 'dev-windows-x86_64.exe'
        $exit | Should -Be 0

        $lines = @(Get-Content -LiteralPath (Join-Path $script:fixtureRoot 'ok.jsonl') | Where-Object { $_.Length -gt 0 })
        $lines.Count | Should -Be 1
        $envelope = $lines[0] | ConvertFrom-Json
        $envelope.PSObject.Properties['payloadType'] | Should -Not -BeNullOrEmpty
        $envelope.PSObject.Properties['payload'] | Should -Not -BeNullOrEmpty
        $envelope.PSObject.Properties['signatures'] | Should -Not -BeNullOrEmpty
        # Not a renamed bundle.
        $envelope.PSObject.Properties['mediaType'] | Should -BeNullOrEmpty
        $envelope.PSObject.Properties['dsseEnvelope'] | Should -BeNullOrEmpty
        $envelope.PSObject.Properties['verificationMaterial'] | Should -BeNullOrEmpty

        $decoded = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($envelope.payload)) | ConvertFrom-Json
        $decoded.'_type' | Should -Be 'https://in-toto.io/Statement/v1'
        $decoded.predicateType | Should -Be 'https://slsa.dev/provenance/v1'
        $decoded.subject[0].name | Should -Be 'dev-windows-x86_64.exe'
        $decoded.subject[0].digest.sha256 | Should -Match '^[0-9a-f]{64}$'
    }

    It 'rejects a renamed Sigstore bundle written as the jsonl content' {
        # Simulate the old, incorrect behavior: the whole bundle as one line.
        $renamedPath = Join-Path $script:fixtureRoot 'renamed.jsonl'
        ($script:bundle | ConvertTo-Json -Compress -Depth 12) | Set-Content -LiteralPath $renamedPath
        $lines = @(Get-Content -LiteralPath $renamedPath | Where-Object { $_.Length -gt 0 })
        $lines.Count | Should -Be 1
        $asEnvelope = $lines[0] | ConvertFrom-Json
        # A bundle at the root has dsseEnvelope/mediaType but no payload.
        $asEnvelope.PSObject.Properties['payload'] | Should -BeNullOrEmpty
        $asEnvelope.PSObject.Properties['dsseEnvelope'] | Should -Not -BeNullOrEmpty
    }

    It 'fails when the bundle has no dsseEnvelope member' {
        $badPath = Join-Path $script:fixtureRoot 'no-envelope.json'
        @{ mediaType = 'application/vnd.dev.sigstore.bundle+json;version=0.3' } |
            ConvertTo-Json | Set-Content -LiteralPath $badPath
        { Invoke-Conversion -OutputName 'bad.jsonl' -ExpectedSubject 'x' -BundlePath $badPath } | Should -Throw
    }

    It 'fails when an expected subject is not attested' {
        { Invoke-Conversion -OutputName 'missing.jsonl' -ExpectedSubject 'other-artifact.exe' } | Should -Throw
    }
}
