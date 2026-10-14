#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
#
# Import the history of the Realtek driver directory from a kernel tag.
#
# The kernel tree is cloned at <tag> (full history, that tag only), reduced to
# $UPSTREAM_PATH with git-filter-repo and that directory is moved to src/.
# The result is stored as branch "upstream" and tag "upstream/<tag>".
#
# git-filter-repo is deterministic: importing a newer tag reproduces exactly
# the same commits for the history both tags share. The new "upstream"
# branch can therefore simply be merged into main; only the commits between
# the two tags show up as new.
#
# Commit messages are kept verbatim (--preserve-commit-hashes), so "Fixes:"
# tags and "commit X upstream" lines keep referring to the kernel history.
#
# Usage: scripts/import-upstream.sh [-r <kernel-repo>] [-u <url>] <tag>
#
#   <tag>             kernel tag to import, e.g. Ubuntu-7.0.0-41.41
#   -r <kernel-repo>  clone from this local kernel repository instead of the
#                     network (much faster if you already have one)
#   -u <url>          kernel repository URL (default: UPSTREAM_URL from
#                     upstream.conf)
#
# Requires git-filter-repo (https://github.com/newren/git-filter-repo).

set -euo pipefail

usage() {
	sed -n '/^# Usage:/,/^[^#]/s/^# \{0,1\}//p' "$0" >&2
	exit 1
}

TOPDIR=$(git rev-parse --show-toplevel)
# shellcheck source=../upstream.conf
. "$TOPDIR/upstream.conf"

source=
url=$UPSTREAM_URL
while getopts "r:u:h" opt; do
	case $opt in
	r) source=$(realpath "$OPTARG") ;;
	u) url=$OPTARG ;;
	*) usage ;;
	esac
done
shift $((OPTIND - 1))
[ $# -eq 1 ] || usage
tag=$1

git filter-repo --version >/dev/null 2>&1 ||
	{ echo "git-filter-repo is required" >&2; exit 1; }

if git -C "$TOPDIR" rev-parse -q --verify "refs/tags/upstream/$tag" >/dev/null; then
	echo "Tag upstream/$tag already exists" >&2
	exit 1
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

echo "Cloning $tag from ${source:-$url} ..."
git clone --bare --single-branch --no-tags --branch "$tag" \
	"${source:-$url}" "$work/kernel.git"

commit=$(git -C "$work/kernel.git" rev-parse "HEAD^{commit}")

# Leave exactly one ref to rewrite: the tagged commit.
git -C "$work/kernel.git" for-each-ref --format='delete %(refname)' |
	git -C "$work/kernel.git" update-ref --stdin
git -C "$work/kernel.git" update-ref refs/heads/import "$commit"
git -C "$work/kernel.git" symbolic-ref HEAD refs/heads/import

echo "Filtering history of $UPSTREAM_PATH ..."
# Keep these options stable: changing them changes the rewritten commit IDs
# and breaks merging future imports into main.
git -C "$work/kernel.git" filter-repo --force \
	--path "$UPSTREAM_PATH/" \
	--path-rename "$UPSTREAM_PATH/:src/" \
	--preserve-commit-hashes \
	--prune-empty auto \
	--prune-degenerate auto \
	--replace-refs delete-no-add

git -C "$TOPDIR" fetch --no-tags "$work/kernel.git" \
	"+refs/heads/import:refs/heads/upstream"
git -C "$TOPDIR" tag "upstream/$tag" upstream

cat <<EOF

Imported $tag ($commit) as branch "upstream" and tag "upstream/$tag".

To move main to the new base:

  git merge upstream/$tag
  # resolve conflicts, drop backports that are now part of upstream
  # compare the r8169 patches of the matching Proxmox kernel (pve-kernel,
  # patches/kernel/) with the ones in main and adjust
  # set in upstream.conf:
  #   UPSTREAM_TAG=$tag
  #   UPSTREAM_COMMIT=$commit
  # review BUILD_EXCLUSIVE_KERNEL(_MIN) in dkms.conf and the Kbuild object list
  dch -v <new-version> "Rebase onto $tag."
EOF
