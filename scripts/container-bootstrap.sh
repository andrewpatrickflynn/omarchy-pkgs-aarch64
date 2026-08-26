#!/usr/bin/env bash
# Install the tooling the other scripts need inside an Arch container.
#   bash scripts/container-bootstrap.sh [extra-packages...]
set -euo pipefail

pkgs=(git jq github-cli "$@")

# pacman 7 sandboxes its downloader with Landlock, which qemu-user does not
# implement. Retry rather than disable unconditionally, so a native ARM runner
# keeps the sandbox.
if ! pacman -Syu --noconfirm --needed "${pkgs[@]}"; then
  echo "==> pacman -Syu failed; retrying with --disable-sandbox" >&2
  pacman -Syu --noconfirm --needed --disable-sandbox "${pkgs[@]}"
fi

for c in git jq gh makepkg repo-add vercmp bsdtar file; do
  command -v "$c" >/dev/null || { echo "==> ERROR: $c missing after bootstrap" >&2; exit 1; }
done
echo "==> Container ready: $(uname -m), $(pacman -Q pacman)"
