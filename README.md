# flatpak-hybris.ubports — Flatpak (with libhybris GL) as an Ubuntu Touch click

Droidian's flatpak-hybris stack as a self-contained click for Ubuntu Touch
24.04-1.x. Droidian diverts `/usr/bin/flatpak` and setuids bwrap in a
postinst; that doesn't fit the read-only UT image. Here the whole stack
ships in the click, relocated via environment variables, untouched by OTA.
Nothing is written outside the click dir and the user's home.

## What's inside

- `sysroot/` — noble arm64 debs: flatpak, bubblewrap, xdg-dbus-proxy, gnupg
  + library closure. `gpgconf.ctl` points gnupg's rootdir at the sysroot
  (gpgme breaks otherwise).
- `flatpak-system/` — Droidian's flatpak-extension-gl-hybris(+tls-padding)
  debs as an "unmaintained extension", served via `FLATPAK_SYSTEM_DIR`.
- `bin/flatpak-hybris` — wrapper: sysroot PATH/LD_LIBRARY_PATH,
  `FLATPAK_SYSTEM_DIR`, `FLATPAK_BWRAP`, `FLATPAK_DBUSPROXY`,
  `FLATPAK_GL_DRIVERS=hybris`; injects the Droidian `flatpak run` args
  (/system:ro etc., `HYBRIS_*` env). `FLATPAK_HYBRIS_TLS_PADDING=1`
  preloads libtls-padding.so.
- `app/` — desktop entry: idempotent setup + QML status page.

## Install / use

    adb push out/flatpak-hybris.ubports_0.1.0_arm64.click /home/phablet/
    adb shell pkcon install-local --allow-untrusted /home/phablet/flatpak-hybris.ubports_0.1.0_arm64.click

Open "Flatpak Hybris" once, then from the Terminal app:

    flatpak install flathub org.gnome.Calculator
    flatpak run org.gnome.Calculator

## Confinement

Runs under the stock `ubuntu-sdk` template plus the reserved `sandboxing`
policy group proposed in apparmor-easyprof-ubuntu!63: the app profile gets
no mount/namespace privileges, bwrap transitions to an unconfined-mode
child profile (like Ubuntu's /etc/apparmor.d/bwrap) and is exec'd from
`~/.cache/flatpak-hybris.ubports/`. Until !63 ships, use the `unconfined`
branch. Confinement blocks the `~/.local/bin/flatpak` symlink; the status
page shows the one-liner for the Terminal.

## Requirements / caveats

- **CONFIG_USER_NS in the kernel** — a click can't ship setuid bwrap. A
  setuid `/usr/bin/bwrap` on a rw rootfs is preferred automatically.
- Launch from an environment with WAYLAND_DISPLAY.
- No session-helper/portals; most apps degrade gracefully.
- Installs are per-user under ~/.local/share/flatpak (runtimes are GBs).
- No Lomiri app drawer entries yet (future: per-app desktop launchers).
- Framework ubuntu-touch-24.04-1.x; focal would need flatpak built from
  source.

## Build / CI

    ./build-local.sh              # podman (qemu binfmt) -> out/*.click
    ./smoke-local.sh              # smoke test

`build-payload.sh`/`smoke-payload.sh` run inside `ubuntu:noble` and are
what CI runs (GitLab arm64 SaaS runners + GitHub arm runners, weekly
schedule). Debs are fetched latest-at-build, so rebuilds track Droidian's
libhybris; CI versions get `+git<date>.<sha>`.

Container-verified: flatpak from click path, flathub with GPG, `flatpak
run` dry-run binds the GL.hybris extension. Not yet device-tested
(userns, wayland, real hybris GL).
