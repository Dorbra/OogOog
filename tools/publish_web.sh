#!/usr/bin/env bash
# Publish (or remove) a web build on the `gh-pages` branch.
#
# GitHub Pages is served from a branch here rather than through the Pages
# deployment API, for one concrete reason: the API route goes through the
# `github-pages` *environment*, which carries a deployment-branch policy. When
# that policy does not match the branch, GitHub refuses the job before any step
# runs — one second, no steps, no downloadable log. That failure mode is
# undiagnosable from the run page and it silently served a stale site for hours.
# Pushing a branch needs only `contents: write` and has no such gate.
#
# Layout on the branch:
#   /            the build from `main`  -> dorbra.github.io/OogOog/
#   /pr/<n>/     a pull request preview -> dorbra.github.io/OogOog/pr/<n>/
#
# HISTORY IS REWRITTEN ON EVERY PUBLISH, deliberately. The debug wasm plus the
# .pck are ~37 MB; an ordinary commit per build would add that to git history
# every time — around 700 MB after twenty builds, against GitHub's 1 GB soft
# limit. Each publish therefore rebuilds the branch as a single orphan commit
# holding the current tree and force-pushes it. Nothing checks this branch out,
# so there is no history to preserve and nobody's clone to invalidate. This is
# what peaceiris/actions-gh-pages calls `force_orphan`.
#
# Usage:
#   publish_web.sh publish <remote> <dest> <web_dir> <message>
#   publish_web.sh remove  <remote> <dest> <message>
#
#   <dest>  "" for the site root, or a subdirectory such as "pr/3".
#
# The remote may be any git URL, a local path included — which is what makes
# this testable without touching GitHub. See tests/test_publish_web.sh.

set -euo pipefail

BRANCH="gh-pages"
GIT_NAME="${GIT_AUTHOR_NAME:-github-actions[bot]}"
GIT_EMAIL="${GIT_AUTHOR_EMAIL:-41898282+github-actions[bot]@users.noreply.github.com}"

MODE="${1:?usage: publish_web.sh publish|remove ...}"
REMOTE="${2:?remote required}"
DEST="${3-}"

case "$MODE" in
	publish)
		WEB_DIR="${4:?web_dir required}"
		MESSAGE="${5:?message required}"
		[ -f "${WEB_DIR}/index.html" ] || {
			echo "::error::${WEB_DIR}/index.html missing — nothing to publish"
			exit 1
		}
		WEB_DIR="$(cd "$WEB_DIR" && pwd)"
		;;
	remove)
		MESSAGE="${4:?message required}"
		[ -n "$DEST" ] || {
			echo "::error::refusing to remove the site root"
			exit 1
		}
		;;
	*)
		echo "::error::unknown mode '${MODE}'"
		exit 1
		;;
esac

# A dest of "../.." would escape the checkout and rm -rf something else.
case "$DEST" in
	/* | *..*)
		echo "::error::dest must be a relative path without '..' (got '${DEST}')"
		exit 1
		;;
esac

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
SITE="${WORK}/site"

# The branch will not exist on the very first run, and that is not an error.
if git clone --quiet --depth 1 --branch "$BRANCH" "$REMOTE" "$SITE" 2>/dev/null; then
	echo "cloned existing ${BRANCH}"
else
	echo "${BRANCH} does not exist yet — creating it"
	git init --quiet -b "$BRANCH" "$SITE"
	git -C "$SITE" remote add origin "$REMOTE"
fi

git -C "$SITE" config user.name "$GIT_NAME"
git -C "$SITE" config user.email "$GIT_EMAIL"

if [ "$MODE" = "remove" ]; then
	if [ ! -d "${SITE}/${DEST}" ]; then
		echo "${DEST} is not on the branch — nothing to remove"
		exit 0
	fi
	rm -rf "${SITE:?}/${DEST}"
	# Drop now-empty parents (pr/ once its last preview goes) so the branch does
	# not accumulate empty directories git would not track anyway.
	rmdir -p "$(dirname "${SITE}/${DEST}")" 2>/dev/null || true
else
	if [ -z "$DEST" ]; then
		# Replacing the root must NOT take the PR previews with it: they belong to
		# pull requests that are still open, and a push to main is not a reason to
		# delete them.
		find "$SITE" -mindepth 1 -maxdepth 1 \
			! -name '.git' ! -name 'pr' -exec rm -rf {} +
		TARGET="$SITE"
	else
		rm -rf "${SITE:?}/${DEST}"
		TARGET="${SITE}/${DEST}"
	fi
	mkdir -p "$TARGET"
	cp -R "${WEB_DIR}/." "$TARGET"/
fi

# Jekyll is on by default for branch-served Pages and would rewrite or drop
# files it does not recognise. Godot's export has no use for it.
touch "${SITE}/.nojekyll"

# Rebuild the branch as exactly one commit (see the note at the top).
git -C "$SITE" checkout --quiet --orphan publish-tmp
git -C "$SITE" add -A
if git -C "$SITE" diff --cached --quiet; then
	echo "nothing to publish — tree is unchanged"
	exit 0
fi
git -C "$SITE" commit --quiet -m "$MESSAGE"
git -C "$SITE" branch --quiet -M publish-tmp "$BRANCH"

# push.negotiate is disabled explicitly: the local clone is shallow and its
# history was just replaced, so negotiation has nothing to agree on and git logs
# a "push negotiation failed; proceeding anyway" warning that looks like a real
# problem in a CI log and is not one.
for attempt in 1 2 3 4; do
	if git -C "$SITE" -c push.negotiate=false push --force --quiet origin "$BRANCH"; then
		echo "pushed ${BRANCH} (${DEST:-root})"
		exit 0
	fi
	echo "push failed (attempt ${attempt})"
	[ "$attempt" -lt 4 ] && sleep $((2 ** attempt))
done

echo "::error::could not push ${BRANCH} after 4 attempts"
exit 1
