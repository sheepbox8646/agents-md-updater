#!/usr/bin/env bash
# Discover the set of target files (e.g. AGENTS.md, CLAUDE.md) that should be
# maintained for this run.
#
# Inputs (env):
#   TARGET_FILES   Comma-separated list of file names to look for.
#                  Default: "AGENTS.md".
#   DIRECTORIES    Newline-separated list of directories to scan. Each entry
#                  is searched recursively. "." means the repo root only
#                  (still recursive). Default: ".".
#
# Behavior:
#   - For each (directory, file_name) pair we run `find` to locate every
#     matching file under that directory.
#   - We always include the literal path "<dir>/<file>" if it exists, even
#     when not picked up by find (defensive for case-sensitive FS).
#   - Results are de-duplicated and sorted.
#   - We skip common vendored directories (node_modules, .git, dist, build,
#     vendor, .venv, target).
#
# Outputs:
#   - Writes "targets<<EOF...EOF" and "count=<n>" to "$GITHUB_OUTPUT" when set.
#   - Always prints the resolved list to stdout for log visibility.
set -euo pipefail

target_files="${TARGET_FILES:-AGENTS.md}"
directories_raw="${DIRECTORIES:-.}"

IFS=',' read -r -a file_names <<< "$target_files"

directories=()
while IFS= read -r line; do
  trimmed="${line#"${line%%[![:space:]]*}"}"
  trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
  [[ -z "$trimmed" ]] && continue
  directories+=("$trimmed")
done <<< "$directories_raw"
if [[ ${#directories[@]} -eq 0 ]]; then
  directories=(".")
fi

prune_args=(
  -path '*/node_modules'        -prune -o
  -path '*/.git'                -prune -o
  -path '*/dist'                -prune -o
  -path '*/build'               -prune -o
  -path '*/vendor'              -prune -o
  -path '*/.venv'               -prune -o
  -path '*/target'              -prune -o
  -path '*/.agents-md-updater'  -prune -o
)

tmp_list="$(mktemp)"
trap 'rm -f "$tmp_list"' EXIT

for dir in "${directories[@]}"; do
  [[ -z "$dir" ]] && continue
  if [[ ! -d "$dir" ]]; then
    echo "::warning::directory '$dir' does not exist, skipping"
    continue
  fi
  for name in "${file_names[@]}"; do
    name="${name// /}"
    [[ -z "$name" ]] && continue
    find "$dir" "${prune_args[@]}" -type f -name "$name" -print 2>/dev/null \
      | sed 's|^\./||' >> "$tmp_list" || true
  done
done

sorted=()
if [[ -s "$tmp_list" ]]; then
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    sorted+=("$line")
  done < <(LC_ALL=C sort -u "$tmp_list")
fi

echo "Discovered ${#sorted[@]} target file(s):"
for f in "${sorted[@]}"; do
  echo "  - $f"
done

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "count=${#sorted[@]}"
    echo "targets<<__AGENTS_MD_EOF__"
    for f in "${sorted[@]}"; do
      echo "$f"
    done
    echo "__AGENTS_MD_EOF__"
  } >> "$GITHUB_OUTPUT"
fi
