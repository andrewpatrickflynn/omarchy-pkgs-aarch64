#!/usr/bin/env bash
# Install the tooling the other scripts need inside an Arch container.
#   bash scripts/container-bootstrap.sh [build|full]
#
# "build" skips github-cli: build jobs never touch the release, and every
# package installed here is unpacked under emulation, so the ~15MB of gh and
# its dependencies is pure cost on the slowest path we have.
set -euo pipefail

role="${1:-full}"
case "$role" in
  build) pkgs=(git jq);              required=(git jq makepkg bsdtar file) ;;
  full)  pkgs=(git jq github-cli);   required=(git jq gh repo-add vercmp bsdtar) ;;
  *) echo "==> ERROR: unknown role '$role' (want build|full)" >&2; exit 1 ;;
esac

# pacman 7 sandboxes its downloader with Landlock, which qemu-user does not
# implement. Retry rather than disable unconditionally, so a native ARM runner
# keeps the sandbox.
if ! pacman -Syu --noconfirm --needed "${pkgs[@]}"; then
  echo "==> pacman -Syu failed; retrying with --disable-sandbox" >&2
  pacman -Syu --noconfirm --needed --disable-sandbox "${pkgs[@]}"
fi

for c in "${required[@]}"; do
  command -v "$c" >/dev/null || { echo "==> ERROR: $c missing after bootstrap" >&2; exit 1; }
done
echo "==> Container ready ($role): $(uname -m), $(pacman -Q pacman)"
