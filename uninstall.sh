#!/bin/sh
#
# Remove the queue and /Library/Printers/foo2zjs.
#
#   ./uninstall.sh --dry-run       # print what would be removed
#   sudo ./uninstall.sh            # remove
#   sudo ./uninstall.sh --queue NAME
#
# SPDX-License-Identifier: GPL-2.0-or-later

set -eu

DEST=/Library/Printers/foo2zjs
QUEUE=HP_LaserJet_1020_foo2zjs
DRY=

die() { echo "错误：$1" >&2; exit 1; }
run() { if [ -n "$DRY" ]; then echo "$*"; else "$@"; fi; }

while [ $# -gt 0 ]; do
    case "$1" in
    --dry-run) DRY=1;;
    --queue) QUEUE=$2; shift;;
    *) die "未知参数 $1";;
    esac
    shift
done
[ -n "$DRY" ] || [ "$(id -u)" -eq 0 ] || die "需要 root：sudo $0"

if lpstat -p "$QUEUE" >/dev/null 2>&1; then
    run lpadmin -x "$QUEUE"
else
    echo "队列 $QUEUE 不存在，跳过"
fi
if [ -d "$DEST" ]; then
    [ -n "$DRY" ] && du -sh "$DEST"
    run rm -rf "$DEST"
else
    echo "$DEST 不存在，跳过"
fi
[ -n "$DRY" ] && echo "（dry-run，未做任何改动）"
exit 0
