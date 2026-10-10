---
type: Agent Config
sources:
  - https://github.com/mattpocock/skills/blob/main/skills/engineering/wayfinder/SKILL.md
  - https://linear.app/docs/assigning-issues
generated: 2026-10-10T18:33-02:30
verified: 2026-10-10T18:33-02:30
status: current
stale_after: 2026-11-10
---

# Issue tracker: Linear

Issues and specs for this repo live in **Linear**: workspace `solenix`, team
`SOL`, project **Event Horizon**. GitHub Issues stay open for bug reports from
the public (the bug-report form); a maintainer copies each accepted one into
Linear and closes it on GitHub with a link.

Use the Linear MCP tools when your agent has them; otherwise the GraphQL API
at `https://api.linear.app/graphql` with a personal API key (`LINEAR_API_KEY`).

## Conventions

- **Create an issue**: start from the team template "Default issue". With MCP,
  `save_issue` with `template` "Default issue"; with GraphQL, `issueCreate`
  with `teamId` (SOL) and `templateId` (find "Default issue" with
  `list_templates`). Add `projectId` (Event Horizon), `title` and the
  assignee: `me` when the work is yours, `null` for an unclaimed wayfinder
  ticket. A description replaces the template body, so pass none. Then fill
  each `{…}` slot: update the issue with `save_issue` (set `id`) and a `patch`.
- **Read an issue**: `get_issue` with its identifier (`SOL-123`), plus
  `list_comments`.
- **List issues**: `list_issues` filtered by project **Event Horizon**, state
  and labels.
- **Make an issue a sub-issue of a parent**: set `parentId` on the child.
  Linear shows sub-issues natively.
- **Comment on an issue**: `save_comment` / `commentCreate`.
- **Apply / remove labels**: update the issue's `labelIds`.
- **Close**: move it to a completed state (Done) or Canceled, with a comment
  that says why.

## Pull requests as a triage surface

**PRs as a request surface: no.** _(Set to `yes` if this repo treats external
PRs as feature requests; `/triage` reads this flag.)_

## When a skill says "publish to the issue tracker"

Create a Linear issue in project Event Horizon.

## When a skill says "fetch the relevant ticket"

Read it as in **Read an issue** above.

## Wayfinding operations

Used by `/wayfinder`. The rules live in one place for every repo: the Linear
team skill **Wayfinder on Linear**. Read it with the Linear tools
(`list_agent_skills`, then `get_agent_skill`) before you chart or work a map.
