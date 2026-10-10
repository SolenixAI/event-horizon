# Terminus

A terminus is unavoidable, uncontrollable and unpredictable
([AGENTS.md §7](AGENTS.md#7-time-matters)). This repo can't remove these items.
It can only push on their time to terminus from what it controls.

## Paths that other tools control

| Path                               | Controlled by                                   | Why it sits here                                                                                                        |
| ---------------------------------- | ----------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| `AGENTS.md`                        | [Arbiter](https://github.com/SolenixAI/arbiter) | Every agent reads the instructions file at the root. It is Arbiter's release, byte for byte; never edit it here.        |
| `.agents/`                         | The `skills` CLI                                | The one real copy of the engine skills, for any agent.                                                                  |
| `skills-lock.json`                 | The `skills` CLI                                | It records which engine skills are installed, and from where.                                                           |
| `.claude/`, `.cursor/`, `.codex/`  | The engines' installers                         | Links and hooks they write for agents that don't read `.agents/` yet. Never hand-edit; delete each once its agent does. |
| `PRODUCT.md`, `DESIGN.md`          | Impeccable Design                               | Its skill reads product and design context at the root.                                                                 |
| `README.md`, `LICENSE`, `.github/` | GitHub                                          | The repo page, issue forms, workflows and Dependabot.                                                                   |
| `.pre-commit-config.yaml`          | pre-commit                                      | It reads its hooks at the root.                                                                                         |
| `Glimmer.xcodeproj/`               | Xcode                                           | The project file the build runs from.                                                                                   |

## Events that others control

| Event                              | Controlled by        | How this repo pushes on it                           |
| ---------------------------------- | -------------------- | ---------------------------------------------------- |
| A new Arbiter release              | Arbiter              | A job brings `AGENTS.md` to the new release.         |
| A new engine release               | The engines' authors | `npx skills update` brings the skills current.       |
| An agent starts reading `.agents/` | Its vendor           | Delete that agent's folder in the same pull request. |
