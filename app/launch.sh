#!/bin/bash
# Desktop entry point: run first-time setup (idempotent), collect status,
# then show the QML status page.

set -ex

SELF="$(readlink -f "${BASH_SOURCE[0]}")"
ROOT="$(dirname "$(dirname "$SELF")")"
FP="$ROOT/bin/flatpak-hybris"

CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/flatpak-hybris.ubports"
mkdir -p "$CACHE"
STATUS="$CACHE/status.json"

json_escape() {
	sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr '\n' ' '
}

# --- sandbox capability check ---------------------------------------------
# Same selection as bin/flatpak-hybris: setuid host bwrap, else the bundled
# copy kept in the cache dir (the only path confinement can exec it from)
SYS="$ROOT/sysroot"
if ! cmp -s "$SYS/usr/bin/bwrap" "$CACHE/bwrap"; then
	cp "$SYS/usr/bin/bwrap" "$CACHE/bwrap"
	chmod 755 "$CACHE/bwrap"
fi
BWRAP="$CACHE/bwrap"
[ -u /usr/bin/bwrap ] && BWRAP=/usr/bin/bwrap
if LD_LIBRARY_PATH="$SYS/usr/lib/aarch64-linux-gnu" "$BWRAP" --unshare-user --ro-bind / / /bin/true 2>"$CACHE/bwrap.err"; then
	bwrap_ok=true
	bwrap_msg="ok ($BWRAP)"
else
	bwrap_ok=false
	bwrap_msg="$(json_escape < "$CACHE/bwrap.err")"
	[ -n "$bwrap_msg" ] || bwrap_msg="bwrap failed (kernel without unprivileged user namespaces?)"
fi

# --- CLI symlinks so 'flatpak' works from the Terminal app ----------------
# Best effort: confinement denies writes to ~/.local/bin. The status page
# shows the ln -s to run once from the (unconfined) terminal instead.
symlinks_ok=false
if mkdir -p "$HOME/.local/bin" 2>/dev/null \
	&& ln -sf "$FP" "$HOME/.local/bin/flatpak" 2>/dev/null \
	&& ln -sf "$FP" "$HOME/.local/bin/flatpak-hybris" 2>/dev/null; then
	symlinks_ok=true
fi

# --- flathub remote (best effort, needs network) --------------------------
flathub_ok=false
if "$FP" remotes --user 2>/dev/null | grep -q '^flathub'; then
	flathub_ok=true
elif "$FP" remote-add --user --if-not-exists flathub \
	https://dl.flathub.org/repo/flathub.flatpakrepo 2>"$CACHE/flathub.err"; then
	flathub_ok=true
fi

fp_version="$("$FP" --version 2>/dev/null | json_escape)"
runtimes="$("$FP" list --user --runtime --columns=ref 2>/dev/null | json_escape)"
apps="$("$FP" list --user --app --columns=application 2>/dev/null | json_escape)"

cat > "$STATUS" <<EOF
{
  "flatpakVersion": "${fp_version}",
  "bwrapOk": ${bwrap_ok},
  "bwrapMsg": "${bwrap_msg}",
  "flathubOk": ${flathub_ok},
  "symlinksOk": ${symlinks_ok},
  "runtimes": "${runtimes}",
  "apps": "${apps}",
  "clickRoot": "${ROOT}"
}
EOF

# exec qmlscene "$ROOT/app/qml/Main.qml" "$STATUS"
exec qmlscene "$ROOT/app/qml/Main.qml"
