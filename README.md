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

Nothing is patched here. Sources are unmodified; only the build architecture
changes. Packages come from three places:

- **Omarchy's own repo** ([omacom-io/omarchy-pkgs](https://github.com/omacom-io/omarchy-pkgs)),
  built with that repo's tooling, which already supports ARM:
  `./bin/build --arch aarch64 --package omacalc omacut omawrite`
- **The AUR**, built with `makepkg` from the published PKGBUILD.
- **`any`-architecture packages**, which need no rebuild at all — the AUR
  artifact is reused as-is.

## Packages

| Package | Version | Provides |
|---------|---------|----------|
| `aether` | 4.29.4-1 | Wallpaper-driven desktop theming |
| `brave-origin-bin` | 1:1.93.136-1 | Minimalist browser from the Brave team |
| `cliamp` | 1.63.2-1 | Retro terminal music player |
| `dotnet-host-bin` | 10.0.11.sdk400-1 | .NET CLI driver |
| `dotnet-runtime-2.1` | 2.1.30.sdk818-1 | .NET Core 2.1 runtime |
| `dotnet-sdk-2.1` | 2.1.30.sdk818-1 | .NET Core 2.1 SDK |
| `herdr` | 0.8.2-1 | Terminal workspace manager for AI coding agents |
| `hypa-ttfx-bin` | 0.3.1-1 | Hypa terminal text effects |
| `hyprland-preview-share-picker-git` | 0.2.1.r9.ge2f30ff-1 | Share picker with window/monitor previews |
| `localsend` | 1.18.2-1 | Cross-platform AirDrop alternative |
| `mise-bin` | 2026.8.11-1 | Dev tools, env vars, task runner |
| `obsidian-appimage` | 1.12.7-1 | Markdown knowledge base (AppImage) |
| `omacalc` | 0.2.2-1 | Calculator — bound to `SUPER + CTRL + Q` |
| `omacut` | 0.4.0-1 | Video length trimmer |
| `omarchy-emacs` | 1.10.1-1 | Emacs theme/font syncing for Omarchy |
| `omarchy-webapp-theme` | 0.3.5-1 | Theme Slack, Discord, GitHub et al. to match Omarchy |
| `omawrite` | 0.5.0-1 | Markdown writing app — bound to `SUPER + SHIFT + W` |
| `openai-codex-desktop` | 26.818.61809-1 | ChatGPT desktop app with Codex |
| `tensaku` | 0.26.7-1 | Screenshot annotation for Wayland |
| `ttf-ia-writer` | 20181225-1 | iA Writer font subset |
| `ttfx` | 0.3.2-1 | Terminal text effects, static binary |
| `tzupdate` | 3.1.0-1 | Set timezone from IP geolocation |
| `ufw-docker` | 251123-1 | Fix the Docker/UFW security flaw |
| `xdg-terminal-exec` | 0.14.3-1 | Launch desktop apps with `Terminal=true` |
| `yaru-icon-theme` | 26.04.5.1ubuntu-1 | Yaru default Ubuntu icon theme |

## Usage

Add to `/etc/pacman.conf`:

```ini
[omarchy-aarch64]
SigLevel = Optional TrustAll
Server = https://github.com/omarchy-mac/omarchy-pkgs-aarch64/releases/download/edge
```

Then:

```bash
sudo pacman -Sy
sudo pacman -S omacalc omawrite omacut   # or any package from the table
```

Assets live on a single rolling `edge` tag and are replaced in place, so the
`Server` URL never changes.

## Caveats

- **Unofficial.** Not affiliated with or endorsed by Omarchy or 37signals.
  Upstream owes you nothing for these builds; report packaging bugs here, not
  to them.
- **Unsigned.** Hence `SigLevel = Optional TrustAll`, which is what Omarchy's
  own `pacman.conf` uses for its repo. If you'd rather not trust unsigned
  packages, build them yourself: the Omarchy ones with the command below, the
  AUR ones with `makepkg` from their PKGBUILD.
- **Rebuilt by hand.** There's no CI. Versions here drift behind upstream until
  someone rebuilds. Check the table above against the package's own upstream
  (`pkgs.omarchy.org/edge/x86_64` for Omarchy's, the AUR for the rest) if a
  version matters to you.

## Building these yourself

Omarchy's own packages:

```bash
git clone https://github.com/omacom-io/omarchy-pkgs
cd omarchy-pkgs
./bin/build --arch aarch64 --package omacalc omacut omawrite
```

Requires Docker. On an x86_64 host it sets up QEMU automatically; on ARM it
builds natively. Each of these takes well under a minute.

Everything else comes from the AUR — clone the package and run `makepkg`.
Packages marked `arch=('any')` need no rebuild at all; the AUR artifact works
on ARM unchanged.
