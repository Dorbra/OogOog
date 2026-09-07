# OogOog documentation

Start here.

| Document | Answers |
|---|---|
| **[ARCHITECTURE.md](ARCHITECTURE.md)** | How the code is structured, what depends on what, and which invariants break things quietly when violated |
| **[GAME_DESIGN.md](GAME_DESIGN.md)** | What the game is, which mechanics serve that, what is planned, and what has been deliberately refused |
| **[CICD.md](CICD.md)** | The pipeline, the eleven gates and what each one catches, how publishing works, and the incident log |
| **[NO_PC_WORKFLOW.md](NO_PC_WORKFLOW.md)** | The constraint that shapes every other decision: there is no development machine |
| **[decisions/](decisions/)** | ADRs — one file per decision, with the reasoning, the cost, and what was rejected |

Plus, at the repo root: **[CONTRIBUTING.md](../CONTRIBUTING.md)** for the branch
workflow and the gate to run before pushing.

---

## Reading order

**New to the project?** `NO_PC_WORKFLOW.md` → `ARCHITECTURE.md` §1–4 →
`GAME_DESIGN.md` §1–4. That is roughly 20 minutes and covers why everything else
looks the way it does.

**Changing gameplay?** `GAME_DESIGN.md`, then `ARCHITECTURE.md` §5 (the
simulation) and §10 (invariants).

**Changing CI or the pipeline?** `CICD.md`, especially §7 — every gate in there
exists because something reached a device broken, and the incident is more useful
than the fix.

**About to argue with a past decision?** Find its ADR first. It records what was
rejected and why, which is usually the part being re-derived.

---

## The four things that explain the rest

1. **There is no development machine.** Every artifact is built by CI. This is
   the root constraint, and roughly half the tooling in the repo exists to make
   a ~6-minute feedback loop survivable.
2. **The simulation never reads input and never touches a sprite.** It is why
   combat logic is testable at all without a display.
3. **No feel constant is a literal.** 49 tuning keys, adjustable on the phone at
   runtime, because "does this feel right" is answered with thumbs.
4. **Verify the artifact, not the process.** A green run says the pipeline
   worked. It says nothing about whether the thing a player installs contains a
   map — which it did not, for two merged PRs.

---

## Keeping these honest

Documentation that drifts is worse than none, because it is believed. Three
rules:

- **An ADR is immutable once merged.** Reversing a decision means a new ADR that
  supersedes it. The old file stays.
- **Every ADR states its cost.** One with no downside in it is marketing.
- **A change that invalidates a document updates it in the same PR.** The PR
  template's verification checklist is the prompt.
