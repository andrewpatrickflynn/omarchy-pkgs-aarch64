#!/usr/bin/env bash
# Build one pkgbase and stage the wanted artifacts into OUTDIR.
#
#   PKGBASE=mise-bin SOURCE=aur CATEGORY=repack PKGNAMES=mise-bin \
#     OUTDIR=./staging scripts/build-package.sh
#
# Env:
#   PKGBASE     pkgbase to build
#   SOURCE      aur | omarchy-pkgs
#   CATEGORY    any | repack
#   PKGNAMES    comma-separated pkgnames to keep (a split pkgbase builds more)
#   OUTDIR      where to stage the kept artifacts
#   IGNOREARCH  true to pass --ignorearch (for PKGBUILDs missing aarch64)
#
# This must run inside an aarch64 environment. On a native ARM runner that is
# free; on an x86 runner it is an emulated aarch64 container (binfmt + qemu).
#
# An earlier design forced CARCH=aarch64 inside an x86 container instead, on
# the theory that 'repack' PKGBUILDs only extract a vendor-prebuilt ARM binary.
# That is false: mise-bin's package() runs the ARM `mise` three times to
# generate shell completions, and any upstream PKGBUILD may start doing the
# same at any time. Emulating the target arch is the only version of this that
# does not silently rot.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
source scripts/common.sh

: "${PKGBASE:?}" "${SOURCE:?}" "${CATEGORY:?}" "${PKGNAMES:?}" "${OUTDIR:?}"
IGNOREARCH="${IGNOREARCH:-false}"
EXTRA_MAKEDEPENDS="${EXTRA_MAKEDEPENDS:-}"
ALLOW_FOREIGN_ELF="${ALLOW_FOREIGN_ELF:-}"

case "$CATEGORY" in
  any)             want_arch=any ;;
  repack|compile)  want_arch=aarch64 ;;
  *) die "unknown category '$CATEGORY' (want any, repack or compile)" ;;
esac

OUTDIR="$(mkdir -p "$OUTDIR" && cd "$OUTDIR" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/out" "$work/srcdest"

# makepkg refuses to run as root. In a container we start as root, so make an
# unprivileged builder and hand it the tree.
if [[ "$(id -u)" -eq 0 ]]; then
  id -u builder &>/dev/null || useradd -m builder
  as_builder() { runuser -u builder -- "$@"; }
else
  as_builder() { "$@"; }
fi

# pacman 7 sandboxes its downloader with Landlock, which qemu-user does not
# implement, so a plain -Sy dies inside an emulated container. Retry rather
# than disable unconditionally, so a native ARM runner keeps the sandbox.
pacman_install() {
  pacman -Sy --noconfirm --needed --asdeps "$@" && return 0
  warn "pacman -Sy failed; retrying with --disable-sandbox (expected under emulation)"
  pacman -Sy --noconfirm --needed --asdeps --disable-sandbox "$@"
}

# --- fetch the PKGBUILD -----------------------------------------------------
src="$work/src"
case "$SOURCE" in
  aur)
    log "Cloning AUR pkgbase '$PKGBASE'"
    git clone --depth 1 "https://aur.archlinux.org/$PKGBASE.git" "$src" \
      || die "could not clone AUR pkgbase '$PKGBASE'"
    ;;
  omarchy-pkgs)
    log "Sparse-checking out $OMARCHY_PKGS_REPO pkgbuilds/$PKGBASE"
    # Whole directory, not just the PKGBUILD: several of these carry local
    # source files (launcher scripts, .install hooks) alongside it.
    git clone --depth 1 --filter=blob:none --sparse \
      "https://github.com/$OMARCHY_PKGS_REPO.git" "$work/oma" \
      || die "could not clone $OMARCHY_PKGS_REPO"
    git -C "$work/oma" sparse-checkout set "pkgbuilds/$PKGBASE" \
      || die "no pkgbuilds/$PKGBASE in $OMARCHY_PKGS_REPO"
    [[ -f "$work/oma/pkgbuilds/$PKGBASE/PKGBUILD" ]] \
      || die "no PKGBUILD at pkgbuilds/$PKGBASE"
    mv "$work/oma/pkgbuilds/$PKGBASE" "$src"
    ;;
  *) die "unknown source '$SOURCE'" ;;
