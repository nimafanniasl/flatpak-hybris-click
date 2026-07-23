#!/bin/bash
# Smoke test a built .click. Runs INSIDE arm64 ubuntu:noble as root
# (CI job container or podman via smoke-local.sh).
# Usage: smoke-payload.sh <package.click>
set -e
CLICK="$(readlink -f "$1")"
[ -f "$CLICK" ] || { echo "usage: $0 <package.click>"; exit 1; }

export HOME=${HOME:-/root} XDG_RUNTIME_DIR=/tmp/xdg DEBIAN_FRONTEND=noninteractive
mkdir -p "$XDG_RUNTIME_DIR"
apt-get update -qq >/dev/null
apt-get install -y -qq ca-certificates dbus dbus-daemon dbus-x11 >/dev/null
[ -S /run/dbus/system_bus_socket ] || { mkdir -p /run/dbus; dbus-daemon --system --fork; }

# unpack where the wrapper expects to live (UT install path)
mkdir -p /opt/click.ubuntu.com/flatpak-hybris.ubports/current
dpkg-deb -x "$CLICK" /opt/click.ubuntu.com/flatpak-hybris.ubports/current
FP=/opt/click.ubuntu.com/flatpak-hybris.ubports/current/bin/flatpak-hybris

fail=0

echo "=== 1. version"
$FP --version

echo "=== 2. flathub remote-add + gpg-verified metadata (host gnupg: $(command -v gpg || echo none))"
if $FP remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo; then
	echo "remote-add OK"
	$FP remote-ls --user flathub --columns=application 2>&1 | head -3
else
	echo "FAIL: remote-add (rc=$?)"; fail=1
fi

echo "=== 3. dummy runtime+app, install, dry-run, check GL.hybris mount"
mkdir -p /tmp/rt/files /tmp/rt/usr /tmp/app/files /tmp/app/export
cat > /tmp/rt/metadata <<EOF
[Runtime]
name=org.freedesktop.Platform
runtime=org.freedesktop.Platform/aarch64/24.08

[Extension org.freedesktop.Platform.GL]
directory=lib/aarch64-linux-gnu/GL
version=1.4
versions=24.08;1.4
subdirectories=true
no-autodownload=true
add-ld-path=lib
merge-dirs=vulkan/icd.d;glvnd/egl_vendor.d;OpenCL/vendors
download-if=active-gl-driver
enable-if=active-gl-driver
EOF
cat > /tmp/app/metadata <<EOF
[Application]
name=com.test.App
runtime=org.freedesktop.Platform/aarch64/24.08
command=true
EOF
$FP build-export --runtime --arch=aarch64 /tmp/repo /tmp/rt 24.08 >/dev/null
$FP build-export --arch=aarch64 /tmp/repo /tmp/app master >/dev/null
$FP remote-add --user --no-gpg-verify local file:///tmp/repo
$FP install --user -y --noninteractive local org.freedesktop.Platform//24.08 com.test.App >/dev/null
$FP list --user

# bwrap stand-in: real bwrap may not sandbox here; let the xdg-dbus-proxy
# invocation run unwrapped (it must sync over an fd), dump the app
# invocation's --args fd (flatpak passes bwrap args via memfd)
cat > /tmp/bwrap-stub <<'STUB'
#!/bin/bash
if [ "$1" = "--version" ]; then echo "bubblewrap 0.9.0"; exit 0; fi
past=(); seen=0
for a in "$@"; do
  if [ "$seen" = 1 ]; then past+=("$a"); fi
  [ "$a" = "--" ] && seen=1
done
case "${past[0]}" in
  *xdg-dbus-proxy*) exec "${past[@]}" ;;
esac
argc=$#
for ((i=1;i<=argc;i++)); do
  if [ "${!i}" = "--args" ]; then
    j=$((i+1)); fd="${!j}"
    cat <&"$fd" | tr '\0' '\n' > /tmp/bwrap-args
  fi
done
exit 0
STUB
chmod +x /tmp/bwrap-stub

eval "$(dbus-launch)"; export DBUS_SESSION_BUS_ADDRESS
FLATPAK_BWRAP=/tmp/bwrap-stub $FP run com.test.App >/dev/null 2>&1 || true
if grep -q "flatpak-system/extension/org.freedesktop.Platform.GL.hybris" /tmp/bwrap-args 2>/dev/null; then
	echo "PASS: GL.hybris extension bind-mounted from the click"
	grep -B1 -A1 "flatpak-system/extension" /tmp/bwrap-args | head -4
	grep -A1 "HYBRIS_EGLPLATFORM_DIR\|FLATPAK_GL_DRIVERS" /tmp/bwrap-args
else
	echo "FAIL: extension not in bwrap args"; fail=1
fi

echo "=== 4. real bwrap userns check (informational in containers)"
SYSD=/opt/click.ubuntu.com/flatpak-hybris.ubports/current/sysroot
LD_LIBRARY_PATH=$SYSD/usr/lib/aarch64-linux-gnu $SYSD/usr/bin/bwrap \
	--unshare-user --ro-bind / / /bin/true \
	&& echo "bwrap userns OK" || echo "bwrap userns unavailable here (retest on device)"

exit $fail
