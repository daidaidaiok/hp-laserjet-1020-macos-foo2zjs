#!/bin/sh
#
# Run the installed filter inside the real cupsd sandbox without using paper.
# A temporary queue sends the output to a local listener; the result is
# checked for the firmware header and a ZjStream page.
#
#   sudo scripts/sandbox-test.sh file.pdf
#
# SPDX-License-Identifier: GPL-2.0-or-later

set -eu

Q=zjs_sandbox_test
PORT=9101
IN=${1:-}
[ -f "$IN" ] || { echo "用法：sudo $0 file.pdf" >&2; exit 1; }
[ "$(id -u)" -eq 0 ] || { echo "需要 root：sudo $0 $IN" >&2; exit 1; }

OUT=$(mktemp -t zjs-sandbox-test)
trap 'lpadmin -x $Q 2>/dev/null || true; rm -f "$OUT"' EXIT

/usr/bin/nc -l 127.0.0.1 $PORT > "$OUT" &
sleep 1

lpadmin -p $Q -E -v socket://127.0.0.1:$PORT \
    -P /Library/Printers/foo2zjs/ppd/HP-LaserJet-1020-foo2zjs.ppd 2>/dev/null
lp -d $Q -o media=A4 "$IN" >/dev/null

i=0
while [ -n "$(lpstat -o $Q 2>/dev/null)" ] && [ $i -lt 30 ]; do
    sleep 2; i=$((i + 1))
done
wait

SIZE=$(wc -c < "$OUT" | tr -d ' ')
echo "收到 $SIZE 字节"
# Over a socket the backend can't report FWVER, so the filter sends firmware first.
head -c 64 "$OUT" | grep -q 'ENTER LANGUAGE=ACL' && echo "✓ 固件头" || echo "✗ 没有固件头"
grep -aq 'JZJZ' "$OUT" && echo "✓ ZjStream 数据" || { echo "✗ 没有 ZjStream 数据，查看 /var/log/cups/error_log"; exit 1; }
