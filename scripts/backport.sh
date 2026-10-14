#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
#
# Apply Linux kernel commits to the driver sources in src/.
#
# Each commit is turned into a patch, its paths are rewritten from
# $UPSTREAM_PATH/ to src/ and it is applied with "git am", which keeps the
# original author, date and message. A "(cherry picked from commit <sha>)"
# line is appended, like "git cherry-pick -x" does, naming the source tree
# for commits that are not in mainline (e.g. "... <sha> net-next").
#
# Only commits that exclusively touch $UPSTREAM_PATH/ are accepted.
#
# If a patch does not apply, "git am" stops and leaves the usual state
# behind. Resolve it (adapting the change, and noting how in the message,
# e.g. "[ context adjustment: ... ]"), then run "git am --continue" and add
# the "(cherry picked from ...)" or "(backported from ...)" line yourself.
#
# Usage: scripts/backport.sh [-C <linux-repo> | -t <tree>] [-n <name>] <commit>...
#
#   -C <linux-repo>   take the commits from a local Linux git repository
#   -t <tree>         download the commits from this tree on git.kernel.org
#                     (default: stable/linux, which contains mainline and all
#                     stable releases; e.g. netdev/net-next for commits that
#                     are not in mainline yet)
#   -n <name>         source tree name for the "(cherry picked from ...)"
#                     line, e.g. net-next (default: none for stable/linux and
#                     -C, the last component of <tree> otherwise)

set -euo pipefail

usage() {
	sed -n '/^# Usage:/,/^[^#]/s/^# \{0,1\}//p' "$0" >&2
	exit 1
}

TOPDIR=$(git rev-parse --show-toplevel)
# shellcheck source=../upstream.conf
. "$TOPDIR/upstream.conf"

linux=
tree=stable/linux
name=
while getopts "C:t:n:h" opt; do
	case $opt in
	C) linux=$OPTARG ;;
	t) tree=$OPTARG ;;
	n) name=$OPTARG ;;
	*) usage ;;
	esac
done
shift $((OPTIND - 1))
[ $# -ge 1 ] || usage
if [ -z "$name" ] && [ -z "$linux" ] && [ "$tree" != stable/linux ]; then
	name=${tree##*/}
fi

# a/drivers/net/ethernet/realtek/r8169_main.c -> r8169_main.c
strip=$(($(tr -cd / <<<"$UPSTREAM_PATH/" | wc -c) + 1))

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

for rev in "$@"; do
	patch="$work/patch"
	if [ -n "$linux" ]; then
		sha=$(git -C "$linux" rev-parse --verify "$rev^{commit}")
		git -C "$linux" format-patch -1 --stdout "$sha" >"$patch"
	else
		curl -fsSL "https://git.kernel.org/pub/scm/linux/kernel/git/$tree.git/patch/?id=$rev" \
			-o "$patch"
		sha=$(sed -n '1s/^From \([0-9a-f]\{40\}\) .*/\1/p' "$patch")
	fi
	[ -n "$sha" ] || { echo "$rev: could not determine commit ID" >&2; exit 1; }

	outside=$(sed -n 's|^diff --git a/\([^ ]*\) .*|\1|p' "$patch" |
		grep -v "^$UPSTREAM_PATH/" || true)
	if [ -n "$outside" ]; then
		echo "$sha touches files outside $UPSTREAM_PATH/:" >&2
		echo "$outside" >&2
		exit 1
	fi

	echo "Applying $(sed -n 's/^Subject: //p' "$patch" | head -n 1)"
	git -C "$TOPDIR" am -3 -p"$strip" --directory=src "$patch"

	# --cleanup=whitespace: kernel commit messages may contain lines
	# starting with '#' (e.g. "#include") that must not be dropped.
	msg=$(git -C "$TOPDIR" log -1 --format=%B)
	printf '%s\n(cherry picked from commit %s%s)\n' "$msg" "$sha" "${name:+ $name}" |
		git -C "$TOPDIR" commit --amend --quiet --cleanup=whitespace -F -
done
