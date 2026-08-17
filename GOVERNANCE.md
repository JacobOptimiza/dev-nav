# Governance

This document describes how decisions are made in DevNav and who holds which
role. It reflects the project as it exists today.

## Decision model

DevNav is a single-maintainer project under the ownership of
**JacobOptimiza**. The maintainer:

- defines the roadmap and scope (see [ROADMAP.md](ROADMAP.md));
- reviews and merges all pull requests — none are merged without passing CI;
- cuts releases and owns the release workflow and its credentials;
- maintains the distribution channels (GitHub Releases, npm trusted
  publishing, Scoop bucket, WinGet submissions).

Proposals and changes arrive through pull requests and issues. Anything that
passes the required gates (CI, CodeQL, coverage, repeatability) and the
maintainer's review can be merged. There is currently no steering committee
or voting process; the maintainer is the final decision authority.

## Roles and responsibilities

| Role | Held by | Responsibilities |
|---|---|---|
| Owner / maintainer | JacobOptimiza | Roadmap and scope decisions; review and merge of all changes; releases and tags; distribution-channel credentials (npm trusted publishing, Scoop bucket); security-response handling; dependency and advisory triage. |
| Emergency successor | sebassm | Designated to keep the project operational (issues, merges, releases) if the maintainer is unavailable. The successor's invitation has been accepted: `sebassm` is an effective collaborator of `JacobOptimiza/dev-nav` with **write** (push/triage) access, verified through the GitHub repository API. |

Contributors submit issues and pull requests; the maintainer may grant
additional collaborators the ability to triage issues. All participants are
subject to the [Code of Conduct](CODE_OF_CONDUCT.md).

## Access and continuity

The project's canonical artifacts live in public infrastructure that does not
depend on a single account: the repository, its history, and the CI
definitions are on GitHub, and every released artifact is reproducible from a
tagged commit (see [ASSURANCE.md](ASSURANCE.md) and
`scripts/verify-build-repeatability.ps1`).

Continuity of *maintenance* now has a working succession path. The emergency
successor `sebassm` holds effective **write** access to the repository
(verified via the GitHub API), which is sufficient to create and close issues,
review and merge pull requests, and publish a release: the release workflow is
versioned in this repository (`.github/workflows/release.yml`), and GitHub
Releases — the project's canonical artifact channel — is reachable with
repository write permissions. The project can therefore remain operational
within a short period if the maintainer becomes unavailable.

Two things are deliberately *not* claimed:

- **Bus factor stays 1.** Day-to-day maintenance still depends on the owner;
  the successor is an emergency path, not an active second maintainer.
- **External accounts are out of scope.** Nothing here asserts the successor's
  access to npm, Scoop, WinGet, or any other credential outside this
  repository.

## Changes to this document

Governance changes are ordinary changes to this file, proposed via pull
request and accepted by the maintainer.
