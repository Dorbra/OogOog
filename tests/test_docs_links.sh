#!/usr/bin/env bash
# Asserts every relative link in the Markdown docs resolves to a real file.
#
# Written after finding that project.godot had pointed at docs/NO_PC_WORKFLOW.md
# for several milestones while no such file existed. Documentation that lies is
# worse than none, because it gets believed — and a dead link is the cheapest,
# most common way for it to start lying.
#
# Only relative links are checked. External URLs are somebody else's uptime and
# checking them would make this gate flaky, which is its own failure mode.
#
# Usage: test_docs_links.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# --others --exclude-standard so files staged for a first commit are covered.
# Checking only tracked files would let a new doc land with dead links in the
# very PR that adds it, which is exactly when they are easiest to fix.
FILES="$(git ls-files --cached --others --exclude-standard '*.md')"
CHECKED=0
BROKEN=0

for file in $FILES; do
	dir="$(dirname "$file")"

	# Markdown inline links: [text](target). Strip any #anchor and drop
	# external schemes and bare anchors.
	targets="$(
		grep -oE '\]\([^)]+\)' "$file" |
			sed -E 's/^\]\(//; s/\)$//' |
			sed -E 's/#.*$//' |
			grep -vE '^(https?:|mailto:)' |
			grep -vE '^$' || true
	)"

	for target in $targets; do
		CHECKED=$((CHECKED + 1))
		resolved="$(realpath -m --relative-to="$ROOT" "${dir}/${target}")"

		# A link that climbs above the repo root is a GitHub UI shortcut, not a
		# file path — "../../releases/tag/dev" resolves against the repo URL on
		# github.com. Nothing on disk to check.
		case "$resolved" in
			../*) continue ;;
		esac

		if [ ! -e "$ROOT/$resolved" ]; then
			echo "  BROKEN  ${file} -> ${target}"
			BROKEN=$((BROKEN + 1))
		fi
	done
done

# Anything in the repo that points at docs/ outside Markdown — project.godot
# carries such a pointer, and that is exactly the one that was dead.
for ref in $(grep -rhoE 'docs/[A-Za-z0-9_/.-]+\.md' --include='*.godot' --include='*.cfg' --include='*.gd' . || true); do
	CHECKED=$((CHECKED + 1))
	if [ ! -e "$ref" ]; then
		echo "  BROKEN  (non-markdown reference) -> ${ref}"
		BROKEN=$((BROKEN + 1))
	fi
done

if [ "$BROKEN" -gt 0 ]; then
	echo "::error::${BROKEN} broken link(s) across ${CHECKED} checked"
	exit 1
fi

echo "PASS — ${CHECKED} relative links resolve"
