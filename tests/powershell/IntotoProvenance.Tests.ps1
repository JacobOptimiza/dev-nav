BeforeAll {
    $script:convertScript = Join-Path $PSScriptRoot '..\..\scripts\convert-attestation-to-intoto.ps1'
    $script:fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("devnav-intoto-{0}" -f [guid]::NewGuid().ToString('N'))
    [System.IO.Directory]::CreateDirectory($script:fixtureRoot) | Out-Null

    # Fixture faithful to actions/attest v4.2.2 output: a Sigstore bundle
    # (mediaType + verificationMaterial) wrapping a DSSE envelope whose
    # payload is a SLSA v1 in-toto Statement over three real artifact files.
    function New-TestArtifact {
        param([string] $Name, [string] $Content)
        $path = Join-Path $script:fixtureRoot $Name
        Set-Content -LiteralPath $path -Value $Content -NoNewline
        return $path
    }

    function Get-DigestOf {
        param([string] $Path)
        return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    }

    function New-AttestationBundle {
        param([hashtable[]] $SubjectSpec)
        $statement = @{
            '_type'        = 'https://in-toto.io/Statement/v1'
            'subject'      = @($SubjectSpec | ForEach-Object {
                @{ name = $_.name; digest = @{ sha256 = $_.digest } }
            })
            'predicateType' = 'https://slsa.dev/provenance/v1'
            'predicate'    = @{
                buildDefinition = @{ buildType = 'https://actions.github.com/buildtypes/workflow/v1' }
                runDetails     = @{ builder = @{ id = 'https://github.com/actions/attest' } }
            }
        }
        $statementJson = $statement | ConvertTo-Json -Compress -Depth 12
        $payload = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($statementJson))
        return @{
            mediaType            = 'application/vnd.dev.sigstore.bundle+json;version=0.3'
            dsseEnvelope         = @{
                payloadType = 'application/vnd.in-toto+json'
                payload     = $payload
                signatures  = @(@{ keyid = ''; sig = 'MEUCIQ' + ('A' * 80) })
            }
            verificationMaterial = @{ tlogEntries = @(@{ logIndex = '1' }) }
        }
    }

    # Three real artifacts, exactly like one build architecture produces.
    $script:artifacts = @(
        @{ file = 'dev-windows-x86_64.exe'; content = 'binary-bytes-exe' }
        @{ file = 'DevNavSetup-x64.exe'; content = 'binary-bytes-setup' }
        @{ file = 'DevNav-scoop-x64.zip'; content = 'binary-bytes-zip' }
    )
    foreach ($artifact in $script:artifacts) {
        $artifact.path = New-TestArtifact -Name $artifact.file -Content $artifact.content
        $artifact.digest = Get-DigestOf $artifact.path
    }

    function Save-Bundle {
        param([string] $Name, [hashtable] $Bundle)
        $path = Join-Path $script:fixtureRoot $Name
        $Bundle | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $path
        return $path
    }

    function Invoke-Conversion {
        param([string] $OutputName, [string[]] $ExpectedSubject, [string] $BundlePath)
        $previous = Get-Location
        try {
            Set-Location -LiteralPath $script:fixtureRoot
            & $script:convertScript -BundlePath $BundlePath `
                -OutputPath (Join-Path $script:fixtureRoot $OutputName) `
                -ExpectedSubject $ExpectedSubject
            return $LASTEXITCODE
        }
        finally {
            Set-Location -LiteralPath $previous
        }
    }
}

AfterAll {
    if ([System.IO.Directory]::Exists($script:fixtureRoot)) {
        [System.IO.Directory]::Delete($script:fixtureRoot, $true)
    }
}

Describe 'convert-attestation-to-intoto' {
    It 'extracts a valid one-line DSSE envelope over three subjects with real digests' {
        $bundle = New-AttestationBundle -SubjectSpec @(
            $script:artifacts | ForEach-Object { @{ name = $_.file; digest = $_.digest } }
        )
        $bundlePath = Save-Bundle -Name 'attestation.json' -Bundle $bundle

        $exit = Invoke-Conversion -OutputName 'ok.jsonl' -BundlePath $bundlePath `
            -ExpectedSubject 'dev-windows-x86_64.exe', 'DevNavSetup-x64.exe', 'DevNav-scoop-x64.zip'
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
        @($decoded.subject).Count | Should -Be 3
        foreach ($artifact in $script:artifacts) {
            $subject = @($decoded.subject) | Where-Object { $_.name -eq $artifact.file }
            $subject | Should -Not -BeNullOrEmpty
            $subject.digest.sha256 | Should -Be $artifact.digest
        }
    }

    It 'fails when an attested digest does not match the real artifact hash' {
        # Statement attests the correct digest for two artifacts but a wrong
        # digest for the third: the real file hashes differently.
        $wrong = '0' * 64
        $bundle = New-AttestationBundle -SubjectSpec @(
            @{ name = 'dev-windows-x86_64.exe'; digest = $script:artifacts[0].digest }
            @{ name = 'DevNavSetup-x64.exe'; digest = $wrong }
            @{ name = 'DevNav-scoop-x64.zip'; digest = $script:artifacts[2].digest }
        )
        $bundlePath = Save-Bundle -Name 'mismatch.json' -Bundle $bundle

        { Invoke-Conversion -OutputName 'mismatch.jsonl' -BundlePath $bundlePath `
                -ExpectedSubject 'dev-windows-x86_64.exe', 'DevNavSetup-x64.exe', 'DevNav-scoop-x64.zip' |
            Out-Null } | Should -Throw '*real file hashes to*'
    }

    It 'fails when an expected artifact file does not exist on disk' {
        $bundle = New-AttestationBundle -SubjectSpec @(
            @{ name = 'ghost.exe'; digest = '1' * 64 }
        )
        $bundlePath = Save-Bundle -Name 'ghost.json' -Bundle $bundle

        { Invoke-Conversion -OutputName 'ghost.jsonl' -BundlePath $bundlePath `
                -ExpectedSubject 'ghost.exe' | Out-Null } | Should -Throw '*not found on disk*'
    }

    It 'rejects a renamed Sigstore bundle written as the jsonl content' {
        # Simulate the old, incorrect behavior: the whole bundle as one line.
        $bundle = New-AttestationBundle -SubjectSpec @(
            @{ name = 'dev-windows-x86_64.exe'; digest = $script:artifacts[0].digest }
        )
        $renamedPath = Join-Path $script:fixtureRoot 'renamed.jsonl'
        ($bundle | ConvertTo-Json -Compress -Depth 12) | Set-Content -LiteralPath $renamedPath
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
        { Invoke-Conversion -OutputName 'bad.jsonl' -BundlePath $badPath `
                -ExpectedSubject 'dev-windows-x86_64.exe' | Out-Null } | Should -Throw
    }
}
