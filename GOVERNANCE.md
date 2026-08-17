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
| Emergency successor | sebassm | Designated to keep the project operational (issues, merges, releases) if the maintainer is unavailable. **Currently pending**: the successor's repository invitation has been sent but not yet accepted, so effective access cannot be verified yet. |

Contributors submit issues and pull requests; the maintainer may grant
additional collaborators the ability to triage issues. All participants are
subject to the [Code of Conduct](CODE_OF_CONDUCT.md).

## Access and continuity

The project's canonical artifacts live in public infrastructure that does not
depend on a single account: the repository, its history, and the CI
definitions are on GitHub, and every released artifact is reproducible from a
tagged commit (see [ASSURANCE.md](ASSURANCE.md) and
`scripts/verify-build-repeatability.ps1`).

Continuity of *maintenance* currently depends on the owner: bus factor is 1
today and is honestly reported as such. The emergency-successor role exists
so the project can continue with minimal interruption, but the successor's
access is **not yet effective** (invitation pending acceptance). Until the
successor has confirmed access — repository write permissions and the ability
to create and close issues, merge changes, and publish a release within a
week of a confirmed loss of support — the project does not claim to satisfy
any continuity requirement.

## Changes to this document

Governance changes are ordinary changes to this file, proposed via pull
request and accepted by the maintainer.
