---
type: Agent Config
sources:
  - https://github.com/SolenixAI/event-horizon
  - .agents/skills/setup-matt-pocock-skills/issue-tracker-github.md
generated: 2026-10-25
verified: 2026-10-25
status: current
stale_after: 2027-01-25
---

# Issue tracker: GitHub

Issues and specs for this repo live in GitHub Issues for
`SolenixAI/event-horizon`. Use the connected GitHub tools when they support the
requested operation; otherwise use the authenticated `gh` CLI. If neither is
available, use the user's signed-in GitHub browser session when possible and
report any operation that remains blocked.

## Conventions

- **Create an issue**: `gh issue create --title "..." --body "..."`. Use a
  heredoc for multi-line bodies.
- **Read an issue**:
  `gh issue view <number> --json number,title,body,labels,comments`.
- **List issues**:
  `gh issue list --state open --json number,title,body,labels,comments` with
  appropriate `--label` and `--state` filters.
- **Make an issue a sub-issue of a parent**: use GitHub's native sub-issue
  support when available. Otherwise add `Part of #<parent>` to the child issue
  body.
- **Comment on an issue**: `gh issue comment <number> --body "..."`.
- **Apply / remove labels**: `gh issue edit <number> --add-label "..."` /
  `--remove-label "..."`.
- **Close**: `gh issue close <number> --comment "..."`.

Infer the repository from `git remote -v`; `gh` does this automatically inside a
clone.

## Pull requests as a triage surface

**PRs as a request surface: no.** _(Set to `yes` if this repo treats external
PRs as feature requests; `/triage` reads this flag.)_

When set to `yes`, use the `gh pr` equivalents to read, list, comment on, label,
or close external pull requests. GitHub shares one number space across issues
and pull requests, so resolve a bare `#42` with `gh pr view 42` and fall back to
`gh issue view 42`.

## When a skill says "publish to the issue tracker"

Create a GitHub issue in `SolenixAI/event-horizon`.

## When a skill says "fetch the relevant ticket"

Read the GitHub issue as described under **Read an issue** above.

## Wayfinding operations

Used by `/wayfinder`. The map is a single GitHub issue with child issues as
tickets.

- **Map**: one issue labelled `wayfinder:map`, holding the Notes /
  Decisions-so-far / Fog body.
- **Child ticket**: link the issue as a GitHub sub-issue when supported.
  Otherwise add it to the map's task list and put `Part of #<map>` at the top of
  the child.
- **Blocking**: use GitHub issue dependencies when available; otherwise add a
  `Blocked by: #<n>` line at the top of the child issue.
- **Frontier query**: list open child issues, then skip any with an open blocker
  or an assignee; the first remaining item in map order is next.
- **Claim**: assign the issue to the current user before beginning work.
- **Resolve**: comment with the answer, close the issue, then add a context
  pointer to the map's Decisions-so-far.
