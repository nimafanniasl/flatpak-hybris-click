# flatpak-hybris → Ubuntu Touch click

Goal: package Droidian's flatpak-hybris stack (flatpak + bubblewrap +
org.freedesktop.Platform.GL.hybris extension + wrapper) as a self-contained
click for Ubuntu Touch. No rootfs writes.

## Findings (recon done)

- droidian/flatpak-hybris = tiny wrapper only (`flatpak-hybris.sh`): diverts
  /usr/bin/flatpak, sets FLATPAK_GL_DRIVERS=hybris, passes
  --filesystem=/system,/vendor,/odm,/apex,/android + --device=all +
  HYBRIS_* env pointing at the GL extension mounted INSIDE the sandbox at
  /usr/lib/<triplet>/GL/hybris. Forces bwrap setuid root on Droidian.
- The real GL bits: `flatpak-extension-gl-hybris` deb (built from Droidian's
  libhybris source pkg), installs an *unmaintained extension* to
  /var/lib/flatpak/extension/org.freedesktop.Platform.GL.hybris/aarch64/1.4/
  (libEGL_libhybris, glvnd egl_vendor.d json, libhybris linkers, etc).
  Plus `flatpak-extension-gl-hybris-tls-padding` (libtls-padding.so, LD_PRELOAD).
  These libs run inside the fd.o runtime → host glibc irrelevant → reuse
  Droidian arm64 debs as-is. Downloaded to debs/.
- flatpak env overrides (verified in 1.14 source):
  - FLATPAK_BWRAP → bwrap binary path (flatpak-utils.c:745)
  - FLATPAK_SYSTEM_DIR → system installation basedir (flatpak-dir.c:1542);
    unmaintained ext lookup = <basedir>/extension/<id>/<arch>/<branch>
  - FLATPAK_GL_DRIVERS=hybris selects the ext (matches active-gl-driver)
  → serve extension from click dir via FLATPAK_SYSTEM_DIR, user installs go
  to ~/.local/share/flatpak (writable). No patching of flatpak needed.

## Decisions

- Target UT 24.04 (noble base): stock noble arm64 flatpak 1.14.x debs can be
  repacked (focal would need a source build of modern flatpak; can follow later).
- Unconfined apparmor template (required: bind mounts, /system access, sockets).
- bwrap: bundled, unprivileged → REQUIRES CONFIG_USER_NS in device kernel.
  Runtime check in wrapper; can't setuid from a click. Fallback: use host
  /usr/bin/bwrap if present+setuid (FLATPAK_BWRAP).
- Click ships a sysroot (flatpak, bwrap, xdg-dbus-proxy, gnupg + lib closure
  from noble arm64, minus libc) + adapted wrapper + minimal QML status/setup
  UI + `bin/flatpak` CLI entrypoint for the Terminal app.

## Steps

1. [x] Recon flatpak-hybris, extension debs, flatpak source mechanisms
2. [x] Fetch noble arm64 deb closure (podman --arch arm64 ubuntu:noble, 78 debs)
3. [x] Assemble click tree: sysroot + extension + wrapper + QML app + manifest/apparmor/desktop
4. [x] Build .click (dpkg-deb, Click-Version 0.4 control + manifest + preinst)
       → out/flatpak-hybris.ubports_0.1.0_arm64.click (27M)
5. [x] Smoke-test in arm64 noble container: version OK, flathub remote-add with
       full gpg verify OK (needed gpgconf.ctl rootdir relocation!), dry-run
       proves GL.hybris extension ro-bind + HYBRIS_*/FLATPAK_GL_DRIVERS env
6. [x] README.md with install instructions + caveats
7. [ ] On-device test (no device attached today): userns/bwrap, wayland, real GL
8. [ ] Ideas: per-app desktop launchers, focal variant, OpenStore submission

Renamed to flatpak-hybris.ubports per Az (was .azkali).

Workspace: ~/claude-builds/flatpak-hybris-click/
- flatpak-hybris/  (droidian wrapper repo)
- flatpak-src/     (flatpak 1.14.10 source, reference only)
- debs/            (droidian extension debs; noble debs go here too)
- click/           (click source tree)
