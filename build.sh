#!/bin/sh
#
# Build everything the installer needs into ./build.
# Runs as a normal user and changes nothing outside this directory.
#
#   ./build.sh                 # use the gs found in PATH
#   GS=/path/to/gs ./build.sh  # use a specific Ghostscript
#
# SPDX-License-Identifier: GPL-2.0-or-later

set -eu

cd "$(dirname "$0")"
ROOT=$(pwd)
B=$ROOT/build
WORK=$B/work

FOO2ZJS_REPO=https://github.com/OpenPrinting/foo2zjs.git
FOO2ZJS_COMMIT=80499ed5bf6caa2963ad337e37cfda78a80aab1e
# Same source foo2zjs's own `getweb 1020` uses. HP firmware, not redistributed here.
FW_URL=https://www.quirinux.org/printers/sihp1020.tar.gz
FW_IMG_SHA256=9d10d8e84a9577f268aac6336ed18cf9235e6f732c1f68e8913c787db60106ce
CC=/usr/bin/clang

step() { printf '\n==> %s\n' "$1"; }
die() { echo "错误：$1" >&2; exit 1; }

[ -x "$CC" ] || die "找不到 $CC，请先运行 xcode-select --install"

rm -rf "$B"
mkdir -p "$B/bin" "$B/firmware" "$WORK"

step "编译 foo2zjs（OpenPrinting/foo2zjs@$(echo "$FOO2ZJS_COMMIT" | cut -c1-7)）"
git clone --quiet "$FOO2ZJS_REPO" "$WORK/foo2zjs"
git -C "$WORK/foo2zjs" checkout --quiet "$FOO2ZJS_COMMIT"
# macOS has no system libjbig; link the copy bundled with foo2zjs instead.
make -C "$WORK/foo2zjs" CC="$CC" LIBJBG="jbig.o jbig_ar.o" \
    jbig.o jbig_ar.o foo2zjs arm2hpdl >/dev/null
cp "$WORK/foo2zjs/foo2zjs" "$B/bin/"

step "下载并转换 HP LaserJet 1020 固件"
curl -fsSL --max-time 120 -o "$WORK/sihp1020.tar.gz" "$FW_URL"
tar -xzf "$WORK/sihp1020.tar.gz" -C "$WORK" sihp1020.img
echo "$FW_IMG_SHA256  $WORK/sihp1020.img" | shasum -a 256 -c - >/dev/null \
    || die "固件 SHA-256 校验失败"
"$WORK/foo2zjs/arm2hpdl" "$WORK/sihp1020.img" > "$B/firmware/sihp1020.dl"
head -c 64 "$B/firmware/sihp1020.dl" | grep -q 'ENTER LANGUAGE=ACL' \
    || die "转换后的固件格式不对"

step "编译 sc-deviceid（通过 CUPS side channel 读取设备 ID）"
"$CC" -O2 -Wall -Wno-deprecated-declarations \
    -o "$B/bin/sc-deviceid" "$ROOT/src/sc-deviceid.c" -lcups

step "收集 Ghostscript"
GS=${GS:-$(command -v gs || true)}
[ -n "$GS" ] || die "找不到 gs，见 README「依赖」一节"
GS=$(realpath "$GS")
# The cupsd sandbox only lets filters exec from places like /Library/Printers,
# so gs is copied there. It must not depend on libraries outside the OS.
# Dependency lines are tab-indented; skip the per-architecture headers.
DEPS=$(otool -L "$GS" | awk '/^\t/ {print $1}' \
    | grep -vE '^(/usr/lib/|/System/)' | sort -u || true)
if [ -n "$DEPS" ]; then
    echo "$GS 依赖系统以外的库：" >&2
    echo "$DEPS" | sed 's/^/    /' >&2
    die "需要一个自包含的 gs（例如 MacTeX 的 Ghostscript 安装包），见 README"
fi
INIT=$("$GS" -h 2>/dev/null | sed -n '/Search path:/{n;p;}' | awk '{print $1}')
GSROOT=$(dirname "$(dirname "$INIT")")
[ -f "$GSROOT/Resource/Init/gs_init.ps" ] || die "找不到 gs 资源目录（$GSROOT）"
cp "$GS" "$B/bin/gs"
cp -R "$GSROOT" "$B/ghostscript"
echo "gs $("$GS" --version)：$GS"
echo "资源：$GSROOT"

rm -rf "$WORK"
step "完成，下一步：sudo ./install.sh"
