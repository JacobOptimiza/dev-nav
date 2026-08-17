# Release signing

DevNav release artifacts are signed cryptographically with
[Sigstore](https://www.sigstore.dev/) cosign in keyless mode, using GitHub
Actions OIDC. There is no persistent private key: each signature is produced
inside the GitHub Actions runner by a short-lived certificate issued by Fulcio
and recorded in the Rekor transparency log.

## What is signed

- **v0.13.0 (retroactive):** the 12 distributed artifacts of the release
  (installers, binaries, PowerShell module files, Scoop/WinGet packages and
  metadata). Bundles live in [`signatures/v0.13.0/`](signatures/v0.13.0/).
- **Future releases:** every artifact is signed by
  `.github/workflows/release.yml` before the GitHub Release is created, and the
  `.sigstore.json` bundles are published alongside the assets. The workflow's
  `actions/attest` build-provenance bundles are also published as
  `DevNav-build-provenance-<arch>.intoto.jsonl` assets in the standard in-toto
  JSONL form (one compact DSSE envelope per line), verifiable with
  `gh attestation verify`.

`signatures/<tag>/index.json` maps each artifact to its SHA-256 digest and its
bundle file.

## Expected issuer and signer identity

- OIDC issuer: `https://token.actions.githubusercontent.com`
- Certificate identity for the retroactive v0.13.0 signatures:
  `https://github.com/JacobOptimiza/dev-nav/.github/workflows/sign-release.yml@refs/heads/main`
- Certificate identity pattern for future releases:
  `https://github.com/JacobOptimiza/dev-nav/.github/workflows/release.yml@refs/tags/v<version>`

## Verifying a v0.13.0 artifact

Download the artifact from the release and the matching bundle from
`signatures/v0.13.0/`, then run:

```sh
cosign verify-blob \
  --bundle DevNavSetup-x64.exe.sigstore.json \
  --certificate-identity "https://github.com/JacobOptimiza/dev-nav/.github/workflows/sign-release.yml@refs/heads/main" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
  DevNavSetup-x64.exe
```

Repeat per artifact with its own bundle. A successful run prints
`Verified OK`. No public key file is needed: cosign verifies the Fulcio
certificate chain, the Rekor entry, and the issuer/identity claims from the
bundle.

For future releases, substitute the bundle and the certificate identity with
the `@refs/tags/v<version>` pattern above.

## Integrity vs provenance vs signature

- **SHA-256 checksums** (`SHA256SUMS.txt`, `release-manifest.json`) verify
  integrity: the file you downloaded matches what the release workflow
  produced.
- **Build attestations** (GitHub artifact attestations) prove provenance: the
  artifact was built by a specific workflow run of this repository.
- **Sigstore signatures** prove authenticity: a private key that never left
  the CI runner and whose identity was certified by Fulcio signed this exact
  blob, and the event is publicly auditable in Rekor.

The signatures are Sigstore keyless signatures, **not** Authenticode code
signing: the `dev-windows-*.exe` binaries and `DevNavSetup-*.exe` installers
do not carry an embedded Authenticode signature. Windows SmartScreen
reputation is unaffected by these bundles.