esac

# --- makepkg.conf -----------------------------------------------------------
conf="$work/makepkg.conf"
cp /etc/makepkg.conf "$conf"
{
  echo ""
  echo "# --- overrides written by scripts/build-package.sh ---"
  # Pinned so the repo stays homogeneous; every existing asset is .pkg.tar.xz.
  echo "PKGEXT='$PKGEXT_WANTED'"
  echo "SRCEXT='.src.tar.gz'"
  echo "PKGDEST='$work/out'"
  echo "SRCDEST='$work/srcdest'"
} >> "$conf"

# Fail loudly rather than quietly producing an x86 package with an aarch64
# name. This is cheap and catches a missing binfmt registration immediately.
host_arch="$(uname -m)"
[[ "$host_arch" == "aarch64" ]] \
  || die "must build on aarch64 (native or emulated); this is $host_arch. On an x86 runner, register binfmt and run inside an aarch64 container."
log "PKGEXT=$PKGEXT_WANTED, build arch=$host_arch, target arch=$want_arch"

chown -R builder: "$work" 2>/dev/null || true

# --- makedepends ------------------------------------------------------------
# --printsrcinfo expands arch-specific arrays for us. It sources the PKGBUILD,
# which is the same trust boundary as building it.
srcinfo="$work/.SRCINFO"
( cd "$src" && as_builder makepkg --config "$conf" --printsrcinfo ) > "$srcinfo" \
  || die "could not parse PKGBUILD for $PKGBASE"

# "compile" additionally needs runtime depends present at build time: linking
# tensaku wants gtk4 and libadwaita headers, not just rustc. "any" and "repack"
# never compile against anything, so installing their depends would be waste.
if [[ "$CATEGORY" == "compile" ]]; then
  dep_re='^[[:space:]]*(make|check)?depends(_[[:alnum:]_]+)?[[:space:]]*=[[:space:]]*(.+)'
else
  dep_re='^[[:space:]]*(make|check)depends(_[[:alnum:]_]+)?[[:space:]]*=[[:space:]]*(.+)'
fi

