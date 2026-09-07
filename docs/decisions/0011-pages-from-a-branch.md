# ADR-0011: Publish Pages from a branch, not the deployment API

**Status:** Accepted · supersedes the publishing mechanism in
[ADR-0006](0006-two-delivery-channels.md)

## Context

The web channel used `actions/deploy-pages`, which runs the job inside the
**`github-pages` environment**.

That environment carries a deployment-branch policy. This repository's was pinned
to `claude/godot-archer-arena` — whichever branch happened to be default when
Pages was first configured. Making `main` the default branch later did **not**
update it.

The result: every deploy from `main` was refused *before the job's first step*.
**The signature is worth memorising — a job that fails in about one second, has
no steps, and whose logs 404.** There is nothing to read because nothing ran.

It was invisible for hours for a second reason: the job carried
`continue-on-error: true`, so the *run* was green while the *job* failed. The
site served a six-hour-old build and nothing said so.

## Decision

**Publish the web build by pushing a `gh-pages` branch.**

```
gh-pages          served at
  /        ────▶  dorbra.github.io/OogOog/          main
  /pr/<n>/ ────▶  dorbra.github.io/OogOog/pr/<n>/   a pull request
```

Pushing a branch needs `contents: write` and nothing else — no environment, no
branch policy, **no gate that can refuse a job before it starts**. The workflow's
`pages: write` and `id-token: write` permissions were dropped entirely.

Three supporting rules:

1. **`continue-on-error` is banned on publish jobs.** A check expected to fail is
   worse than no check — it trains you to ignore red.
2. **The job polls the live URL and fails if it never returns 200.** A push is
   not a publish.
3. **Every publish rewrites the branch to a single orphan commit.** The debug
   wasm plus the `.pck` are ~37 MB; ordinary commits would reach ~700 MB of
   history in twenty builds, against GitHub's 1 GB soft limit.

## Consequences

**Good:**
- Real per-PR previews, each in its own directory, so a PR cannot overwrite the
  bookmarked URL and two PRs cannot overwrite each other. The shared-site
  last-writer-wins problem is gone.
- No dependence on a repository setting that cannot be read or changed from CI.
- A publish that does not reach the internet now fails loudly.

**Bad:**
- **The environment restriction still has to be cleared**, because branch-served
  Pages is built by GitHub's own `pages-build-deployment` workflow, which goes
  through that same environment. Moving to a branch removes *our* dependence on
  it, not GitHub's.
- Force-pushing a generated branch would be alarming anywhere else. It is safe
  only because nothing checks `gh-pages` out.
- Two workflows now force-push the same branch, so they must share a concurrency
  group. Getting that wrong would interleave two publishes.
- Cleanup is now our job: a closed PR's directory has to be deleted explicitly,
  or every merged PR leaves ~40 MB behind forever.

## Alternatives

| | Verdict |
|---|---|
| Fix the environment setting and keep `deploy-pages` | Rejected — restores a dependence on an unreadable setting, and still gives only one site with last-writer-wins |
| Main-only Pages, no PR previews | **Tried and reverted.** It removed the red X without giving previews, and its stated reason was based on a wrong diagnosis |
| External static host (Netlify, Cloudflare) | Rejected — another account, another token, another thing to keep working |
