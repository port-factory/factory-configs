---
name: create-factory-line
description: Create and install a Port software factory line with factory-cli - a YAML that defines stages (Claude agents, workflows, human approvals), checkpoints and the repo the agents work on. Use when the user wants to build, change or debug a factory line, set up an org for the software factory, or install a line from YAML.
---

# Create a Port software factory line

A **line** is a sequence of **stages** a work item moves through. Each stage has an **executor** (a Claude managed agent, a Port workflow, or none) and **checkpoints** that must pass before the item moves on (a schema for the artifacts, a jq condition, or a human approval/question). `factory-cli` turns one YAML file into the Anthropic agents, the Claude integration, the service account and the line.

A complete, working example is in `references/example-ui-bugs-line.yaml`: reproduce a UI bug with a screenshot → fix with before/after screenshots and a PR, which waits until the PR is approved and green (requested changes send it back with the reviewer's comment) → merge.

## 1. Prerequisites (check them, don't assume)

1. **Port org with the software factory enabled** (contact Port to turn it on). The factory blueprints (`_factory_line`, `_factory_work_item`, ...) must exist; `factory-cli install --dry-run` checks this.
2. **GitHub integration through Port's GitHub app**, installed on the GitHub org, with **Contents: read and write** (and Pull requests: read and write) on the repos the agents touch. Port then keeps a rotating app token in the org secret `__GITHUB_OCEAN_<INSTALLATION>_<GITHUB_ORG>_ACCESS_TOKEN`.
3. **Credentials** in a `.env` (never commit it): `PORT_CLIENT_ID`, `PORT_CLIENT_SECRET` (org admin: avatar > Credentials > Organization), `PORT_REGION` (`eu` or `us`), `ANTHROPIC_API_KEY` (Claude Console > Keys & access).
4. **A repo the agents can run.** Add an `AGENTS.md` that says how to install, run, screenshot and test it. Agents follow it; a one-command way to run the app without external services (seeded in-memory data) makes reproduction reliable.

## 2. Write the line YAML

Start from `references/example-ui-bugs-line.yaml` and change only what's specific to the user. Full field reference: `references/line-yaml.md`.

Rules that prevent failed installs and stuck items:

- **`team` takes `_team` identifiers, not names**: `default_team`, not `default-team`. Check with `GET /v1/blueprints/_team/entities`.
- **Every Claude stage needs `executor_settings.execution_identity`** (a service account). Without it the agent can't call Port MCP, can't report, and the stage times out. The CLI creates missing service accounts (`service_accounts:` sets title/role; default role Admin).
- **Every agent stage needs a `schema` checkpoint** that lists the artifacts the agent must report, with `format: markdown` or `format: url`.
- **Instructions must end in a report.** Tell the agent to always call `report_work_item` (success, `needs_info` with a question, or `failed` with `retry: true` for environment errors) and never end without it.
- **Screenshots on the work item**: tell the agent to upload with Port MCP `create_markdown_image_upload` → run the returned `curlCommand` → `finalize_markdown_image_upload`, then put the returned markdown image in a markdown artifact and append it to the work item description in the same report. Images render only inside Port.
- **Gate on the pull request, not a form**: an `entity_condition` on the fix stage waits for the `githubPullRequest` entity (`match: { link: '{{ .workItem.artifacts.pr_url }}' }`) and moves on by itself when the entity matches `pass_when` (a Port query, not jq); the first `reject_when` rule whose query matches sends the item back to the stage with its `reason` (text with `{{ jq }}`) in the prompt. It needs the PR's review state and checks in the GitHub integration mapping: set the `pull-request` kind's selector to `api: graphql` and map `.reviewDecision` (falling back to the latest review per reviewer), `.statusCheckRollup.state`, and the latest change request's body and time (`changesRequestedAt`, a date-time), all into the blueprint. The condition has no memory of earlier rejections, so reject on changes requested only when `changesRequestedAt > {{ .stageRun.startedAt }}`. See `references/line-yaml.md`.
- **Human approvals**: `type: human_input`, `kind: approval`. On an agent stage's output it gates the next stage (`reject_to: cancel` to stop). A review stage is `executor: none` with the approval `on: input` and `reject_to: <fix stage>`; the reviewer's notes reach the next try's prompt. Responders via `usersQuery`, e.g. `{{ .workItem.requestedBy }}`.
- **Follow-ups after a rejection** start a new session: tell the fix agent to check for an existing `pr_url` artifact and push to that PR's branch instead of opening a new one.
- **Repo access**: `session.resources: [{ type: github_repository, url: ... }]` mounts the repo (clone/push). Pull requests go through Port MCP: set `github.token_secret` and the CLI creates the GitHub MCP server and connects the service accounts, so the agents get `github_*` tools. No vault, no `mcp_servers` on the agent.
- **Names are global in the Anthropic workspace.** Agents and environments are matched by name and updated in place, so prefix them per person or team (`dana-bug-fixer`) in a shared workspace.

## 3. Install

Install the Port factory CLI (`factory-cli`), then:

```bash
set -a; source .env; set +a        # not `node --env-file`: it won't override an ANTHROPIC_API_KEY already in your shell
npx factory-cli install my-line.yaml --dry-run   # read-only plan: factory, blueprints, agents, service accounts, integration, line
npx factory-cli install my-line.yaml
```

- `github.token_secret` is Port's rotating GitHub app token. The CLI also sets it as `executor_settings.git_access_token` (the secret's name) on every Claude stage, so mounted repos are cloned and pushed with a fresh token on every try. The plan says `connect <account> to github (rotates its client credentials)` for an existing service account: that's expected, the factory doesn't use them.
- Running `install` again is safe: it reuses or updates by name and never removes stages.
- Remove a line with `npx factory-cli uninstall <line> --delete-work-items --yes`.

## 4. Verify

- The plan says `create`/`update` for what you expect, and the install ends with `Done: line "<id>" created with N stage(s).`
- In Port: the line's entity page (`/_factory_lineEntity?identifier=<line>`) lists the stages; the Claude integration is **Running** with actions processing on.
- File a test item: `POST /v1/factory/work-items` with `title`, `description`, `line` and `requested_by` (the person who approves). Watch `GET /v1/factory/work-items/<id>`: `stage`, `state`, `artifacts`, `pendingInput`. The work item page shows the stage graph, the description (with screenshots) and artifacts.

## Known issues

- A line saved before `entity_condition` took Port queries (jq strings in `pass_when`/`reject_when`) can't be read or updated (`malformed_entity`). Delete it (`uninstall --delete-work-items --yes`) and install it again.
