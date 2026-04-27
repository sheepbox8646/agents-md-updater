# Tests

Local smoke testing for the reusable workflow using
[`act`](https://github.com/nektos/act).

## Prerequisites

- Docker (for act)
- `act` installed (`brew install act` / `gh extension install nektos/gh-act`)

## Quick start (dry-run, no API keys)

```bash
./tests/run-act.sh                       # workflow_dispatch + codex + dry-run
./tests/run-act.sh push                  # push event + dry-run
./tests/run-act.sh workflow_dispatch claude
```

The dry-run path does NOT call OpenAI or Anthropic. Instead, the workflow
appends a marker comment to each discovered target file and the
`apply-changes.sh` step commits the diff locally inside the act container.
This validates everything except the agent step itself.

## Live run (real APIs)

1. `cp tests/secrets.example tests/.secrets`
2. Fill in the keys you need (`OPENAI_API_KEY` and/or `ANTHROPIC_API_KEY`).
3. `LIVE=1 ./tests/run-act.sh workflow_dispatch codex`

`tests/.secrets` is git-ignored. Live runs will hit real APIs and may incur
cost.

## Layout

```
tests/
├── caller-workflow.yml      # local-only caller, never copy to a real repo
├── events/                  # event payloads consumed by act -e
│   ├── push.json
│   ├── workflow_dispatch.json
│   └── schedule.json
├── fixtures/sample-repo/    # tiny project with multiple AGENTS.md / CLAUDE.md
├── secrets.example          # template for tests/.secrets
└── run-act.sh               # main test driver
```

## How `act` integration works

The reusable workflow normally does a second `actions/checkout` of
`sheepbox8646/agents-md-updater` to obtain the scripts and default prompt.
Under `act` we set `env.ACT == 'true'`, which causes the workflow to skip
that checkout and instead `cp -R` the local `scripts/` and `prompts/`
directories into `.agents-md-updater/`. This means edits in your local
working tree are picked up immediately.

`apply-changes.sh` similarly notices `ACT=true` (or `dry_run=true`) and
commits locally without pushing or opening a PR.

## Tips

- `act` defaults to `nektos/act-environments-ubuntu:18.04` which is heavy. If
  you hit issues, try `-P ubuntu-latest=catthehacker/ubuntu:act-latest`.
- macOS Apple Silicon: keep `--container-architecture linux/amd64` (already
  passed by `run-act.sh`).
- Pass `AMD_DIRECTORIES=. AMD_TARGET_FILES=AGENTS.md` to scan this repo's
  own root instead of the fixture.
