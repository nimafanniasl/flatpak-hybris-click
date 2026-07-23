#!/bin/bash
# Full click build. Runs INSIDE a pristine arm64 ubuntu:noble environment
# (CI job container or podman via build-local.sh), as root.
# Output: $OUT/flatpak-hybris.ubports_<version>_arm64.click
set -e

SRC="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
WORK="${WORK:-/tmp/fh-build}"
OUT="${OUT:-$SRC/out}"
DROIDIAN=https://production.repo.droidian.org
CLICK_PREFIX=/opt/click.ubuntu.com/flatpak-hybris.ubports/current

[ "$(dpkg --print-architecture)" = "arm64" ] || { echo "need arm64"; exit 1; }
export DEBIAN_FRONTEND=noninteractive
rm -rf "$WORK"
mkdir -p "$WORK/debs" "$OUT"

# 1. noble closure: whatever apt would add on top of the pristine base image
#    is exactly what the UT rootfs is missing. Must run before anything else
#    is installed or the closure shrinks.
apt-get update -qq
apt-get install -y --download-only --no-install-recommends \
	flatpak xdg-dbus-proxy bubblewrap gnupg ca-certificates
cp /var/cache/apt/archives/*.deb "$WORK/debs/"

apt-get install -y --no-install-recommends curl ca-certificates >/dev/null

# 2. latest Droidian GL.hybris extension debs
curl -fsSL "$DROIDIAN/dists/trixie/main/binary-arm64/Packages.gz" -o "$WORK/Packages.gz"
for pkg in flatpak-extension-gl-hybris flatpak-extension-gl-hybris-tls-padding; do
	file="$(zcat "$WORK/Packages.gz" | awk -v p="$pkg" '
		BEGIN { RS=""; FS="\n" }
		$1 == "Package: " p {
			v=""; f=""
			for (i=1; i<=NF; i++) {
				if ($i ~ /^Version: /)  v = substr($i, 10)
				if ($i ~ /^Filename: /) f = substr($i, 11)
			}
			print v " " f
		}' | sort -V | tail -1 | cut -d' ' -f2)"
	[ -n "$file" ] || { echo "no $pkg in droidian repo"; exit 1; }
	echo "   droidian: $file"
	curl -fsSL "$DROIDIAN/$file" -o "$WORK/debs/ext-$(basename "$file")"
done

# 3. assemble click tree
PKGDIR="$WORK/pkg"
SYS="$PKGDIR/sysroot"
mkdir -p "$SYS" "$PKGDIR/DEBIAN"
cp -a "$SRC/click/." "$PKGDIR/"

# provided by the UT 24.04 rootfs itself; do not bundle
EXCLUDE='^(libc6|libc-bin|gcc-14-base|libgcc-s1|libstdc\+\+6|adduser|debconf|dbus|dbus-bin|dbus-daemon|dbus-session-bus-common|dbus-system-bus-common|ca-certificates|openssl)_'

tmp="$(mktemp -d)"
for deb in "$WORK"/debs/*.deb; do
	name="$(basename "$deb")"
	case "$name" in
	ext-*)	dpkg-deb -x "$deb" "$tmp" ;;
	*)	if [[ "$name" =~ $EXCLUDE ]]; then echo "   skip $name"; else dpkg-deb -x "$deb" "$SYS"; fi ;;
	esac
done
mkdir -p "$PKGDIR/flatpak-system"
mv "$tmp/var/lib/flatpak/extension" "$PKGDIR/flatpak-system/extension"
rm -rf "$tmp"

rm -rf "$SYS/usr/share/doc" "$SYS/usr/share/man" "$SYS/usr/share/lintian" \
       "$SYS/usr/share/bash-completion" "$SYS/usr/share/zsh" \
       "$SYS/usr/share/fish" "$SYS/usr/share/gtk-doc" "$SYS/etc/init.d" \
       "$SYS/usr/share/icons" "$SYS/usr/share/bug"

find "$SYS" -type l | while read -r l; do
	t="$(readlink "$l")"
	case "$t" in
	/*) [ -e "$SYS$t" ] && ln -sf "$SYS$t" "$l" || echo "   WARN: $l -> $t (absolute, outside sysroot)" ;;
	esac
done

# relocate gnupg: gpgme asks gpgconf for component paths, which are compiled
# as /usr/bin/*; rootdir redirect keeps everything inside the click
echo "rootdir=$CLICK_PREFIX/sysroot/usr" > "$SYS/usr/bin/gpgconf.ctl"

chmod +x "$PKGDIR/bin/flatpak-hybris" "$PKGDIR/app/launch.sh"
ln -sf flatpak-hybris "$PKGDIR/bin/flatpak"

# 4. version: manifest + optional CI suffix
VERSION="$(sed -n 's/.*"version": "\([^"]*\)".*/\1/p' "$SRC/click/manifest.json")"
if [ -n "$CI" ] || [ -n "$GITHUB_ACTIONS" ]; then
	sha="${CI_COMMIT_SHORT_SHA:-${GITHUB_SHA:0:8}}"
	VERSION="$VERSION+git$(date +%Y%m%d)${sha:+.$sha}"
	sed -i "s/\"version\": \"[^\"]*\"/\"version\": \"$VERSION\"/" "$PKGDIR/manifest.json"
fi

# 5. build the .click (a deb with Click-Version + manifest in control)
cat > "$PKGDIR/DEBIAN/control" <<EOF
Package: flatpak-hybris.ubports
Version: $VERSION
Click-Version: 0.4
Architecture: arm64
Maintainer: Azkali <a.ffcc7@gmail.com>
Description: Flatpak with libhybris GL support for Ubuntu Touch
EOF
cp "$PKGDIR/manifest.json" "$PKGDIR/DEBIAN/manifest"
cat > "$PKGDIR/DEBIAN/preinst" <<'EOF'
#! /bin/sh
echo "Click packages may not be installed directly using dpkg."
echo "Use 'click install' instead."
exit 1
EOF
chmod 755 "$PKGDIR/DEBIAN/preinst"
( cd "$PKGDIR" && find . -type f -not -path './DEBIAN/*' -exec md5sum {} \; \
	| sed 's|\./||' > DEBIAN/md5sums )

dpkg-deb -Zgzip --root-owner-group -b "$PKGDIR" \
	"$OUT/flatpak-hybris.ubports_${VERSION}_arm64.click"
ls -lh "$OUT"/*.click
