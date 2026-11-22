# Line YAML reference (factory-cli)

Top-level keys:

| Key | What it does |
|---|---|
| `integration` | `installation_id` (Claude integration to use or install) |
| `github` | `token_secret` (org secret with a GitHub token, e.g. Port's rotating app token `__GITHUB_OCEAN_<installation>_<org>_ACCESS_TOKEN`), `mcp` (`identifier`, `allowed_tools`, or `false`). Creates the GitHub MCP server in Port and connects the service accounts to it |
| `defaults` | `model` for new agents, default `environment` for Claude stages |
| `environments` | Anthropic environments by name. `{}` = cloud, unrestricted networking. `config` is passed to Anthropic (e.g. `packages`) |
| `agents` | Anthropic agents by name: `system_prompt`, `model`, `description`, `skills`, `port_mcp` (default true: adds Port MCP, always allowed), `config` (passed to Anthropic: `mcp_servers`, `tools`, ...) |
| `service_accounts` | Service accounts by email (`...@serviceaccounts.getport.io`): `title`, `role` (default `Admin`). Execution identities are created even if not listed here |
| `workflows` | Port workflows for `custom_workflow` stages, created or replaced before the line |
| `intake` | Jira issues filed as work items (`type: jira`, `query` jq, optional `jql`) |
| `line` | `identifier`, `title`, `description`, `team` (list of `_team` identifiers), `stages` |

## Stage

```yaml
- identifier: fix
  title: Fix
  executor: claude_managed_agent        # or custom_workflow, human, none
  agent: my-bug-fixer                   # name under agents:, or agent_id
  environment: my-env                   # optional, defaults.environment otherwise
  executor_settings:
    execution_identity: { type: service_account, identifier: factory-agent@serviceaccounts.getport.io }
  session:
    resources: [{ type: github_repository, url: 'https://github.com/my-org/my-repo' }]
  instructions: |
    ...                                 # the stage's prompt; end with "always call report_work_item"
  checkpoints: [...]
  max_tries: 3                          # 1-10
  timeout: 1h                           # 1m-7d; agent stages default to 2h
```

## Checkpoints

```yaml
# Artifacts the stage must report (at most one schema per stage, on output)
- identifier: artifacts
  type: schema
  schema:
    properties:
      pr_url: { type: string, format: url, title: Pull request }
      before_after: { type: string, format: markdown, title: Before and after }
    required: [pr_url, before_after]

# jq condition on the context ({workItem, line, stage})
- identifier: commit_looks_right
  type: condition
  expression: '(.workItem.artifacts.commit // "") | test("^[0-9a-f]{7,40}$")'

# Human approval. on: output (default) = after the stage; on: input = before it starts.
- identifier: approve_fix
  type: human_input
  kind: approval                        # or question (output only, no reject_to)
  title: Review the fix
  on: input
  responders:
    usersQuery:
      combinator: or
      rules:
        - { property: $identifier, operator: '=', value: '{{ .workItem.requestedBy }}' }
  reject_to: fix                        # a stage identifier, or cancel; default: the same stage
```

# Wait for an entity (e.g. the PR), pass or send back automatically. Output only; no form.
# pass_when and each reject_when query are Port queries over the entity; reason and progress are text with {{ jq }}.
- identifier: pr_ready
  type: entity_condition
  entity:
    blueprint: githubPullRequest
    match: { link: '{{ .workItem.artifacts.pr_url }}' }
  pass_when:
    combinator: and
    rules:
      - { property: reviewDecision, operator: '=', value: APPROVED }
      - { property: checksState, operator: in, value: [SUCCESS, NEUTRAL] }
  reject_when:                          # up to 10 rules; a matching one sends the item back with its reason
    - query:
        combinator: and
        rules:
          - { property: reviewDecision, operator: '=', value: CHANGES_REQUESTED }
          # No memory of earlier rejections: only a change request after this try started counts
          - { property: changesRequestedAt, operator: '>', value: '{{ .stageRun.startedAt }}' }
      reason: 'Changes requested: {{ .entity.properties.changesRequestedComment // "see the review" }}'
  progress: 'Review: {{ .entity.properties.reviewDecision // "pending" }}'
```

PR properties for that condition, in the GitHub integration's `pull-request` mapping (selector `api: graphql`; add the properties to the `githubPullRequest` blueprint):

```yaml
reviewDecision: >-
  .reviewDecision // ([.reviews.nodes[]? | select(.state == "APPROVED" or .state == "CHANGES_REQUESTED")]
  | group_by(.author.login) | map(max_by(.createdAt).state)
  | if index("CHANGES_REQUESTED") != null then "CHANGES_REQUESTED" elif index("APPROVED") != null then "APPROVED" else "REVIEW_REQUIRED" end)
checksState: .statusCheckRollup.state
changesRequestedComment: '[.reviews.nodes[]? | select(.state == "CHANGES_REQUESTED")] | max_by(.createdAt)? | .body // null'
changesRequestedAt: '[.reviews.nodes[]? | select(.state == "CHANGES_REQUESTED")] | max_by(.createdAt)? | .createdAt // null'   # date-time
```

(GitHub's own `reviewDecision` is null unless branch protection requires reviews, hence the fallback.)

Order: schemas, then conditions, then human input. A rejection sends the item to `reject_to` with the responder's notes in the next try's prompt (try counter reset).

## Reporting (what agents call)

`report_work_item` with `stage_run`, `outcome` (`success`, `needs_info` + `questions`, `changes_requested` + `reason` + `to`, `failed` [+ `retry: true`]), `artifacts` (name → value) and optionally the work item's own fields (title, description) to update.

## Screenshots via Port MCP

1. `create_markdown_image_upload({ filename, contentType: "image/png", size })` → returns a `curlCommand`.
2. Run the `curlCommand` where the file is.
3. `finalize_markdown_image_upload({ key, name, altText })` → returns the image `url` and a `![alt](url)` snippet. Images render inside Port for org members only.

## GitHub through Port MCP

With `github.token_secret`, the CLI creates an `_mcp_server` entity (`github`) for `https://api.githubcopilot.com/mcp/` with the header `Authorization: {{ .secrets["<token_secret>"] }}`, then connects every service account to it (rotating an existing account's client credentials to sign in as it). Agents running as those accounts see `github_create_pull_request`, `github_merge_pull_request`, `github_pull_request_read`, ... in Port MCP. Don't add GitHub MCP or a vault to the agent.
