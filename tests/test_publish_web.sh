#!/usr/bin/env bash
# Tests for tools/publish_web.sh against a local bare repository.
#
# The point of taking the remote as an argument is exactly this: the publish
# logic can be proven here, without GitHub, before it ever runs in CI. The
# properties that matter are the ones that are expensive to get wrong remotely —
# a root publish deleting live PR previews, and history growing by 37 MB a build.

set -euo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/tools/publish_web.sh"
ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT

REMOTE="${ROOT}/remote.git"
git init --quiet --bare "$REMOTE"

PASS=0
FAIL=0

ok() {
	if [ "$1" = "true" ]; then
		PASS=$((PASS + 1))
	else
		FAIL=$((FAIL + 1))
		echo "  FAIL: $2"
	fi
}

assert_file() {
	local path="$1" want="$2" msg="$3"
	if [ -f "$path" ] && [ "$(cat "$path")" = "$want" ]; then ok true "$msg"; else ok false "$msg"; fi
}

assert_missing() {
	if [ ! -e "$1" ]; then ok true "$2"; else ok false "$2"; fi
}

# Builds a fake web export whose index.html carries a marker we can identify.
make_web() {
	local dir="$1" marker="$2"
	rm -rf "$dir"
	mkdir -p "$dir"
	echo "$marker" > "${dir}/index.html"
	echo "wasm-${marker}" > "${dir}/index.wasm"
}

checkout() {
	rm -rf "${ROOT}/verify"
	git clone --quiet --branch gh-pages "$REMOTE" "${ROOT}/verify"
}

echo "== first publish creates the branch"
make_web "${ROOT}/web" "root-1"
"$SCRIPT" publish "$REMOTE" "" "${ROOT}/web" "root 1" > /dev/null
checkout
assert_file "${ROOT}/verify/index.html" "root-1" "root index.html published"
if [ -f "${ROOT}/verify/.nojekyll" ]; then ok true; else ok false ".nojekyll written"; fi

echo "== a PR preview lands in its own directory"
make_web "${ROOT}/web" "pr-3"
"$SCRIPT" publish "$REMOTE" "pr/3" "${ROOT}/web" "pr 3" > /dev/null
checkout
assert_file "${ROOT}/verify/pr/3/index.html" "pr-3" "preview published under pr/3"
assert_file "${ROOT}/verify/index.html" "root-1" "root untouched by a preview"

echo "== a second preview does not disturb the first"
make_web "${ROOT}/web" "pr-4"
"$SCRIPT" publish "$REMOTE" "pr/4" "${ROOT}/web" "pr 4" > /dev/null
checkout
assert_file "${ROOT}/verify/pr/3/index.html" "pr-3" "pr/3 survives pr/4"
assert_file "${ROOT}/verify/pr/4/index.html" "pr-4" "pr/4 published"

echo "== republishing the root REPLACES it but KEEPS previews"
# The regression this guards: clearing the root with a blanket delete would take
# the previews of every still-open pull request with it.
make_web "${ROOT}/web" "root-2"
"$SCRIPT" publish "$REMOTE" "" "${ROOT}/web" "root 2" > /dev/null
checkout
assert_file "${ROOT}/verify/index.html" "root-2" "root replaced"
assert_file "${ROOT}/verify/pr/3/index.html" "pr-3" "pr/3 survives a root publish"
assert_file "${ROOT}/verify/pr/4/index.html" "pr-4" "pr/4 survives a root publish"

echo "== a stale file at the root is not left behind"
echo "stale" > "${ROOT}/verify/leftover.html"
git -C "${ROOT}/verify" add -A > /dev/null
git -C "${ROOT}/verify" -c user.email=t@t -c user.name=t commit --quiet -m stale
git -C "${ROOT}/verify" push --quiet origin gh-pages
make_web "${ROOT}/web" "root-3"
"$SCRIPT" publish "$REMOTE" "" "${ROOT}/web" "root 3" > /dev/null
checkout
assert_missing "${ROOT}/verify/leftover.html" "stale root file removed"

echo "== history stays at exactly one commit"
# Six publishes have happened. With ordinary commits the branch would now carry
# six copies of every asset; at ~37 MB a build that is how a repository dies.
COMMITS=$(git -C "${ROOT}/verify" rev-list --count HEAD)
if [ "$COMMITS" = "1" ]; then ok true; else ok false "history is 1 commit (got ${COMMITS})"; fi

echo "== removing a preview"
"$SCRIPT" remove "$REMOTE" "pr/3" "drop pr 3" > /dev/null
checkout
assert_missing "${ROOT}/verify/pr/3" "pr/3 removed"
assert_file "${ROOT}/verify/pr/4/index.html" "pr-4" "pr/4 untouched by removing pr/3"
assert_file "${ROOT}/verify/index.html" "root-3" "root untouched by a removal"

echo "== removing something already gone is a no-op, not an error"
if "$SCRIPT" remove "$REMOTE" "pr/99" "drop pr 99" > /dev/null 2>&1; then
	ok true
else
	ok false "removing a missing preview exits 0"
fi

echo "== refuses to remove the site root"
if "$SCRIPT" remove "$REMOTE" "" "wipe" > /dev/null 2>&1; then
	ok false "empty dest rejected for remove"
else
	ok true
fi

echo "== refuses a dest that escapes the checkout"
make_web "${ROOT}/web" "evil"
if "$SCRIPT" publish "$REMOTE" "../../etc" "${ROOT}/web" "evil" > /dev/null 2>&1; then
	ok false "traversal in dest rejected"
else
	ok true
fi

echo "== refuses a web dir with no index.html"
rm -rf "${ROOT}/empty" && mkdir -p "${ROOT}/empty"
if "$SCRIPT" publish "$REMOTE" "" "${ROOT}/empty" "empty" > /dev/null 2>&1; then
	ok false "missing index.html rejected"
else
	ok true
fi

echo
if [ "$FAIL" -eq 0 ]; then
	echo "PASS — ${PASS} assertions"
else
	echo "FAIL — ${FAIL} failed, ${PASS} passed"
	exit 1
fi
