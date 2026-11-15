#!/bin/bash
# Build arm64e dropbear for the guest (pubkey-only, port 2222 via oneios-init). Not part of build.sh because
# dropbear is vendored from ownervisor and pinned separately.
#
#   userland/helpers/build-dropbear.sh [OUT_DIR]
#
# Writes OUT_DIR/dropbear (signed). Also copies OUT_DIR/zsh if userland/helpers/build-zsh.sh was run first.
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)
OUT=${1:-$REPO/out/userland/helpers}
TAG=DROPBEAR_2022.83
WORK=$REPO/out/userland/dropbear-armv8e/work
URL="https://github.com/mkj/dropbear/archive/refs/tags/${TAG}.tar.gz"
SHA256=e02c5c36eb53bfcd3f417c6e40703a50ec790a1a772269ea156a2ccef14998d2
AUTHKEYS=/private/var/root/.ssh/authorized_keys
SHELL=/private/var/oneios/bin/zsh

. "$REPO/scripts/ios/env.sh"
mkdir -p "$OUT" "$WORK"
tarball=$WORK/${TAG}.tar.gz
if [ ! -f "$tarball" ] || [ "$(openssl dgst -sha256 "$tarball" | awk '{print $2}')" != "$SHA256" ]; then
  curl -fsSL -o "$tarball" "$URL"
fi
if [ "$(openssl dgst -sha256 "$tarball" | awk '{print $2}')" != "$SHA256" ]; then
  echo "build-dropbear.sh: tarball sha256 mismatch" >&2; exit 1
fi
src=$WORK/dropbear-$TAG
rm -rf "$src"
tar -xzf "$tarball" -C "$WORK"
python3 - "$src" "$AUTHKEYS" "$SHELL" <<'PY'
import sys
from pathlib import Path
src = Path(sys.argv[1])
auth, shell = sys.argv[2], sys.argv[3]

def one(path, old, new):
    p = src / path
    text = p.read_text()
    if text.count(old) != 1:
        sys.exit(f"{path}: expected one match, got {text.count(old)}")
    p.write_text(text.replace(old, new))

one('common-session.c',
    '\tif (ses.authstate.pw_shell[0] == \'\\0\') {\n\t\treturn "/bin/sh";\n\t} else {\n\t\treturn ses.authstate.pw_shell;\n\t}',
    f'\t(void)ses.authstate.pw_shell;\n\treturn "{shell}";')
one('svr-authpubkey.c',
    '\t\tlen = strlen(ses.authstate.pw_dir);\n\t\t/* allocate max required pathname storage,\n'
    '\t\t * = path + "/.ssh/authorized_keys" + \'\\0\' = pathlen + 22 */\n\t\tfilename = m_malloc(len + 22);\n'
    '\t\tsnprintf(filename, len + 22, "%s/.ssh/authorized_keys",\n\t\t\t\t\tses.authstate.pw_dir);',
    f'\t\tfilename = m_strdup("{auth}");')
perms_old = (
    '\tif (ses.authstate.pw_dir == NULL) {\n\t\tgoto out;\n\t}\n\n'
    '\tif ((len = strlen(ses.authstate.pw_dir)) == 0) {\n\t\tgoto out;\n\t}\n\n'
    '\t/* allocate max required pathname storage,\n\t * = path + "/.ssh/authorized_keys" + \'\\0\' = pathlen + 22 */\n'
    '\tlen += 22;\n\tfilename = m_malloc(len);\n\tstrlcpy(filename, ses.authstate.pw_dir, len);\n\n'
    '\t/* check ~ */\n\tif (checkfileperm(filename) != DROPBEAR_SUCCESS) {\n\t\tgoto out;\n\t}\n\n'
    '\t/* check ~/.ssh */\n\tstrlcat(filename, "/.ssh", len);\n\tif (checkfileperm(filename) != DROPBEAR_SUCCESS) {\n\t\tgoto out;\n\t}\n\n'
    '\t/* now check ~/.ssh/authorized_keys */\n\tstrlcat(filename, "/authorized_keys", len);\n\tif (checkfileperm(filename) != DROPBEAR_SUCCESS) {\n\t\tgoto out;\n\t}')
perms_new = (
    f'\t(void)len;\n\tfilename = m_strdup("{auth}");\n'
    '\tif (checkfileperm(filename) != DROPBEAR_SUCCESS) {\n\t\tgoto out;\n\t}')
one('svr-authpubkey.c', perms_old, perms_new)
PY

cat >"$src/localoptions.h" <<'H'
#define DROPBEAR_SVR_PASSWORD_AUTH 0
#define DROPBEAR_SVR_PAM_AUTH 0
#define DROPBEAR_SVR_PUBKEY_AUTH 1
#define DROPBEAR_SVR_MULTIUSER 1
#define DROPBEAR_UTMP 0
#define DROPBEAR_WTMP 0
#define DROPBEAR_LASTLOG 0
#define DROPBEAR_PUTUTLINE 0
#define DO_MOTD 0
#define DEFAULT_PATH "/private/var/oneios/bin:/usr/bin:/bin:/usr/sbin:/sbin"
#define ED25519_PRIV_FILENAME "/private/var/oneios/ssh/dropbear_ed25519_host_key"
#define RSA_PRIV_FILENAME "/private/var/oneios/ssh/dropbear_rsa_host_key"
#define ECDSA_PRIV_FILENAME "/private/var/oneios/ssh/dropbear_ecdsa_host_key"
#define DSS_PRIV_FILENAME "/private/var/oneios/ssh/dropbear_dss_host_key"
H

export CC="$IOS_DIR/ios-clang"
(cd "$src" && ./configure --host=arm-apple-darwin CC="$CC" --disable-zlib --disable-lastlog --disable-utmp --disable-wtmp >/dev/null)
make -C "$src" PROGRAMS=dropbear dropbear -j"$(sysctl -n hw.ncpu)" >/dev/null

ENT=$OUT/dropbear-entitlements.plist
cat >"$ENT" <<'P'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>com.apple.private.security.no-container</key><true/></dict></plist>
P
cp "$src/dropbear" "$OUT/dropbear"
"$IOS_DIR/ios-sign.py" --identifier com.oneios.dropbear --entitlements "$ENT" "$OUT/dropbear" >/dev/null
rm -f "$ENT"
python3 -I "$HERE/../tweak" cdhash "$OUT/dropbear" | tee /tmp/dropbear-cdhash.txt
grep -q 'arm64e pages=4096' /tmp/dropbear-cdhash.txt || {
  echo "build-dropbear.sh: dropbear is not arm64e with 4 KiB pages (line above)" >&2; exit 1
}
rm -f /tmp/dropbear-cdhash.txt
echo "build-dropbear.sh: $OUT/dropbear"