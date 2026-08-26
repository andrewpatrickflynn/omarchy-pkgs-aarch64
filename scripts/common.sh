# Shared helpers. Source this; don't execute it.
# shellcheck shell=bash

MANIFEST="${MANIFEST:-packages.json}"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[1;33m==> WARNING:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m==> ERROR:\033[0m %s\n' "$*" >&2; exit 1; }

manifest() { jq -r "$1" "$MANIFEST"; }

DB_NAME="$(manifest '.repo.db')"
REPO_TAG="${REPO_TAG:-$(manifest '.repo.tag')}"
PKGEXT_WANTED="$(manifest '.repo.pkgext')"
OMARCHY_PKGS_REPO="$(manifest '.repo.omarchy_pkgs_repo')"

# GitHub release assets cannot contain ':', so an epoch'd version arrives as
# 'pkg-1.1.2-3-...' rather than 'pkg-1:1.2-3-...'. repo-add takes %FILENAME%
# verbatim from the file it is handed, so the rename must happen *before*
# repo-add or the db points at a URL that 404s.
sanitize_asset_name() { printf '%s' "${1//:/.}"; }

# Read every %NAME% -> %VERSION% pair out of a repo db tarball.
db_versions() {
  local db="$1" tmp
  tmp="$(mktemp -d)"
  tar -xf "$db" -C "$tmp"
  local d
  for d in "$tmp"/*/; do
    [[ -f "$d/desc" ]] || continue
    printf '%s\t%s\n' \
      "$(sed -n '/^%NAME%$/{n;p;}' "$d/desc")" \
      "$(sed -n '/^%VERSION%$/{n;p;}' "$d/desc")"
  done
  rm -rf "$tmp"
}

# Read every %FILENAME% out of a repo db tarball.
db_filenames() {
  local db="$1" tmp
  tmp="$(mktemp -d)"
  tar -xf "$db" -C "$tmp"
  local d
  for d in "$tmp"/*/; do
    [[ -f "$d/desc" ]] || continue
    sed -n '/^%FILENAME%$/{n;p;}' "$d/desc"
  done
  rm -rf "$tmp"
}

# Fetch the current db from the rolling release. Both dbs are needed before
# repo-add runs: it only carries forward entries from the db files present in
# its working directory, so omitting .files.tar.zst silently truncates the
# files db to whatever is being added right now.
fetch_current_dbs() {
  local dest="$1"
  mkdir -p "$dest"
  log "Fetching current $DB_NAME db from release '$REPO_TAG'"
  gh release download "$REPO_TAG" --repo "$GH_REPO" --dir "$dest" --clobber \
    --pattern "$DB_NAME.db.tar.zst" --pattern "$DB_NAME.files.tar.zst" \
    || die "could not download the current db from release '$REPO_TAG'"
  [[ -f "$dest/$DB_NAME.db.tar.zst" ]] || die "release '$REPO_TAG' has no $DB_NAME.db.tar.zst"
}
