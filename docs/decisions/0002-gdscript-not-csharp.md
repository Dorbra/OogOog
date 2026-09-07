# ADR-0002: GDScript, not C#

**Status:** Accepted · M0

## Context

Godot supports both. C# is the more familiar language for someone with a
backend/DevOps background, has better tooling, and is statically typed. That is
a genuine pull, so the reason to refuse it needs to be concrete.

## Decision

**GDScript**, everywhere.

The deciding facts are about Godot's C# support on Android specifically, not
about the languages:

- The C# **Android export is experimental**.
- It is limited to **arm64 and x64** only.
- Its `monovm` runtime was **deprecated as of .NET 9**, with **no NativeAOT on
  Android**.
- JIT startup is measurably slower — and on a phone, launch time is the first
  thing anyone notices.

Under the no-PC constraint, "experimental" is disqualifying. There is no local
debugger to fall back on when an experimental export path misbehaves; the only
diagnostic channel is a log file read through an in-game panel.

## Consequences

**Good:** the fully supported path, faster startup, smaller builds, and every
Godot answer online applies directly.

**Bad:**
- No static type checking beyond GDScript's optional hints. Mitigated by
  `gdlint` and by keeping the simulation pure and unit-tested.
- **Lambdas capture by value.** This has caused three separate bugs here —
  counters assigned inside signal handlers silently never update. It is
  documented in [ARCHITECTURE.md §10](../ARCHITECTURE.md#the-gdscript-trap-that-has-caused-three-bugs-here)
  and commented at every site that relies on the workaround.
- `Dictionary` returned from a pool cannot be compared to `null` — `x == null` is
  always false for a Dictionary, so an exhausted pool silently wrote into a
  throwaway object until `is_empty()` replaced it.

## Alternatives

| | Verdict |
|---|---|
| C# | Rejected — experimental Android export, deprecated runtime, no NativeAOT |
| GDExtension (C++) | Rejected — a build toolchain per platform, for a game that is not remotely CPU-bound |
