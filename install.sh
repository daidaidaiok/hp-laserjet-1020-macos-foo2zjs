#!/bin/sh
#
# Install ./build into /Library/Printers/foo2zjs and create a CUPS queue.
#
#   sudo ./install.sh                  # auto-detect the USB printer
#   ./install.sh --dry-run             # print what would be done
#   sudo ./install.sh --uri usb://...  # pick the device explicitly
#   sudo ./install.sh --queue NAME     # queue name (default HP_LaserJet_1020_foo2zjs)
#
# Existing queues are left alone; only the queue named above is (re)created.
#
# SPDX-License-Identifier: GPL-2.0-or-later

set -eu

cd "$(dirname "$0")"
ROOT=$(pwd)
B=$ROOT/build
DEST=/Library/Printers/foo2zjs
QUEUE=HP_LaserJet_1020_foo2zjs
URI=
DRY=

die() { echo "错误：$1" >&2; exit 1; }
run() { if [ -n "$DRY" ]; then echo "$*"; else "$@"; fi; }

while [ $# -gt 0 ]; do
    case "$1" in
    --dry-run) DRY=1;;
    --uri) URI=$2; shift;;
    --queue) QUEUE=$2; shift;;
    *) die "未知参数 $1";;
    esac
    shift
done

for f in bin/foo2zjs bin/sc-deviceid bin/gs firmware/sihp1020.dl ghostscript/Resource/Init/gs_init.ps; do
    [ -e "$B/$f" ] || die "缺少 build/$f，请先运行 ./build.sh"
done
[ -n "$DRY" ] || [ "$(id -u)" -eq 0 ] || die "需要 root：sudo $0"

if [ -z "$URI" ]; then
    URI=$(/usr/libexec/cups/backend/usb 2>/dev/null \
        | awk '$2 ~ /LaserJet%201020/ {print $2}')
    case $(printf '%s' "$URI" | grep -c .) in
    0) die "没有找到 USB 连接的 HP LaserJet 1020，确认打印机已开机并切到本机";;
    1) ;;
    *) die "找到多台 1020，请用 --uri 指定：
$URI";;
    esac
fi
echo "设备：$URI"
echo "队列：$QUEUE"
[ -e "$DEST" ] && echo "注意：$DEST 已存在，将被覆盖"

run install -d -o root -g wheel -m 755 \
    "$DEST" "$DEST/bin" "$DEST/filter" "$DEST/firmware" "$DEST/ppd" "$DEST/share"
run install -o root -g wheel -m 755 "$B/bin/foo2zjs" "$B/bin/sc-deviceid" "$B/bin/gs" "$DEST/bin/"
run rm -rf "$DEST/share/ghostscript"
run cp -R "$B/ghostscript" "$DEST/share/ghostscript"
run chown -R root:wheel "$DEST/share/ghostscript"
run chmod -R go-w "$DEST/share/ghostscript"
run install -o root -g wheel -m 644 "$B/firmware/sihp1020.dl" "$DEST/firmware/"
run install -o root -g wheel -m 755 "$ROOT/filter/pdftozjs-1020" "$DEST/filter/"
run install -o root -g wheel -m 644 "$ROOT/ppd/HP-LaserJet-1020-foo2zjs.ppd" "$DEST/ppd/"

run lpadmin -p "$QUEUE" -E -v "$URI" \
    -P "$DEST/ppd/HP-LaserJet-1020-foo2zjs.ppd" \
    -D "HP LaserJet 1020 (foo2zjs)" -o printer-is-shared=false

if [ -n "$DRY" ]; then
    echo "（dry-run，未做任何改动）"
else
    echo "完成：在打印对话框里选择「HP LaserJet 1020 (foo2zjs)」"
fi
