#!/usr/bin/env bash
# Rewrite the Version column of the README package table from a repo db, so the
# table cannot drift from what is actually published.
#
#   DB=path/to/omarchy-aarch64.db.tar.zst scripts/update-readme.sh
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
source scripts/common.sh

: "${DB:?DB must point at a $DB_NAME.db.tar.zst}"
README="${README:-README.md}"
[[ -f "$README" ]] || die "$README not found"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
db_versions "$DB" | sort > "$work/versions.tsv"
[[ -s "$work/versions.tsv" ]] || die "no entries in $DB"

python3 - "$README" "$work/versions.tsv" <<'PY'
import re, sys
readme_path, versions_path = sys.argv[1], sys.argv[2]
versions = {}
for line in open(versions_path):
    if line.strip():
        name, ver = line.rstrip("\n").split("\t")
        versions[name] = ver

out, changed, seen = [], [], set()
# Table rows look like: | `pkgname` | 1.2.3-1 | description |
row = re.compile(r'^(\|\s*`([^`]+)`\s*\|\s*)([^|]*?)(\s*\|.*)$')
for line in open(readme_path):
    m = row.match(line.rstrip("\n"))
    if m and m.group(2) in versions:
        name, old, new = m.group(2), m.group(3).strip(), versions[m.group(2)]
        seen.add(name)
        if old != new:
            changed.append(f"{name}: {old} -> {new}")
        out.append(f"{m.group(1)}{new}{m.group(4)}\n")
    else:
        out.append(line)

open(readme_path, "w").writelines(out)
missing = sorted(set(versions) - seen)
if missing:
    print("WARNING: in the db but not in the README table: " + ", ".join(missing), file=sys.stderr)
for c in changed:
    print("  " + c, file=sys.stderr)
print(f"{len(changed)} version(s) updated in {readme_path}", file=sys.stderr)
PY
