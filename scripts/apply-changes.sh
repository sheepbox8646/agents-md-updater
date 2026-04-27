#!/usr/bin/env bash
# Detect the changes the agent produced and either commit them directly to the
# base branch or open a pull request from a generated branch.
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
#   DISCOVERED_TARGETS  Newline-separated list of target paths to stage.
#   GITHUB_TOKEN        Token used by `gh` to push and open the PR.
#   RUN_ID              github.run_id, used to build the default branch name.
#   REPO_FULL_NAME      Optional owner/repo, used to print a manual compare URL.
set -euo pipefail

mode="${OUTPUT_MODE:-pr}"
base_branch="${BASE_BRANCH:-main}"
pr_branch="${PR_BRANCH:-}"
pr_title="${PR_TITLE:-chore: update AGENTS.md}"
commit_message="${COMMIT_MESSAGE:-chore: update AGENTS.md}"
agent="${AGENT:-unknown}"
dry_run="${DRY_RUN:-false}"
run_id="${RUN_ID:-local}"
repo_full_name="${REPO_FULL_NAME:-${GITHUB_REPOSITORY:-}}"

git config user.name "agents-md-updater[bot]"
git config user.email "agents-md-updater@users.noreply.github.com"

# Stage only the discovered target files. This prevents helper directories such
# as `.agents-md-updater/` from being committed as embedded repositories and
# avoids accidentally sweeping unrelated edits into the commit.
staged_any=false
while IFS= read -r target; do
  [[ -z "$target" ]] && continue
  git add -A -- "$target"
  staged_any=true
done <<< "${DISCOVERED_TARGETS:-}"

if [[ "$staged_any" != "true" ]]; then
  echo "::notice::No discovered target files were staged; nothing to commit."
  exit 0
fi

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

compare_url() {
  if [[ -n "$repo_full_name" ]]; then
    printf 'https://github.com/%s/compare/%s...%s?expand=1\n' \
      "$repo_full_name" "$base_branch" "$pr_branch"
  fi
}

emit_pr_fallback_notice() {
  echo "::warning::Branch '$pr_branch' was pushed, but this token is not allowed to create pull requests automatically."
  echo "::warning::Enable 'Settings -> Actions -> General -> Allow GitHub Actions to create and approve pull requests' or provide secrets.GH_TOKEN with a PAT / GitHub App token that can open PRs."
  if [[ -n "$repo_full_name" ]]; then
    echo "::notice::Open this URL to create the PR manually: $(compare_url)"
  else
    echo "::notice::Open a PR manually from '$pr_branch' into '$base_branch'."
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
      tmp_output="$(mktemp)"
      printf '%s\n' "$pr_body" > "$tmp_body"
      if gh pr create \
        --base "$base_branch" \
        --head "$pr_branch" \
        --title "$pr_title" \
        --body-file "$tmp_body" \
        >"$tmp_output" 2>&1; then
        cat "$tmp_output"
      else
        pr_create_output="$(cat "$tmp_output")"
        if printf '%s' "$pr_create_output" | grep -Eqi 'already exists|already has an open pull request'; then
          if gh pr edit "$pr_branch" --title "$pr_title" --body-file "$tmp_body" >"$tmp_output" 2>&1; then
            cat "$tmp_output"
          else
            cat "$tmp_output" >&2
            rm -f "$tmp_body" "$tmp_output"
            exit 1
          fi
        elif printf '%s' "$pr_create_output" | grep -qi 'not permitted to create or approve pull requests'; then
          cat "$tmp_output" >&2
          emit_pr_fallback_notice
        else
          cat "$tmp_output" >&2
          rm -f "$tmp_body" "$tmp_output"
          exit 1
        fi
      fi
      rm -f "$tmp_body" "$tmp_output"
    else
      echo "::warning::gh CLI not available; branch pushed to '$pr_branch' but PR was not opened."
      if [[ -n "$repo_full_name" ]]; then
        echo "::notice::Open this URL to create the PR manually: $(compare_url)"
      fi
    fi
    ;;
  *)
    echo "::error::Unknown OUTPUT_MODE='$mode'"
    exit 1
    ;;
esac
