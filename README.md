# agents-md-updater

A reusable GitHub Workflow that uses **Codex** or **Claude Code** to keep
your project's `AGENTS.md` (and/or `CLAUDE.md`) faithful to the current state
of the codebase. Drops into any repo, supports monorepos with multiple
`AGENTS.md` files, and ships with [`act`](https://github.com/nektos/act)
fixtures so you can test it locally without burning API credit.

- Pluggable agent: `codex` or `claude`
- Auth via API key **or** OAuth token; optional custom base URL for both
- Configurable trigger: cron, push to specific paths, manual dispatch, or
  after-PR-merged (or anything else GitHub Actions supports)
- Multi-directory aware: scans every directory you list, picks up nested
  `AGENTS.md`/`CLAUDE.md`, sends them all to a single agent run
- Output: open a Pull Request (default) or push directly to a branch
- Local testing with `act` and the included `tests/run-act.sh` driver

---

## Quick start

Pick one of the [`examples/`](examples) and copy it into
`.github/workflows/update-agents-md.yml` of **your** repo. The minimal form
looks like this:

```yaml
name: Update AGENTS.md
on:
  schedule:
    - cron: "0 3 * * 1"
  workflow_dispatch: {}

permissions:
  contents: write
  id-token: write
  pull-requests: write

jobs:
  update:
    uses: sheepbox8646/agents-md-updater/.github/workflows/update-agents-md.yml@main
    with:
      agent: codex
      target_files: AGENTS.md,CLAUDE.md
      directories: |
        .
        packages/api
        apps/web
    secrets:
      OPENAI_API_KEY: ${{ secrets.OPENAI_API_KEY }}
```

> Pin to `@main` while you experiment, then move to a tag (e.g. `@v1`) once
> we cut releases.
>
> If you use `agent: claude` (or let users switch to Claude via
> `workflow_dispatch`), the **caller workflow** must grant
> `permissions: id-token: write`. This is required by
> `anthropics/claude-code-action` for GitHub App OIDC auth and is harmless for
> Codex.

---

## Inputs

| Input | Type | Default | Description |
| --- | --- | --- | --- |
| `agent` | string | (required) | `codex` or `claude` |
| `target_files` | string | `AGENTS.md` | Comma-separated file names to maintain. |
| `directories` | string | `.` | Newline-separated list of directories to scan recursively. |
| `base_branch` | string | repo default | Branch to PR/commit against. |
| `output_mode` | string | `pr` | `pr` (open a pull request) or `commit` (push to `base_branch`). |
| `pr_branch` | string | `agents-md-updater/<run_id>` | Head branch for the PR. |
| `pr_title` | string | `chore: update AGENTS.md` | PR title. |
| `pr_body` | string | auto-generated | PR body. |
| `commit_message` | string | `chore: update AGENTS.md` | Commit message. |
| `model` | string | `''` | Optional model override forwarded to the agent. |
| `prompt_file` | string | `''` | Path (in caller repo) to a custom prompt that fully replaces the default template. |
| `extra_instructions` | string | `''` | Multi-line string appended to the default prompt under `## Additional Instructions`. |
| `codex_responses_endpoint` | string | `''` | Custom Responses API endpoint for Codex (e.g. Azure). |
| `anthropic_base_url` | string | `''` | Custom `ANTHROPIC_BASE_URL` for Claude. |
| `runs_on` | string | `ubuntu-latest` | Runner label. |
| `tools_ref` | string | `main` | Git ref of `sheepbox8646/agents-md-updater` to fetch scripts/prompt from. |
| `dry_run` | boolean | `false` | Skip the real agent and only append a marker line. Used by `tests/run-act.sh`. |

## Secrets

| Secret | When to set |
| --- | --- |
| `OPENAI_API_KEY` | Required when `agent: codex`. |
| `ANTHROPIC_API_KEY` | Set this **or** `CLAUDE_CODE_OAUTH_TOKEN` when `agent: claude`. |
| `CLAUDE_CODE_OAUTH_TOKEN` | Set this **or** `ANTHROPIC_API_KEY` when `agent: claude`. Generate with `claude setup-token` (Pro/Max plans). |
| `GH_TOKEN` | Optional. Use a PAT or GitHub App token if the default `GITHUB_TOKEN` cannot push to your branch / open the PR (e.g. you need cross-repo writes or a fine-grained token). |

The workflow only validates the secrets it needs for the chosen agent, so you
do not have to set the other ones.

## Workflow permissions

When `agent: claude`, your **caller workflow** must include:

```yaml
permissions:
  contents: write
  id-token: write
  pull-requests: write
```

Why: `anthropics/claude-code-action` uses GitHub OIDC when operating through
the default Claude GitHub App. Without `id-token: write`, GitHub refuses to
mint the JWT and the action fails with:

```text
Could not fetch an OIDC token. Did you remember to add `id-token: write` to your workflow permissions?
```

This is especially important for **external reusable workflows** like this
repository: the permission must be granted by the **caller** workflow, not just
inside the called workflow.

---

## Authentication recipes

### Codex with `OPENAI_API_KEY`

```yaml
with:
  agent: codex
secrets:
  OPENAI_API_KEY: ${{ secrets.OPENAI_API_KEY }}
```

### Codex against Azure (or any custom Responses endpoint)

```yaml
with:
  agent: codex
  codex_responses_endpoint: https://YOUR_PROJECT.openai.azure.com/openai/v1/responses
secrets:
  OPENAI_API_KEY: ${{ secrets.AZURE_OPENAI_API_KEY }}
```

### Claude Code with `ANTHROPIC_API_KEY`

```yaml
permissions:
  id-token: write

with:
  agent: claude
secrets:
  ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
```

### Claude Code with an OAuth token (Pro / Max plans)

Run `claude setup-token` locally, copy the token, and store it as
`CLAUDE_CODE_OAUTH_TOKEN`:

```yaml
permissions:
  id-token: write

with:
  agent: claude
secrets:
  CLAUDE_CODE_OAUTH_TOKEN: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
```

### Claude Code via a custom base URL

```yaml
permissions:
  id-token: write

with:
  agent: claude
  anthropic_base_url: https://my-proxy.example.com
secrets:
  ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
```

---

## Triggers

The reusable workflow runs on `workflow_call`, so you choose the trigger in
your **caller** workflow. See [`examples/`](examples) for working samples:

- [`cron.yml`](examples/cron.yml) - weekly scheduled refresh.
- [`on-push-paths.yml`](examples/on-push-paths.yml) - run when code in
  specific directories changes on `main`.
- [`manual-dispatch.yml`](examples/manual-dispatch.yml) -
  `workflow_dispatch` with UI inputs for agent / scope / output mode.
- [`after-pr-merged.yml`](examples/after-pr-merged.yml) - run after a PR is
  merged to the default branch.

You can mix any number of triggers in a single caller workflow.

---

## Multiple AGENTS.md files

For monorepos, list each scope under `directories`:

```yaml
with:
  directories: |
    .
    packages/api
    packages/web
    apps/admin
  target_files: AGENTS.md,CLAUDE.md
```

The workflow will:

1. Walk each listed directory recursively (skipping `node_modules`, `.git`,
   `dist`, `build`, `vendor`, `.venv`, `target`).
2. Collect every matching `AGENTS.md` / `CLAUDE.md`.
3. Hand the deduplicated list to a **single** agent run.

The default prompt instructs the agent to keep each file scoped to its own
directory and to avoid duplicating parent content.

---

## Customising the prompt

Two layers, applied in order:

1. **Replace** the default template entirely with `prompt_file: path/to/prompt.md`.
   The path is resolved inside the caller repo.
2. **Append** project-specific notes with `extra_instructions: |`. They show
   up under a new `## Additional Instructions` section at the end of the
   final prompt and complement the default template.

```yaml
with:
  agent: codex
  extra_instructions: |
    - Keep "Build & Test" up-to-date with package.json scripts.
    - Mention that this repo uses pnpm workspaces.
    - Do not edit anything under docs/.
```

---

## Local testing with `act`

```bash
# dry-run, no API keys needed
./tests/run-act.sh                          # workflow_dispatch + codex
./tests/run-act.sh push                     # push event
./tests/run-act.sh workflow_dispatch claude

# live (real APIs, costs money)
cp tests/secrets.example tests/.secrets
$EDITOR tests/.secrets
LIVE=1 ./tests/run-act.sh workflow_dispatch codex
```

Under `act` the reusable workflow:

- Skips the cross-repo checkout and copies the local `scripts/` and
  `prompts/` directories so your edits are picked up immediately.
- In dry-run mode, appends a marker comment to each discovered target file
  instead of calling the agent, then commits the diff locally without
  pushing or opening a PR.

See [`tests/README.md`](tests/README.md) for the full layout.

---

## Security notes

- The default `output_mode: pr` is the safest setting; a human still reviews
  every change before it lands.
- The Codex action defaults to `safety-strategy: drop-sudo` and the
  `workspace-write` sandbox; the agent cannot escalate privileges or reach
  the network mid-run.
- The Claude prompt explicitly tells the agent **not** to commit, push, or
  open PRs - all git operations happen in our `apply-changes.sh` step using
  `GITHUB_TOKEN` (or `GH_TOKEN` if provided).
- `tests/.secrets` is git-ignored. Never commit real keys.
- Pin `tools_ref` to a tag once you have one; `@main` will follow latest
  commits.

---

## Layout

```
agents-md-updater/
├── .github/workflows/
│   ├── update-agents-md.yml      # the reusable workflow (workflow_call)
│   └── ci.yml                     # self-test: shellcheck + actionlint + smoke
├── examples/                      # caller workflows for each trigger
├── prompts/update-agents-md.md    # default prompt template
├── scripts/                       # discover / build-prompt / apply-changes
├── tests/                         # act fixtures + driver
└── README.md
```

## License

MIT — see [`LICENSE`](LICENSE).