mapfile -t deps < <(
  {
    sed -nE "s/$dep_re/\3/p" "$srcinfo" \
      | sed -E 's/[<>=].*$//' | tr -d ' '
    # Some PKGBUILDs call tooling they never declare — yaru's build() uses
    # arch-meson, which ships in devtools. packages.json records those.
    [[ -n "$EXTRA_MAKEDEPENDS" ]] && tr ',' '\n' <<< "$EXTRA_MAKEDEPENDS"
  } | sed '/^$/d' | sort -u
)
if ((${#deps[@]})); then
  log "Installing build deps: ${deps[*]}"
  if [[ "$(id -u)" -eq 0 ]]; then
    pacman_install "${deps[@]}" || die "could not install build deps: ${deps[*]}"
  else
    warn "not root; assuming build deps are present: ${deps[*]}"
  fi
else
  log "No build deps declared"
fi

# --- build ------------------------------------------------------------------
# --nodeps: runtime depends are irrelevant to producing the artifact, and for
# repack builds they are aarch64 packages an x86 runner could not install.
# --nocheck: test suites want checkdepends and a native target.
mkflags=(--config "$conf" --nodeps --nocheck --noconfirm --force --clean)
[[ "$IGNOREARCH" == "true" ]] && mkflags+=(--ignorearch)
log "Building $PKGBASE"
( cd "$src" && as_builder makepkg "${mkflags[@]}" ) || die "makepkg failed for $PKGBASE"

# --- collect and verify -----------------------------------------------------
shopt -s nullglob
built=("$work/out"/*"$PKGEXT_WANTED")
((${#built[@]})) || die "$PKGBASE produced no $PKGEXT_WANTED artifact"
log "Built ${#built[@]} artifact(s): $(printf '%s ' "${built[@]##*/}")"

# Read the name from .PKGINFO rather than inferring it from the filename.
# Authoritative for split pkgbases, where several artifacts share a prefix
# (yaru builds 9 subpackages; dotnet-core-2.1 builds 2).
artifact_pkgname() {
  local name
  name="$(bsdtar -xOqf "$1" .PKGINFO 2>/dev/null \
    | awk -F' = ' '/^pkgname = /{print $2; exit}')"
  [[ -n "$name" ]] || die "could not read pkgname from $1 (.PKGINFO missing?)"
  printf '%s' "$name"
}

# The failure this guards against is shipping an x86 payload under an aarch64
# filename. It deliberately does NOT demand that every ELF be aarch64: the
# openai-codex-desktop Electron bundle legitimately carries 32-bit ARM
# libraries, and rejecting those is a false positive.
#
# e_machine is read straight out of the ELF header rather than matched against
# file(1)'s prose, which spells the same architecture several ways ("x86-64",
# "Intel 80386", "Intel i386").
elf_machine() {
  local bytes lo hi
  bytes="$(od -An -tu1 -j18 -N2 -- "$1" 2>/dev/null)" || return 1
  read -r lo hi <<< "$bytes"
  [[ -n "$lo" && -n "$hi" ]] || return 1
  printf '%s' "$(( lo + hi * 256 ))"
}

# Vendors bundle native modules for every platform they support. Those are
# expected and unused here, but the allowance is a path glob rather than a
# blanket exemption, so an x86 binary somewhere that matters still fails.
elf_allowed() {
  local rel="$1" pat pats
  [[ -n "$ALLOW_FOREIGN_ELF" ]] || return 1
  IFS=',' read -r -a pats <<< "$ALLOW_FOREIGN_ELF"
  for pat in "${pats[@]}"; do
    [[ -n "$pat" ]] || continue
    # shellcheck disable=SC2053  # glob match is the point
    [[ "$rel" == $pat ]] && return 0
  done
  return 1
}

audit_elf() {
  local pkg="$1" tmp list arm=0 x86=0 other=0 allowed=0 m rel
  tmp="$(mktemp -d)"; list="$tmp.list"
  bsdtar -xf "$pkg" -C "$tmp" 2>/dev/null || die "could not extract $pkg"

  # One batched file(1) call to find the ELF objects, then read each header.
  command find "$tmp" -type f -print0 | xargs -0 -r file -N -- 2>/dev/null \
    | sed -n 's/^\(.*\): ELF .*/\1/p' > "$list" || true

  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    m="$(elf_machine "$f")" || continue
    case "$m" in
      183) arm=$((arm + 1)) ;;        # EM_AARCH64
      62|3)                             # EM_X86_64, EM_386
            rel="${f#"$tmp"}"
            if elf_allowed "$rel"; then
              allowed=$((allowed + 1))
            else
              x86=$((x86 + 1)); warn "  x86 object: $rel"
            fi ;;
      *) other=$((other + 1)) ;;      # EM_ARM (40) and friends: not our problem
    esac
  done < "$list"
  rm -rf "$tmp" "$list"

  log "  ELF audit: $arm aarch64, $x86 x86, $other other-arch, $allowed allowed-foreign"
  (( x86 == 0 )) || die "$pkg carries $x86 x86 ELF object(s) — this is not an aarch64 build"
  (( arm > 0 ))  || die "$pkg contains no aarch64 ELF objects — expected a prebuilt ARM payload"
}

kept=0
IFS=',' read -r -a wanted <<< "$PKGNAMES"
for name in "${wanted[@]}"; do
  found=""
  for pkg in "${built[@]}"; do
    [[ "$(artifact_pkgname "$pkg")" == "$name" ]] && { found="$pkg"; break; }
  done
  [[ -n "$found" ]] || die "$PKGBASE did not produce an artifact for '$name'"

  base="$(basename "$found")"
  [[ "$base" == *"-$want_arch$PKGEXT_WANTED" ]] \
    || die "$base is not a '-$want_arch$PKGEXT_WANTED' artifact"
  log "Keeping $base"
  [[ "$CATEGORY" == "repack" ]] && audit_elf "$found"

  # An epoch puts a ':' in the filename, which neither a GitHub release asset
  # nor an actions/upload-artifact path can contain. Rename here so the name is
  # already safe by the time repo-add records it as %FILENAME%.
  safe="$(sanitize_asset_name "$base")"
  [[ "$safe" == "$base" ]] || log "  staging as $safe (':' cannot survive an upload)"
  cp "$found" "$OUTDIR/$safe"
  kept=$((kept + 1))
done

log "Staged $kept artifact(s) in $OUTDIR"
