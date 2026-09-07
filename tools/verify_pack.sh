#!/usr/bin/env bash
# Asserts that every runtime file the source references actually ends up inside
# the exported pack.
#
# This exists because of a bug that shipped to a real device. The arena is a
# `.txt` file, `export_filter` was "all_resources", and Godot does not consider
# a .txt a resource — so `data/arenas/arena_01.txt` was silently left out of
# every export. In the packaged game the map had zero cells, which meant zero
# walls, zero spawn points and a world of size zero: the ground drew into an
# empty rect, the player fell back to the origin, and the whole thing rendered
# as a grey void with a pond floating in it.
#
# Nothing caught it. The unit tests, the boot smoke test and the render tests
# all run the project FROM SOURCE, where the file is sitting on disk. The export
# step only ever checked that exporting succeeded, never that the artifact it
# produced contained what the game needs to run. That is the gap this closes.
#
# The required list is derived from the source rather than hardcoded, so a data
# file added later is covered automatically, without anyone remembering to
# update this script.
#
# Usage: verify_pack.sh <godot-binary> [preset]

set -euo pipefail

GODOT="${1:?usage: verify_pack.sh <godot-binary> [preset]}"
PRESET="${2:-Web}"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "exporting '${PRESET}' to verify its pack..."
"$GODOT" --headless --path . --export-debug "$PRESET" "${WORK}/index.html" > /dev/null

PCK="${WORK}/index.pck"
[ -s "$PCK" ] || {
	echo "::error::export produced no pack at ${PCK}"
	exit 1
}

# Every res:// path mentioned in src/, minus build artefacts (screenshot output)
# and directory-only references.
REQUIRED="$(
	grep -rho 'res://[A-Za-z0-9_/.-]*' src/ |
		grep -E '\.(txt|json|svg|png|tscn|tres)$' |
		grep -v '^res://build/' |
		sort -u
)"

[ -n "$REQUIRED" ] || {
	echo "::error::found no res:// file references in src/ — this check is not doing anything"
	exit 1
}

MISSING=0
FOUND=0
while IFS= read -r path; do
	# Two storage forms, and the check has to accept both. A real resource keeps
	# its full "res://…" path in the pack (an .svg is remapped to a .ctex but the
	# original path is still recorded). A file pulled in by include_filter is
	# stored WITHOUT the res:// prefix — "data/arenas/arena_01.txt". Matching only
	# the first form is what made this script report the JSON files missing when
	# they were present.
	bare="${path#res://}"
	if grep -qa -e "$path" -e "$bare" "$PCK"; then
		echo "  ok      ${path}"
		FOUND=$((FOUND + 1))
	else
		echo "  MISSING ${path}"
		MISSING=$((MISSING + 1))
	fi
done <<< "$REQUIRED"

if [ "$MISSING" -gt 0 ]; then
	echo "::error::${MISSING} file(s) referenced by src/ are not in the ${PRESET} pack."
	echo "::error::A non-resource extension (.txt and friends) needs an entry in"
	echo "::error::export_presets.cfg -> include_filter, or it is silently dropped."
	exit 1
fi

echo "pack verified: ${FOUND} referenced files all present"
