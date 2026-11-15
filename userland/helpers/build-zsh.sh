#!/bin/bash
# Build arm64e zsh for the guest (dropbear login shell). Same source pin as ownervisor tools/zsh.py.
#
#   userland/helpers/build-zsh.sh [OUT_DIR]
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)
OUT=${1:-$REPO/out/userland/helpers}
TAG=zsh-118
URL="https://github.com/apple-oss-distributions/zsh/archive/refs/tags/${TAG}.tar.gz"
SHA256=9ee07990dca582d977ecb99f0f4396c301c5d197e29e9ea6be1d23fbe0ec9ce0
WORK=$REPO/out/userland/zsh-armv8e/work

. "$REPO/scripts/ios/env.sh"
mkdir -p "$OUT" "$WORK"
macos_sdk=$(xcrun --sdk macosx --show-sdk-path)
tarball=$WORK/${TAG}.tar.gz
if [ ! -f "$tarball" ] || [ "$(openssl dgst -sha256 "$tarball" | awk '{print $2}')" != "$SHA256" ]; then
  curl -fsSL -o "$tarball" "$URL"
fi
if [ "$(openssl dgst -sha256 "$tarball" | awk '{print $2}')" != "$SHA256" ]; then
  echo "build-zsh.sh: tarball sha256 mismatch" >&2; exit 1
fi
top=$WORK/zsh-$TAG
rm -rf "$top"
tar -xzf "$tarball" -C "$WORK"
# Directory name inside the archive is zsh-zsh-118
tree=$WORK/zsh-zsh-118
[ -d "$tree/zsh" ] || tree=$top
src=$tree/zsh
[ -d "$src" ] || { echo "build-zsh.sh: no zsh sources under $WORK" >&2; exit 1; }

shim=$WORK/shim
rm -rf "$shim"
mkdir -p "$shim/System/sys"
for header in curses.h ncurses.h ncurses_dll.h term.h termcap.h unctrl.h; do
  cp "$macos_sdk/usr/include/$header" "$shim/"
done
cat >"$shim/System/sys/codesign.h" <<'H'
#pragma once
#include <sys/types.h>
#define CS_OPS_STATUS 0
#define CS_INSTALLER 0x00000008
int csops(pid_t pid, unsigned int ops, void *useraddr, size_t usersize);
H

export CC="$IOS_DIR/ios-clang"
export CPPFLAGS="-I$shim -DUSE_GETCWD"
cache=$WORK/config.cache
cp "$tree/configure.cache-embedded" "$cache"
rm -rf "$src/Src"/*.o "$src/Src/zsh" "$src/config.status" 2>/dev/null || true
(cd "$src" && ./configure --host=arm-apple-darwin CC="$CC" \
  --prefix=/private/var/oneios \
  --enable-etcdir=/private/var/oneios/etc \
  --with-tcsetpgrp --enable-multibyte --enable-unicode9 --enable-max-function-depth=700 \
  --disable-dynamic --disable-gdbm --disable-pcre --with-term-lib=ncurses \
  --cache-file="$cache" >/dev/null)
make -C "$src/Src" -j"$(sysctl -n hw.ncpu)" zsh >/dev/null

ENT=$OUT/zsh-entitlements.plist
cat >"$ENT" <<'P'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>com.apple.private.security.no-container</key><true/></dict></plist>
P
cp "$src/Src/zsh" "$OUT/zsh"
"$IOS_DIR/ios-sign.py" --identifier com.oneios.zsh --entitlements "$ENT" "$OUT/zsh" >/dev/null
rm -f "$ENT"
python3 -I "$HERE/../tweak" cdhash "$OUT/zsh" | tee /tmp/zsh-cdhash.txt
grep -q 'arm64e pages=4096' /tmp/zsh-cdhash.txt || {
  echo "build-zsh.sh: zsh is not arm64e with 4 KiB pages (line above)" >&2; exit 1
}
rm -f /tmp/zsh-cdhash.txt
echo "build-zsh.sh: $OUT/zsh"