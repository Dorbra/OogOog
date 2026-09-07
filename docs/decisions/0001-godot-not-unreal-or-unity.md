# ADR-0001: Godot 4.7, not Unreal or Unity

**Status:** Accepted · M0

## Context

The request was "an Android game, I was thinking Unreal Engine, but I'm no
mobile expert". The requirements that actually constrain the choice:

- Flat 2D, top-down, single player.
- Must be **free** — stated explicitly.
- **No development machine.** Every build comes from CI.

That last one is not a preference. It eliminates any engine whose authoring
story assumes an editor, and it makes CI build time a first-order cost rather
than an annoyance.

## Decision

**Godot 4.7.1**, pinned in `.godot-version` and verified against the workflow's
`GODOT_VERSION` on every run.

### Not Unreal

|  | Godot 4.7 | Unreal 5 |
|---|---|---|
| Empty-project APK | ~25–40 MB | ~150–300 MB |
| CI build time | 3–5 min | 20–60 min |
| Authoring without an editor | Text scenes, scriptable | Effectively requires the editor |
| Android toolchain | SDK + JDK, forgiving | Exact NDK pinning, brittle |

Unreal's real strengths — photoreal 3D, Nanite, Lumen, large worlds — are all
irrelevant to a flat 2D phone game. Meanwhile a 20–60 minute CI build would make
the *only* feedback loop unusable, and "no editor" is close to fatal for Unreal
authoring.

### Not Unity — and the stated premise was wrong

**Unity is free here.** Unity Personal is free under $200k combined revenue and
funding, the Runtime Fee was cancelled in September 2024, and the splash screen
is optional in Unity 6. Cost is not the reason to skip it, and it would have been
wrong to let that go uncorrected.

The actual reasons: Unity in CI requires **licence activation on every runner**,
which is recurring friction Godot simply does not have. And its genuine
advantages — Asset Store art, first-party ads and IAP, Photon netcode — map onto
exactly the things this project is not building.

Godot is MIT: no account, no revenue threshold, nothing to re-check later.

## Consequences

**Good:** small APKs, fast CI, real headless tooling, no licensing surface.

**Bad, stated honestly:**
- Smaller ecosystem — fewer answers when stuck, and that has cost time.
- 4.7.1 was ~2 months old at adoption. Mobile and web export regressions are
  plausible. Mitigated by pinning; 4.6.x is the escape hatch.
- No Asset Store means art is hand-made or absent. This is a real ceiling,
  named in [GAME_DESIGN.md §6](../GAME_DESIGN.md#6-art-direction).

## Alternatives

| | Verdict |
|---|---|
| Unreal 5 | Rejected — build times and editor dependence are disqualifying under the no-PC constraint |
| Unity 6 | Rejected on CI friction, **not** cost. The premise that it is paid was corrected |
| Raw framework (SDL, libGDX, Bevy) | Rejected — would mean writing export pipelines, touch input and a renderer by hand, all of which Godot ships |
