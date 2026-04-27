#!/usr/bin/env bash
# Build the final prompt that the agent will execute.
#
# Inputs (env):
#   DEFAULT_PROMPT_PATH   Path to the bundled default prompt (required).
#   OUTPUT_PATH           Path to write the final prompt to (required).
#   DISCOVERED_TARGETS    Newline-separated list of target file paths
#                         produced by discover-targets.sh.
#   PROMPT_FILE_OVERRIDE  Optional path to a custom prompt file in the caller
#                         repo. When set, it FULLY replaces the default
#                         template (we still inject the target list /
#                         repository metadata / additional instructions).
#   EXTRA_INSTRUCTIONS    Optional multi-line string appended to the prompt
#                         under "## Additional Instructions".
#   REPO_FULL_NAME        e.g. "octocat/hello-world".
#   BASE_BRANCH           e.g. "main".
set -euo pipefail

: "${DEFAULT_PROMPT_PATH:?DEFAULT_PROMPT_PATH is required}"
: "${OUTPUT_PATH:?OUTPUT_PATH is required}"

base_prompt_path="$DEFAULT_PROMPT_PATH"
if [[ -n "${PROMPT_FILE_OVERRIDE:-}" ]]; then
  if [[ ! -f "$PROMPT_FILE_OVERRIDE" ]]; then
    echo "::error::prompt_file '$PROMPT_FILE_OVERRIDE' was specified but does not exist in the caller repo"
    exit 1
  fi
  base_prompt_path="$PROMPT_FILE_OVERRIDE"
fi

mkdir -p "$(dirname "$OUTPUT_PATH")"

{
  echo "# AGENTS.md Update Task"
  echo
  echo "Repository: \`${REPO_FULL_NAME:-unknown}\`"
  echo "Base branch: \`${BASE_BRANCH:-unknown}\`"
  echo
  echo "## Files to Maintain"
  echo
  if [[ -n "${DISCOVERED_TARGETS:-}" ]]; then
    while IFS= read -r f; do
      [[ -z "$f" ]] && continue
      echo "- \`$f\`"
    done <<< "$DISCOVERED_TARGETS"
  else
    echo "_(none discovered)_"
  fi
  echo
  echo "---"
  echo
  cat "$base_prompt_path"
} > "$OUTPUT_PATH"

if [[ -n "${EXTRA_INSTRUCTIONS:-}" ]]; then
  {
    echo
    echo "---"
    echo
    echo "## Additional Instructions"
    echo
    printf '%s\n' "$EXTRA_INSTRUCTIONS"
  } >> "$OUTPUT_PATH"
fi

echo "Wrote prompt to $OUTPUT_PATH ($(wc -l < "$OUTPUT_PATH") lines)"
