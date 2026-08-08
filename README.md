# omarchy-pkgs-aarch64

Unofficial **aarch64** builds of Omarchy's own packages, for Apple Silicon Macs
running [Asahi Linux](https://asahilinux.org/) and the
[omarchy-mac](https://codeberg.org/malik-na/omarchy-mac) fork.

## Why this exists

Omarchy's package repo at `pkgs.omarchy.org` publishes **x86_64 only** —
`edge/aarch64` and `stable/aarch64` both return 404. So on ARM, every package
that lives in Omarchy's own repo is simply unavailable, which leaves keybindings
pointing at binaries that can't be installed. `SUPER + CTRL + Q` (calculator)
and `SUPER + SHIFT + W` (writer) are the visible casualties.

Nothing is patched here. These are built from the **unmodified PKGBUILDs** in
[omacom-io/omarchy-pkgs](https://github.com/omacom-io/omarchy-pkgs) using that
repo's own build tooling, which already supports ARM:

```bash
./bin/build --arch aarch64 --package omacalc omacut omawrite
```

The packages below already declare `arch=('x86_64' 'aarch64')` upstream. They
just aren't published for ARM.

## Packages

| Package | Version | Provides |
|---------|---------|----------|
| `omacalc` | 0.2.2-1 | Calculator (Qt Quick) — bound to `SUPER + CTRL + Q` |
| `omawrite` | 0.5.0-1 | Writer (Qt Quick) — bound to `SUPER + SHIFT + W` |
| `omacut` | 0.4.0-1 | Video trimmer (Qt Quick) |

## Usage

Add to `/etc/pacman.conf`:

```ini
[omarchy-aarch64]
SigLevel = Optional TrustAll
Server = https://github.com/scottjones/omarchy-pkgs-aarch64/releases/download/edge
```

Then:

```bash
sudo pacman -Sy
sudo pacman -S omacalc omawrite omacut
```

Assets live on a single rolling `edge` tag and are replaced in place, so the
`Server` URL never changes.

## Caveats

- **Unofficial.** Not affiliated with or endorsed by Omarchy or 37signals.
  Upstream owes you nothing for these builds; report packaging bugs here, not
  to them.
- **Unsigned.** Hence `SigLevel = Optional TrustAll`, which is what Omarchy's
  own `pacman.conf` uses for its repo. If you'd rather not trust unsigned
  packages, build them yourself with the command above — it takes seconds.
- **Rebuilt by hand.** There's no CI. Versions here drift behind upstream until
  someone rebuilds. Check the table above against
  `pkgs.omarchy.org/edge/x86_64` if a version matters to you.
- **`tensaku` is absent** deliberately: its PKGBUILD declares `arch=('x86_64')`
  only and is AUR-sourced, so it's not ours to re-declare.

## Building these yourself

```bash
git clone https://github.com/omacom-io/omarchy-pkgs
cd omarchy-pkgs
./bin/build --arch aarch64 --package omacalc omacut omawrite
```

Requires Docker. On an x86_64 host it sets up QEMU automatically; on ARM it
builds natively. Each of these takes well under a minute.
