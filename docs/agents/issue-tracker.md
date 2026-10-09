# Issue tracker: Linear

Issues and specs for this repo live in **Linear**: workspace `solenix`, team
`SOL`, project **Event Horizon**. GitHub Issues stay open for bug reports from
the public (the bug-report form); a maintainer copies each accepted one into
Linear and closes it on GitHub with a link.

Use the Linear MCP tools when your agent has them; otherwise the GraphQL API
at `https://api.linear.app/graphql` with a personal API key (`LINEAR_API_KEY`).

## Conventions

- **Create an issue**: `save_issue` (MCP) or `issueCreate` with `teamId`,
  `projectId` (Event Horizon), `title`, `description` (Markdown).
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

Used by `/wayfinder`. The **map** is a single Linear issue with **child**
issues as tickets.

- **Map**: one issue labelled `wayfinder:map`, holding the Notes /
  Decisions-so-far / Fog body.
- **Child ticket**: a sub-issue of the map (`parentId`), labelled
  `wayfinder:<type>` (`research`/`prototype`/`grilling`/`task`). Once claimed,
  it is assigned to the driving dev.
- **Blocking**: Linear's native **blocks / blocked by** relations
  (`issueRelationCreate` with `type: blocks`). A ticket is unblocked when every
  blocker is completed or canceled.
- **Frontier query**: the map's open sub-issues with no open blocker and no
  assignee; first in the map's sort order wins.
- **Claim**: assign the ticket to yourself, the session's first write.
- **Resolve**: comment the answer, complete the ticket, then append a context
  pointer (gist + link) to the map's Decisions-so-far.
