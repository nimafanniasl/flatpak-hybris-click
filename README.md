# flatpak-hybris.ubports — Flatpak (with libhybris GL) as an Ubuntu Touch click

Self-contained click packaging of Droidian's flatpak-hybris stack for
Ubuntu Touch 24.04-1.x. Nothing is written outside the click install dir and
the user's home.

Droidian's own packaging diverts `/usr/bin/flatpak` and sets bwrap setuid in
a debian postinst; that does not fit the read-only UT image and would be
reverted by OTA. Here the whole stack (flatpak included) ships inside the
click and is relocated via environment variables, so OTA updates never touch
it.

Artifact: `out/flatpak-hybris.ubports_0.1.0_arm64.click` (~27 MB)

## What's inside

- `sysroot/` — noble arm64 debs unpacked: flatpak 1.14.6, bubblewrap 0.9.0,
  xdg-dbus-proxy, gnupg suite + library closure (libostree, libappstream,
  libcurl, libicu, ...). libc/dbus/ca-certificates excluded (host provides).
- `flatpak-system/extension/org.freedesktop.Platform.GL.hybris/aarch64/1.4/`
  — Droidian's flatpak-extension-gl-hybris + -tls-padding debs (libhybris
  built against the fd.o runtime; host glibc irrelevant), served as a flatpak
  "unmaintained extension" via `FLATPAK_SYSTEM_DIR`.
- `bin/flatpak-hybris` (+ `bin/flatpak` symlink) — wrapper: sets PATH /
  LD_LIBRARY_PATH into sysroot, `FLATPAK_SYSTEM_DIR`, `FLATPAK_BWRAP`,
  `FLATPAK_DBUSPROXY`, `FLATPAK_GL_DRIVERS=hybris`; on `flatpak run` injects
  the Droidian args (`--filesystem=/system:ro ... --device=all`,
  `HYBRIS_EGLPLATFORM_DIR/LINKER_DIR/LD_LIBRARY_PATH` pointing at the mounted
  extension). `FLATPAK_HYBRIS_TLS_PADDING=1` preloads libtls-padding.so.
- `app/` — desktop entry: `launch.sh` does idempotent setup (bwrap/userns
  check, `~/.local/bin/flatpak` symlinks, flathub remote-add --user) and
  shows a QML status page.
- gnupg relocation: `sysroot/usr/bin/gpgconf.ctl` with `rootdir=` pointing at
  the click sysroot — without it gpgme asks gpgconf for component paths and
  gets compiled-in /usr/bin/* (absent on UT), breaking GPG verification.

## Install / use

    adb push out/flatpak-hybris.ubports_0.1.0_arm64.click /home/phablet/
    adb shell pkcon install-local --allow-untrusted /home/phablet/flatpak-hybris.ubports_0.1.0_arm64.click

Open "Flatpak Hybris" once (setup + status), then from the Terminal app:

    flatpak install flathub org.gnome.Calculator
    flatpak run org.gnome.Calculator

(`flatpak` = symlink in ~/.local/bin; re-login once if not found.)

## Confinement (this branch)

This branch drops the `unconfined` apparmor template: the app runs under the
stock `ubuntu-sdk` template plus a new reserved `sandboxing` policy group
proposed for apparmor-easyprof-ubuntu. The app profile itself gets no mount
or namespace privileges; bubblewrap is handed off to an unconfined-mode
child profile (same approach as Ubuntu's /etc/apparmor.d/bwrap), and the
bundled bwrap is executed from `~/.cache/flatpak-hybris.ubports/` because
the click install dir cannot carry the exec transition.

Until the `sandboxing` group ships in an image, installing this build fails
at apparmor policy generation - use master (unconfined) on stock images.
Confinement also blocks the automatic `~/.local/bin/flatpak` symlink; the
status page shows the one-liner to create it from the (unconfined) Terminal.

## Requirements / caveats

- **CONFIG_USER_NS in the device kernel.** A click cannot ship a setuid bwrap
  (files owned by clickpkg), so bubblewrap runs unprivileged. Halium kernels
  often lack USER_NS — enable it in the kernel (Volla kernels: our tree) or
  install a setuid bwrap on a rw rootfs (`/usr/bin/bwrap` setuid is picked up
  automatically). The status app shows the check result.
- Wayland: flatpak apps connect to Mir's wayland socket; app must be launched
  from an environment with WAYLAND_DISPLAY (terminal/app session on 24.04).
- flatpak session-helper/portals are not running (no
  org.freedesktop.Flatpak / document portal); most apps degrade gracefully.
- Installs are per-user under ~/.local/share/flatpak (runtimes are GBs; home
  must have space).
- Target framework ubuntu-touch-24.04-1.x (noble). A focal build would need
  flatpak built from source against 20.04.
- Apps installed via flatpak don't appear in the Lomiri app drawer (future:
  generate per-app desktop launchers).

## Build

Everything runs inside a pristine arm64 `ubuntu:noble`:

    ./build-local.sh              # podman (qemu binfmt) -> out/*.click
    ./smoke-local.sh              # smoke test the built click

`build-payload.sh` / `smoke-payload.sh` are the container-internal parts and
are what CI runs directly. The build downloads the noble closure with apt
(whatever a pristine noble base is missing = what the UT rootfs is missing)
and the *latest* flatpak-extension-gl-hybris(+tls-padding) debs from
https://production.repo.droidian.org, so rebuilding tracks Droidian's
libhybris automatically.

## CI

- `.gitlab-ci.yml` — build + smoke on GitLab.com arm64 SaaS runners
  (`saas-linux-small-arm64`); .click as pipeline artifact. Add a scheduled
  pipeline (weekly) in the GitLab UI to auto-track new droidian/noble debs.
- `.github/workflows/build.yml` — same on GitHub `ubuntu-24.04-arm` runners,
  with a weekly cron. Free arm64 runners require the repo to be public.

CI builds get a `+git<date>.<sha>` version suffix.

## Verified (arm64 noble container, 2026-07-23)

- flatpak 1.14.6 runs from /opt/click.ubuntu.com path, no host gnupg/flatpak
- flathub remote-add with full GPG verification, remote-ls works
- `flatpak run` dry-run: GL.hybris extension ro-bind from the click →
  /usr/lib/aarch64-linux-gnu/GL/hybris, FLATPAK_GL_DRIVERS/HYBRIS_* env set
- NOT yet tested on a real device (none attached): userns, wayland display,
  actual GL through hybris
