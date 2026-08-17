<#
.SYNOPSIS
    Extracts the DSSE envelope from a Sigstore attestation bundle and writes a
    standards-compliant in-toto .intoto.jsonl provenance file.

.DESCRIPTION
    `actions/attest` writes its output as a Sigstore bundle
    ({"mediaType": ..., "dsseEnvelope": {...}, "verificationMaterial": ...}).
    The DSSE/in-toto JSON Lines format instead requires each line to be the
    DSSE envelope itself ({"payloadType", "payload", "signatures"}).

    This script extracts bundle.dsseEnvelope, serializes it as a single
    compact JSON line, and then validates the result end-to-end before the
    caller publishes it: exactly one JSON object per line, DSSE envelope shape
    at the root (not a renamed Sigstore bundle), a decodable payload that is
    an in-toto Statement with a SLSA provenance predicateType, every expected
    artifact present as a subject, and each attested digest equal to the real
    SHA-256 of the artifact file on disk.

    Exits non-zero on any validation failure.

.EXAMPLE
    ./scripts/convert-attestation-to-intoto.ps1 -BundlePath attestation.json `
        -OutputPath DevNav-build-provenance-x64.intoto.jsonl `
        -ExpectedSubject dev-windows-x86_64.exe, DevNavSetup-x64.exe, DevNav-scoop-x64.zip
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $BundlePath,
    [Parameter(Mandatory)][string] $OutputPath,
    # Artifact names (without digest) that must appear as in-toto subjects
    # with digests matching the real files in the working directory.
    [Parameter(Mandatory)][string[]] $ExpectedSubject
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-JsonProperty {
    param([psobject] $Object, [string] $Name)
    return $null -ne ($Object.PSObject.Properties[$Name])
}

function ConvertFrom-Base64String {
    param([string] $Base64)
    return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Base64))
}

if (-not (Test-Path -LiteralPath $BundlePath -PathType Leaf)) {
    throw "Attestation bundle not found: $BundlePath"
}

$bundle = Get-Content -LiteralPath $BundlePath -Raw | ConvertFrom-Json

if (-not (Test-JsonProperty $bundle 'dsseEnvelope')) {
    throw 'The bundle has no dsseEnvelope member; unexpected actions/attest output shape.'
}

# --- Extract the DSSE envelope and write it as one compact JSON line. ---
$envelopeJson = $bundle.dsseEnvelope | ConvertTo-Json -Compress -Depth 32
[System.IO.File]::WriteAllText($OutputPath, $envelopeJson + "`n")

# =====================================================================
# Validation: everything below must hold before the file may be published.
# =====================================================================

# 1. Exactly one valid JSON object per line.
$lines = @(Get-Content -LiteralPath $OutputPath | Where-Object { $_.Length -gt 0 })
if ($lines.Count -ne 1) {
    throw "Expected exactly 1 JSON line, found $($lines.Count)."
}
$envelope = $lines[0] | ConvertFrom-Json

# 2. DSSE envelope shape at the root: payloadType, payload, signatures.
foreach ($member in @('payloadType', 'payload', 'signatures')) {
    if (-not (Test-JsonProperty $envelope $member)) {
        throw "DSSE envelope is missing required member '$member'."
    }
}

# 3. Not a renamed Sigstore bundle: Sigstore bundle fields must be absent.
foreach ($member in @('dsseEnvelope', 'verificationMaterial', 'mediaType')) {
    if (Test-JsonProperty $envelope $member) {
        throw "'$member' found at the root: this is a Sigstore bundle, not a DSSE envelope."
    }
}

if ($envelope.payloadType -ne 'application/vnd.in-toto+json') {
    throw "Unexpected payloadType '$($envelope.payloadType)'; expected 'application/vnd.in-toto+json'."
}
if (@($envelope.signatures).Count -lt 1) {
    throw 'DSSE envelope carries no signatures.'
}

# 4. Decoded payload is an in-toto Statement.
$statement = ConvertFrom-Base64String $envelope.payload | ConvertFrom-Json
if ($statement.'_type' -ne 'https://in-toto.io/Statement/v1') {
    throw "Unexpected in-toto statement _type '$($statement.'_type')'."
}

# 5. SLSA build provenance predicateType.
$slsaPredicateTypes = @(
    'https://slsa.dev/provenance/v1',
    'https://slsa.dev/provenance/v0.2'
)
if ($statement.predicateType -notin $slsaPredicateTypes) {
    throw "predicateType '$($statement.predicateType)' is not a SLSA provenance type."
}

# 6. Every expected artifact is a subject whose attested digest equals the
#    real SHA-256 of the file on disk.
$subjects = @($statement.subject)
if ($subjects.Count -eq 0) {
    throw 'The in-toto statement has no subjects.'
}
foreach ($expected in $ExpectedSubject) {
    $artifactPath = Join-Path (Get-Location) $expected
    if (-not (Test-Path -LiteralPath $artifactPath -PathType Leaf)) {
        throw "Expected artifact '$expected' not found on disk for digest verification."
    }
    $match = $subjects | Where-Object { $_.name -eq $expected }
    if (-not $match) {
        $found = ($subjects | ForEach-Object { $_.name }) -join ', '
        throw "Expected subject '$expected' not attested. Found: $found"
    }
    $realDigest = (Get-FileHash -LiteralPath $artifactPath -Algorithm SHA256).Hash.ToLowerInvariant()
    foreach ($s in @($match)) {
        if (-not $s.digest.sha256 -or $s.digest.sha256 -notmatch '^[0-9a-f]{64}$') {
            throw "Subject '$expected' lacks a valid sha256 digest."
        }
        if ($s.digest.sha256 -ne $realDigest) {
            throw "Subject '$expected' attests digest $($s.digest.sha256) but the real file hashes to $realDigest."
        }
    }
}

# 7. Structural presence of the signature material the bundle verification
#    relies on (cryptographic verification happens through the Sigstore
#    bundle, which carries the certificate and Rekor entries).
foreach ($signature in @($envelope.signatures)) {
    if ([string]::IsNullOrWhiteSpace($signature.sig)) {
        throw 'A DSSE signature has an empty sig value.'
    }
}

Write-Host "OK: $OutputPath is a valid in-toto/SLSA DSSE envelope (JSONL, 1 line, subjects and digests verified against the artifacts)."
exit 0
