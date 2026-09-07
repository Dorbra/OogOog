## What

<!-- One or two sentences. What does this change do from the player's side? -->

## Why

<!-- The problem or the ask. If it came from a playtest, quote the actual complaint. -->

## How it was verified

Every box below runs locally before pushing (see CONTRIBUTING.md). CI repeats
them, plus the Android export.

- [ ] `gdformat --check` + `gdlint` clean
- [ ] `godot --headless --path . --import`
- [ ] Unit tests pass
- [ ] Headless boot smoke test passes
- [ ] Idle render + combat render produce screenshots
- [ ] Looked at the screenshots — they show what I expect

## Screenshot

<!-- Attach build/combat.png or build/shot.png. Nobody on this project can run
     the game locally, so a picture is the only proof the render path works. -->

## Notes for the reviewer

<!-- Anything unverifiable from here: things that need a real phone (feel,
     frame rate, thermals), or behaviour only reachable in a browser. -->
