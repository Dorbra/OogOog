# ADR-0010: Branch per feature, PR builds to the phone

**Status:** Accepted · M2

## Context

Early work went straight onto a long-lived branch. Once `main` became the default
and the project was expected to run like a real engineering effort, that stopped
being appropriate.

There is also a problem specific to a game: **whether something feels right is
not reviewable in a diff.** A PR that changes `draw_time_full` from 0.55 to 0.28
is a one-line diff whose entire value is unobservable in code review.

## Decision

**`main` is protected and always releasable. Everything goes through a branch and
a pull request — and every PR builds a playable artifact.**

| Prefix | For |
|---|---|
| `feat/` | New player-facing capability |
| `fix/` | Something is broken |
| `chore/` | Tooling, CI, refactors |
| `docs/` | Documentation only |

Opening a PR produces:
- a **`pr-<n>` prerelease** with an installable APK,
- a **web preview** at `/pr/<n>/`,
- a **sticky comment** carrying both, edited in place rather than appended, so
  the thread does not fill with build noise.

**So a change can be played on the phone before it is approved.** That matters
here more than in most projects.

## Consequences

**Good:**
- Review can be "I played it and the aim still drifts", which is the only review
  that means anything for a feel change.
- `main` stays releasable; the bookmarked `dev` link is always a real build.
- Per-PR tags mean two open PRs never fight over one release.

**Bad:**
- Ceremony for a solo developer. A one-line fix costs a branch, a PR, a CI run
  and a merge — and this has already been consciously bypassed once, when a
  six-line workflow fix was carried on an existing feature branch rather than
  split into a second PR that would have needed two merges on a phone.
- CI runs per PR push cost minutes and build minutes.
- **Branch protection cannot express "0 required approvals".** GitHub's count
  starts at 1, and any approval requirement deadlocks a solo repo because
  self-approval is forbidden. The correct setting is to require a PR and leave
  **"Require approvals" unchecked** — documented after the original instruction
  turned out to be un-followable.

## Alternatives

| | Verdict |
|---|---|
| Commit straight to `main` | Rejected — no artifact to play before it is live, and no gate |
| Trunk-based with feature flags | Rejected — flag machinery outweighs the benefit at this size |
| PRs without per-PR builds | Rejected — a diff cannot answer "does it feel right" |
