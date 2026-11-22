# factory-port

Build your own **Port software factory line**: an agent reproduces a bug and saves a screenshot on the work item through Port MCP, another agent fixes it, puts before/after screenshots on the work item and opens a PR, and once the PR is approved and green the line moves on and merges it by itself. Requested changes send it back to the fix agent with the reviewer's comment.

## What's here

| Path | |
|---|---|
| [`examples/ui-bugs-line.yaml`](examples/ui-bugs-line.yaml) | The line from the demo video: reproduce → fix (waits on the PR) → merge |
| [`examples/ui-features-line.yaml`](examples/ui-features-line.yaml) | A feature request from a GitHub issue to a merged PR: spec → a person approves the spec → build (waits on the PR) → merge. Install it after the bugs line, which defines the shared environment, service account and merge agent |
| [`examples/team-lines/`](examples/team-lines) | Lines for other teams, to show what a whole factory looks like: dependency upgrades and incident follow-ups (Platform), vulnerability remediation (Security), data quality alerts (Data Platform), crash fixes (Mobile), docs from merged PRs (Developer Experience). They mount no repos and nothing files work into them, so they install but never run: copy one as a starting point |
| [`.agents/skills/create-factory-line/`](.agents/skills/create-factory-line/SKILL.md) | A skill that teaches your coding agent to write, install and debug a line |
| `.claude/skills/`, `.cursor/skills/` | The same skill for Claude Code and Cursor (copies; see below) |

## Use the skill

Clone this repo (or copy the skill folder into your own repo) and ask your coding agent, for example: *"Create a factory line for `my-org/my-repo` that reproduces UI bugs with a screenshot, asks me before fixing, and opens a PR with before/after screenshots."*

- **Claude Code** reads `.claude/skills/`.
- **Cursor** reads `.cursor/skills/`.
- **Other agents** that support the [`.agents/skills`](https://agentskills.io) convention read `.agents/skills/`.

## Create a line by hand

1. A Port org with the software factory enabled (contact Port), and Port's GitHub app installed with **Contents: read and write**.
2. A `.env` with `PORT_CLIENT_ID`, `PORT_CLIENT_SECRET`, `PORT_REGION`, `ANTHROPIC_API_KEY`.
3. Copy `examples/ui-bugs-line.yaml` and change the repo URL, team, names and GitHub token secret.
4. Install the Port factory CLI (`factory-cli`), then:

   ```bash
   set -a; source .env; set +a
   npx factory-cli install ui-bugs-line.yaml --dry-run
   npx factory-cli install ui-bugs-line.yaml
   ```

The skill has the details, gotchas and known issues.

## Editing the skill

Edit only `.agents/skills/`, then run `scripts/sync-skills.sh`. CI fails if the copies drift.
