# Architecture Decision Records

One file per decision that would be expensive to reverse or that a newcomer
would otherwise re-litigate. Format is [Michael Nygard's][nygard], lightly
adapted: **Context → Decision → Consequences → Alternatives**.

[nygard]: https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions

## Rules

- **An ADR is immutable once merged.** Reversing a decision means a *new* ADR
  that supersedes the old one; the old file stays, marked `Superseded by ADR-n`.
  The history of what was believed and why is the point.
- **Record the cost.** An ADR with no downside in it is marketing, not
  engineering.
- **Record what was rejected, and why.** Most of the value is here — it is what
  stops the same argument being had twice.

## Index

| # | Decision | Status |
|---|---|---|
| [0001](0001-godot-not-unreal-or-unity.md) | Godot 4.7, not Unreal or Unity | Accepted |
| [0002](0002-gdscript-not-csharp.md) | GDScript, not C# | Accepted |
| [0003](0003-sim-view-split.md) | Split simulation from view | Accepted |
| [0004](0004-runtime-tuning.md) | No feel constant is a literal | Accepted |
| [0005](0005-text-first-authoring.md) | Text-first authoring | Accepted |
| [0006](0006-two-delivery-channels.md) | Two delivery channels | Accepted |
| [0007](0007-typed-sim-events.md) | Typed sim events, not polling | Accepted |
| [0008](0008-no-physics-engine.md) | Pure-maths collision, no physics engine | Accepted |
| [0009](0009-pool-combat-objects.md) | Pool everything spawned in combat | Accepted |
| [0010](0010-branch-per-feature.md) | Branch per feature, PR builds to the phone | Accepted |
| [0011](0011-pages-from-a-branch.md) | Publish Pages from a branch | Accepted, supersedes part of 0006 |
| [0012](0012-verify-inside-the-artifact.md) | Verify the artifact, not the process | Accepted |
