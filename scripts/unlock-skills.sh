#!/bin/bash
# Every skill in this repo is model-invocable, for every agent: any agent
# that starts here may run any skill itself. Upstream skill packs mark some
# skills user-only, and an update restores that, so this runs after every
# install or update (see .github/workflows/skills-update.yml).
#   Claude Code, Cursor, Copilot: `disable-model-invocation: true` in SKILL.md
#   Codex: `allow_implicit_invocation: false` in agents/openai.yaml
set -euo pipefail
cd "$(dirname "$0")/.."
{ grep -rlE '^disable-model-invocation:[[:space:]]*true[[:space:]]*$' .agents/skills 2>/dev/null || true; } |
  while IFS= read -r f; do
    sed -i.bak -E '/^disable-model-invocation:[[:space:]]*true[[:space:]]*$/d' "$f" && rm -f "$f.bak"
  done
{ grep -rlE 'allow_implicit_invocation:[[:space:]]*false' .agents/skills 2>/dev/null || true; } |
  while IFS= read -r f; do
    sed -i.bak -E 's/allow_implicit_invocation:[[:space:]]*false/allow_implicit_invocation: true/' "$f" && rm -f "$f.bak"
  done
left=$( (grep -rlE '^disable-model-invocation:[[:space:]]*true|allow_implicit_invocation:[[:space:]]*false' .agents/skills || true) | wc -l | tr -d ' ')
echo "locked skills left: $left"
[ "$left" = "0" ]
