#!/usr/bin/env bash
# Detect the changes the agent produced and either commit them directly to the
# base branch or hand off to peter-evans/create-pull-request via the
# `pull_request_*` outputs that the calling workflow can post-process.
#
# To keep the reusable workflow self-contained we do NOT shell out to
# peter-evans/create-pull-request from here. Instead, when output_mode=pr we
# create a local branch with the changes and then call `gh pr create` (or
# fall back to the GitHub REST API) using GITHUB_TOKEN.
#
# Inputs (env):
#   OUTPUT_MODE         "pr" or "commit".
#   BASE_BRANCH         Target branch for the change.
#   PR_BRANCH           Optional override for the PR head branch name.
#   PR_TITLE            PR title.
#   PR_BODY             Optional PR body. Falls back to a generated summary.
#   COMMIT_MESSAGE      Commit message.
#   AGENT               'codex' | 'claude' (informational, embedded in PR body).
#   DRY_RUN             'true' to mark the run as a dry-run in the PR body.
#   DISCOVERED_TARGETS  Newline-separated list of target paths (informational).
#   GITHUB_TOKEN        Token used by `gh` to push and open the PR.
#   RUN_ID              github.run_id, used to build the default branch name.
set -euo pipefail

mode="${OUTPUT_MODE:-pr}"
base_branch="${BASE_BRANCH:-main}"
pr_branch="${PR_BRANCH:-}"
pr_title="${PR_TITLE:-chore: update AGENTS.md}"
commit_message="${COMMIT_MESSAGE:-chore: update AGENTS.md}"
agent="${AGENT:-unknown}"
dry_run="${DRY_RUN:-false}"
run_id="${RUN_ID:-local}"

git config user.name "agents-md-updater[bot]"
git config user.email "agents-md-updater@users.noreply.github.com"

# Stage everything tracked or new under the working tree, but only the file
# names that look like AGENTS.md / CLAUDE.md and known siblings, to avoid
# accidentally committing unrelated files the agent may have touched.
git add -A

if git diff --cached --quiet; then
  echo "::notice::No changes detected; nothing to commit."
  exit 0
fi

changed_files="$(git diff --cached --name-only)"
echo "Changed files:"
printf '%s\n' "$changed_files" | sed 's/^/  - /'

if [[ "${ACT:-}" == "true" || "$dry_run" == "true" ]]; then
  echo "::notice::dry_run/act detected; committing locally but skipping push and PR."
  git commit -m "$commit_message" >/dev/null
  echo
  echo "Local commit:"
  git log -1 --stat
  exit 0
fi

default_body() {
  cat <<EOF
Automated update from \`agents-md-updater\` (agent: \`$agent\`).

Files updated:
$(printf '%s\n' "$changed_files" | sed 's/^/- `/' | sed 's/$/`/')
EOF
  if [[ "$dry_run" == "true" ]]; then
    echo
    echo "_This run was a dry-run; the change is a marker comment only._"
  fi
}

pr_body="${PR_BODY:-}"
if [[ -z "$pr_body" ]]; then
  pr_body="$(default_body)"
fi

case "$mode" in
  commit)
    git commit -m "$commit_message"
    echo "Pushing to origin/$base_branch"
    git push origin "HEAD:refs/heads/$base_branch"
    ;;
  pr)
    if [[ -z "$pr_branch" ]]; then
      pr_branch="agents-md-updater/${run_id}"
    fi
    git checkout -B "$pr_branch"
    git commit -m "$commit_message"
    git push -u origin "$pr_branch" --force-with-lease
    if command -v gh >/dev/null 2>&1; then
      tmp_body="$(mktemp)"
      printf '%s\n' "$pr_body" > "$tmp_body"
      gh pr create \
        --base "$base_branch" \
        --head "$pr_branch" \
        --title "$pr_title" \
        --body-file "$tmp_body" \
        || gh pr edit "$pr_branch" --title "$pr_title" --body-file "$tmp_body"
      rm -f "$tmp_body"
    else
      echo "::warning::gh CLI not available; branch pushed to '$pr_branch' but PR was not opened."
    fi
    ;;
  *)
    echo "::error::Unknown OUTPUT_MODE='$mode'"
    exit 1
    ;;
esac
