#!/usr/bin/env bash
# Drive `act` against the local reusable workflow.
#
# Usage:
#   ./tests/run-act.sh                          # workflow_dispatch + codex + dry_run
#   ./tests/run-act.sh push                     # push event + dry_run
#   ./tests/run-act.sh workflow_dispatch claude # manual + claude + dry_run
#   LIVE=1 ./tests/run-act.sh workflow_dispatch codex
#       Disables dry-run; reads tests/.secrets for OPENAI_API_KEY etc.
#       NOTE: live runs will hit real APIs and incur cost.
#
# Optional env:
#   AMD_DIRECTORIES   override directories input
#   AMD_TARGET_FILES  override target_files input
#   AMD_OUTPUT_MODE   override output_mode input
#   ARCH              container arch passed to act (default linux/amd64)

set -euo pipefail

cd "$(dirname "$0")/.."

EVENT="${1:-workflow_dispatch}"
AGENT="${2:-claude}"
ARCH="${ARCH:-linux/amd64}"
DRY_RUN="${LIVE:+false}"
DRY_RUN="${DRY_RUN:-true}"

if ! command -v act >/dev/null 2>&1; then
  echo "::error::'act' is not installed. See https://github.com/nektos/act#installation" >&2
  exit 127
fi

EVENT_FILE="tests/events/${EVENT}.json"
if [[ ! -f "$EVENT_FILE" ]]; then
  echo "::error::No fixture event file at $EVENT_FILE" >&2
  exit 1
fi

SECRETS_FILE="tests/.secrets"
if [[ "$DRY_RUN" != "true" && ! -f "$SECRETS_FILE" ]]; then
  echo "::error::LIVE=1 requires tests/.secrets (copy from tests/secrets.example)." >&2
  exit 1
fi

# Build act command
args=(
  "$EVENT"
  -W tests/caller-workflow.yml
  -e "$EVENT_FILE"
  --container-architecture "$ARCH"
  --input "agent=$AGENT"
  --input "directories=${AMD_DIRECTORIES:-tests/fixtures/sample-repo}"
  --input "target_files=${AMD_TARGET_FILES:-AGENTS.md,CLAUDE.md}"
  --input "output_mode=${AMD_OUTPUT_MODE:-pr}"
  --input "dry_run=$DRY_RUN"
)

if [[ -f "$SECRETS_FILE" ]]; then
  args+=(--secret-file "$SECRETS_FILE")
fi

echo "+ act ${args[*]}"
exec act "${args[@]}"
