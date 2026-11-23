<!-- prettier-ignore-start -->

# Trust implementation plan

This plan establishes mechanical trust, strict verification, and developer velocity for Event Horizon.
It eliminates repository drift, enforces zero-warning builds, hardens architecture boundaries, and cuts test latency.
Work proceeds in six focused PRs with explicit evidence and zero interference with the monitor selection branch.
The PRs are PR-01, PR-02, PR-03, PR-04, PR-05, and PR-06.

## How to read this

One box is one unit of work. Every box names the evidence that checks it. A nested box is a sub-step of the box above it. Check a box only when its evidence exists, a file, a log line, a screenshot, a test run, or a SHA. The body is a how-to. The appendices explain and record.

The program runs `pstack/skills/poteto-mode/playbooks/autopilot-full.md`. The operator reviews before merge any PR that changes an interaction. All six PRs in this plan are infrastructure, CI, compiler settings, and developer tooling; they carry no interaction change and land autonomously once verified.

Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

## Program checklist

### Arm the program

- [ ] State the protocol and this plan to the operator, then stop. Start execution only on the operator's explicit go.
- [ ] Read these from trunk at program start. Re-read them at every tick.
  - [ ] `git show origin/main:pstack/skills/poteto-mode/playbooks/autopilot-full.md`
  - [ ] `git show origin/main:pstack/skills/swarm/SKILL.md`
  - [ ] `git show origin/main:scripts/check-architecture.sh`
  - [ ] `git show origin/main:pstack/skills/poteto-mode/playbooks/opening-a-pr.md`
  - [ ] `git show origin/main:pstack/skills/unslop/SKILL.md`
- [ ] On the operator's go, arm the audit tick as `/loop 1h` with the tick prompt below. Never leave the cadence to memory.
- [ ] Use this tick prompt, verbatim. "Re-read the execution playbook from trunk. Audit the operation against it and fix drift in this tick. Probe every active lane and judge progress by side effects only. Stand down a stuck lane and dispatch its replacement now. Then post a short status message to the operator in chat only when the audit found a tracked change that no earlier status message reported, such as a PR opened, a code-ready head, a round launched or closed, a verdict, a merge, a stuck agent and the action taken, a blocker added or cleared, or a decision only the operator can make. Name every such change and nothing else. Do not repeat a table, the merged list, or an unchanged blocker. If the audit found none, end the turn with no reply text. Either way, log this tick's row in your decision trail. The row names the items reported, or none."
- [ ] On the operator's hold or stand-down, send every owner a zero-writes order at once.

### Spawn owners

- [ ] Spawn one owner per PR with the full lifecycle the execution playbook names.
- [ ] Follow this dependency graph. Start dependent work only after its parent merges, or base it on the parent branch when the execution playbook stacks.
  - [ ] PR-01 is independent and first. It branches from `main`.
  - [ ] PR-02, PR-03, PR-04, PR-05, and PR-06 depend on PR-01 and branch in parallel once PR-01 lands.
- [ ] Hold the file boundaries. PR-01 touches only formatting and asset files. PR-02 touches only `.github/workflows/ci.yml`. PR-03 touches only Xcode project settings and intent declarations. PR-04 touches only `scripts/check-architecture.sh` and `Makefile`. PR-05 touches only `scripts/test-unit.sh` and pre-commit push hooks. PR-06 touches only documentation and agent guidelines. Never touch untracked monitor outputs files in `companion/src/outputs.rs` or `companion/tests/outputs.rs`.
- [ ] Hold the review gate. None of the PRs in this plan change a user interaction.

### PR mechanics, for every PR

- [ ] Resolve the forge once. Default to `gh`; if `command -v origin` succeeds and Origin can resolve the repository, use `origin pr` for every PR operation. Record any fallback to `gh`. Never require `gt`.
- [ ] Open the PR ready, never draft, per **Opening a PR**. Use the run's built-in PR tool when it has one, else `origin pr create --status open --base <base-branch>` or `gh pr create --base <base-branch>` according to the resolved forge. A stack child targets its parent branch.
- [ ] Run the repo's lint and typecheck once before the PR-facing push. Push with hooks on.
- [ ] Run `/deslop` before each commit and `/no-comments` before review.
- [ ] Triage every Bugbot and security-reviewer comment per `../references/bugbot-triage.md`.
- [ ] Rebase onto current trunk before the code-ready report and babysit. Keep that merge base in fix rounds. Rebase again only at merge prep, on a `git merge-tree` conflict with trunk, on a CI failure that comes from a change on trunk, or when a known concurrent change to the same files lands.

### Verdict and merge, for every PR

- [ ] A full swarm runs once, at the code-ready head. Another full swarm runs only for new behavior, a redesign, or a large new diff. A rebase, a merge-conflict resolution, or a minor fix gets a single verifier at the new head, and a wording-only change gets none. Run each full swarm per `pstack/skills/swarm/SKILL.md`. One gates lane. The ten live lanes from the PR's **Verify, live** block. The perf lane from its **Verify, perf** block. Two or more audit lanes, each with its own focus, that read the diff and the receipts and distrust the PR body. The root audits the receipts in the merge-ready report before the verdict.
- [ ] Judge every finding by the execution playbook's blocking rule. The verdict is clean when none blocks. A failure on trunk behavior in a lane marked `Regression lane against trunk.` is recorded against trunk and does not block the PR. A new head gets a fresh verdict, except for results that stay valid under the patch-id rule in `playbooks/shipping.md`.
- [ ] The owner squash-merges its own PR once verified, tested on the trunk it lands on.

### Boot recipe, for every live lane

Each live lane runs on its own runner at the PR head. Drive through `control-cli` from `cursor-team-kit`.

- [ ] `git fetch origin <head-branch> && git checkout <head SHA>`.
- [ ] Start the environment and check tool readiness with `make --version` and `swiftlint version`.
- [ ] Deliver input only through shell commands. Capture stdout and exit codes.
- [ ] Save every screenshot to `/tmp/swarm-<pr-id>/worker-<n>/<slug>.png` and return the paths with the report.

## Format repository assets and align pre-commit hooks (PR-01)

**Depends on.** None.

**Files.**

- [ ] Edit `.pre-commit-config.yaml`.
- [ ] Edit `brand/bodies.svg`.
- [ ] Edit `brand/glow.svg`.
- [ ] Edit `brand/horizon.svg`.
- [ ] Edit `brand/orbit.svg`.
- [ ] Edit `Glimmer/AppIcon.icon/icon.json`.
- [ ] Edit `Glimmer/Assets.xcassets/AccentColor.colorset/Contents.json`.
- [ ] Edit `docs/HOST_SETUP.md`.
- [ ] Edit `docs/PROFILING.md`.
- [ ] Edit `docs/adr/0001-fork-glimmer-and-build-only-the-experience.md`.
- [ ] Edit `docs/adr/0002-drive-an-unmodified-sunshine.md`.
- [ ] Edit `docs/adr/0003-one-rust-companion-with-os-seams.md`.
- [ ] Edit `DESIGN.md`.
- [ ] Edit `GLOSSARY.md`.
- [ ] Edit `.github/ISSUE_TEMPLATE/bug_report.yml`.
- [ ] Edit `.impeccable/surfaces/glimmer-deskhome-swift.md`.
- [ ] Edit `companion/src/sunshine_watchdog.rs`.

**Build.**

- [ ] Run `pre-commit run --all-files` to apply formatting across all assets.
- [ ] Run `cargo fmt` inside `companion/` to format tracked Rust sources.

**You see.**

- [ ] `pre-commit run --all-files` exits with code 0 on repeated runs.
- [ ] `git diff` shows clean newline additions and Prettier formatting without logic changes.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Run `pre-commit run --all-files` across the whole repository.
- [ ] Run `cargo fmt --check` inside `companion/`.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Ten lanes on `grok-4.7-xhigh-fast` at the PR head, per the boot recipe.

- [ ] Lane 1. Regression lane against trunk. Run `pre-commit run --all-files` at trunk and head. Trunk fails with modified files. Save `/tmp/swarm-pr-01/worker-1/pre-commit-regression.png`. Pass when head exits 0 with zero modified files.
- [ ] Lane 2. Verify SVG assets render cleanly. Inspect `brand/horizon.svg`. Save `/tmp/swarm-pr-01/worker-2/svg-horizon.png`. Pass when file contains trailing newline and valid XML tags.
- [ ] Lane 3. Verify JSON assets parse without syntax errors. Run `python3 -m json.tool Glimmer/AppIcon.icon/icon.json`. Save `/tmp/swarm-pr-01/worker-3/icon-json.png`. Pass when JSON validator exits 0.
- [ ] Lane 4. Verify documentation markdown formatting. Run `markdownlint docs/HOST_SETUP.md`. Save `/tmp/swarm-pr-01/worker-4/markdown-check.png`. Pass when markdownlint reports 0 errors.
- [ ] Lane 5. Verify YAML issue templates. Run `yamllint .github/ISSUE_TEMPLATE/bug_report.yml`. Save `/tmp/swarm-pr-01/worker-5/yaml-check.png`. Pass when yamllint reports 0 errors.
- [ ] Lane 6. Verify companion watchdog formatting. Run `git diff companion/src/sunshine_watchdog.rs`. Save `/tmp/swarm-pr-01/worker-6/rust-watchdog.png`. Pass when watchdog file matches rustfmt rules.
- [ ] Lane 7. Verify pre-commit config does not touch untracked files. Run `git status -s`. Save `/tmp/swarm-pr-01/worker-7/git-status.png`. Pass when untracked outputs.rs files remain untouched.
- [ ] Lane 8. Verify SwiftLint pass after formatting. Run `swiftlint lint --quiet`. Save `/tmp/swarm-pr-01/worker-8/swiftlint.png`. Pass when SwiftLint reports 0 violations.
- [ ] Lane 9. Verify secret scanning hook. Run `pre-commit run trufflehog --all-files`. Save `/tmp/swarm-pr-01/worker-9/trufflehog.png`. Pass when hook reports 0 verified secrets.
- [ ] Lane 10. Verify repeated pre-commit run idempotence. Run `pre-commit run --all-files` twice in succession. Save `/tmp/swarm-pr-01/worker-10/idempotence.png`. Pass when second run reports passed on every hook with zero file diffs.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Metric. Execution latency of `pre-commit run --all-files` on a clean working tree.
- [ ] Probe. Run `time pre-commit run --all-files` three times and record real elapsed time.
- [ ] Baseline. Record trunk elapsed time of 8.4 seconds with hook failures.
- [ ] Rule. Head execution time must remain under 12.0 seconds with all hooks passing.

**Review gate.** None. PR-01 is not review-gated.

**Merge.**

- [ ] Root's clean verdict at the exact head SHA.
- [ ] Bugbot triage done.
- [ ] Rebased onto current trunk after the verdict, patch-id unchanged.
- [ ] The owner squash-merges its own PR into main.

## Enforce complete pre-commit checks and Rust formatting in continuous integration (PR-02)

**Depends on.** PR-01.

**Files.**

- [ ] Edit `.github/workflows/ci.yml`.

**Build.**

- [ ] Add a `pre-commit` job in `.github/workflows/ci.yml` running `pre-commit run --all-files`.
- [ ] Add `cargo fmt --check` step to the `companion` matrix job in `.github/workflows/ci.yml`.
- [ ] Add `pre-commit` to the `ci-summary` dependency list.

**You see.**

- [ ] GitHub Actions runs pre-commit on all pull requests and catches formatting, YAML, JSON, and secret regressions.
- [ ] The `companion` matrix job verifies `cargo fmt` on both Ubuntu and Windows runners.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Run `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))"`.
- [ ] Run `bash scripts/test-release-tools.sh`.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Ten lanes on `grok-4.7-xhigh-fast` at the PR head, per the boot recipe.

- [ ] Lane 1. Regression lane against trunk. Inspect `.github/workflows/ci.yml` at trunk and head. Trunk lacks pre-commit job. Save `/tmp/swarm-pr-02/worker-1/ci-diff.png`. Pass when head workflow includes pre-commit job and companion fmt step.
- [ ] Lane 2. Validate YAML syntax of updated workflow. Run `yamllint .github/workflows/ci.yml`. Save `/tmp/swarm-pr-02/worker-2/yaml-lint.png`. Pass when yamllint reports 0 errors.
- [ ] Lane 3. Validate job dependency wiring. Run `python3 -c "import yaml; cfg = yaml.safe_load(open('.github/workflows/ci.yml')); assert 'pre-commit' in cfg['jobs']['ci-summary']['needs']"`. Save `/tmp/swarm-pr-02/worker-3/job-deps.png`. Pass when Python assertion passes.
- [ ] Lane 4. Verify runner OS selection for pre-commit. Check that the pre-commit job runs on `ubuntu-latest` for speed. Save `/tmp/swarm-pr-02/worker-4/runner-os.png`. Pass when job runs-on is ubuntu-latest.
- [ ] Lane 5. Verify cargo fmt step in companion job. Check that `cargo fmt --check` runs before `cargo clippy`. Save `/tmp/swarm-pr-02/worker-5/cargo-fmt.png`. Pass when step exists in companion job.
- [ ] Lane 6. Verify pre-commit tool caching. Inspect whether cache action is configured for pre-commit environments. Save `/tmp/swarm-pr-02/worker-6/cache-step.png`. Pass when pre-commit environment caching is defined.
- [ ] Lane 7. Verify permissions block in workflow. Ensure `permissions: contents: read` is preserved. Save `/tmp/swarm-pr-02/worker-7/permissions.png`. Pass when permissions remain read-only.
- [ ] Lane 8. Verify concurrency settings. Ensure `cancel-in-progress: true` remains active. Save `/tmp/swarm-pr-02/worker-8/concurrency.png`. Pass when concurrency group matches ci ref.
- [ ] Lane 9. Verify simulated failure on intentional drift. Run pre-commit hook check against staged trailing whitespace in a temporary file. Save `/tmp/swarm-pr-02/worker-9/drift-catch.png`. Pass when pre-commit hook halts commit.
- [ ] Lane 10. Verify ci-summary gate logic. Inspect `ci-summary` step condition. Save `/tmp/swarm-pr-02/worker-10/summary-gate.png`. Pass when failure in any required job fails ci-summary.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Metric. Estimated GitHub Actions runtime for the new pre-commit job on `ubuntu-latest`.
- [ ] Probe. Run `pre-commit run --all-files` inside an Ubuntu container and measure execution time.
- [ ] Baseline. Trunk has no pre-commit CI job (0 seconds).
- [ ] Rule. New pre-commit job duration must remain under 90 seconds on a warm cache.

**Review gate.** None. PR-02 is not review-gated.

**Merge.**

- [ ] Root's clean verdict at the exact head SHA.
- [ ] Bugbot triage done.
- [ ] Rebased onto current trunk after the verdict, patch-id unchanged.
- [ ] The owner squash-merges its own PR into main.

## Enforce zero compiler warnings and fix AppIntents framework metadata warnings (PR-03)

**Depends on.** PR-01.

**Files.**

- [ ] Edit `Glimmer.xcodeproj/project.pbxproj`.
- [ ] Edit `Glimmer/GlimmerIntents.swift`.

**Build.**

- [ ] Set `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` across all targets in `Glimmer.xcodeproj`.
- [ ] Set `GCC_TREAT_WARNINGS_AS_ERRORS = YES` for C and Objective-C compilation.
- [ ] Explicitly link `AppIntents.framework` to eliminate metadata processor warnings.

**You see.**

- [ ] `xcodebuild build` compiles cleanly with zero warnings.
- [ ] Any new compiler warning immediately halts the build.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Run `xcodebuild -project Glimmer.xcodeproj -scheme Glimmer -configuration Debug -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO`.
- [ ] Inspect build log to confirm zero compiler warning lines.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Ten lanes on `grok-4.7-xhigh-fast` at the PR head, per the boot recipe.

- [ ] Lane 1. Regression lane against trunk. Build Glimmer on trunk and head. Trunk logs AppIntents metadata processor warning. Save `/tmp/swarm-pr-03/worker-1/build-warnings.png`. Pass when head builds with 0 warning lines.
- [ ] Lane 2. Verify `SWIFT_TREAT_WARNINGS_AS_ERRORS` setting. Search `Glimmer.xcodeproj/project.pbxproj` for the flag. Save `/tmp/swarm-pr-03/worker-2/swift-flags.png`. Pass when all target configurations define YES.
- [ ] Lane 3. Verify `GCC_TREAT_WARNINGS_AS_ERRORS` setting. Search `Glimmer.xcodeproj/project.pbxproj` for the flag. Save `/tmp/swarm-pr-03/worker-3/gcc-flags.png`. Pass when all target configurations define YES.
- [ ] Lane 4. Verify helper target builds cleanly. Build helper target via `make helper-build`. Save `/tmp/swarm-pr-03/worker-4/helper-build.png`. Pass when helper compiles with zero warnings.
- [ ] Lane 5. Verify LoginHelper target builds cleanly. Build LoginHelper scheme via xcodebuild. Save `/tmp/swarm-pr-03/worker-5/login-helper.png`. Pass when LoginHelper compiles with zero warnings.
- [ ] Lane 6. Verify GlimmerTests target builds cleanly under strict warnings. Run `xcodebuild build-for-testing -project Glimmer.xcodeproj -scheme Glimmer -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`. Save `/tmp/swarm-pr-03/worker-6/test-build.png`. Pass when test target compiles with zero warnings.
- [ ] Lane 7. Verify AppIntents metadata extraction. Check build log for `appintentsmetadataprocessor`. Save `/tmp/swarm-pr-03/worker-7/appintents-log.png`. Pass when metadata extraction completes without warnings.
- [ ] Lane 8. Verify Release configuration build. Run `make release` dry-run or compile check. Save `/tmp/swarm-pr-03/worker-8/release-config.png`. Pass when Release configuration builds without warnings.
- [ ] Lane 9. Verify warning gate catches unused variable. Introduce temporary unused variable in a test file and compile. Save `/tmp/swarm-pr-03/worker-9/warning-trap.png`. Pass when compiler rejects build with error.
- [ ] Lane 10. Verify clean tree after build. Run `git status -s`. Save `/tmp/swarm-pr-03/worker-10/clean-tree.png`. Pass when working tree has zero untracked artifacts.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Metric. Incremental build duration of `Glimmer` target in Debug configuration.
- [ ] Probe. Touch `Glimmer/GlimmerApp.swift` and run `time make app`.
- [ ] Baseline. Trunk incremental build time of 4.8 seconds.
- [ ] Rule. Head incremental build time must remain under 6.5 seconds.

**Review gate.** None. PR-03 is not review-gated.

**Merge.**

- [ ] Root's clean verdict at the exact head SHA.
- [ ] Bugbot triage done.
- [ ] Rebased onto current trunk after the verdict, patch-id unchanged.
- [ ] The owner squash-merges its own PR into main.

## Expand architecture boundary checks to cover all companion domain modules (PR-04)

**Depends on.** PR-01.

**Files.**

- [ ] Edit `scripts/check-architecture.sh`.
- [ ] Edit `Makefile`.

**Build.**

- [ ] Update `scripts/check-architecture.sh` to dynamically find and inspect all core domain files in `companion/src/` rather than hardcoding two files.
- [ ] Exclude platform adapter directories `companion/src/os/` from domain isolation checks.
- [ ] Add explicit checks forbidding direct `URLSession` usage in `Glimmer/Stream/`.

**You see.**

- [ ] `bash scripts/check-architecture.sh` validates that all current and future companion domain files avoid direct OS and network calls.
- [ ] Any accidental import of network or OS adapters in companion domain logic immediately fails the architecture check.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Run `bash scripts/check-architecture.sh`.
- [ ] Confirm the script reports that all companion domain files and Swift streaming bounds passed.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Ten lanes on `grok-4.7-xhigh-fast` at the PR head, per the boot recipe.

- [ ] Lane 1. Regression lane against trunk. Run `scripts/check-architecture.sh` at trunk and head. Trunk checks only two hardcoded files. Save `/tmp/swarm-pr-04/worker-1/arch-diff.png`. Pass when head dynamically inspects all root companion files.
- [ ] Lane 2. Verify exclusion of adapter directories. Check that `companion/src/os/` files are permitted to use OS APIs. Save `/tmp/swarm-pr-04/worker-2/adapter-exempt.png`. Pass when adapter files do not trigger false positives.
- [ ] Lane 3. Verify violation trap for companion host. Add temporary `std::fs` call to `companion/src/host.rs` and run script. Save `/tmp/swarm-pr-04/worker-3/host-trap.png`. Pass when script catches violation and exits 1.
- [ ] Lane 4. Verify violation trap for new domain module. Add temporary test file `companion/src/test_core.rs` with forbidden import and run script. Save `/tmp/swarm-pr-04/worker-4/module-trap.png`. Pass when script catches violation and exits 1.
- [ ] Lane 5. Verify `URLSession` boundary check in Swift. Check that `grep -rn 'URLSession' Glimmer/Stream/` allows only comments. Save `/tmp/swarm-pr-04/worker-5/urlsession-check.png`. Pass when zero executable URLSession calls exist.
- [ ] Lane 6. Verify `NativeBackend` instantiation constraint. Check that only `Glimmer/AppModel+Streaming.swift` constructs NativeBackend. Save `/tmp/swarm-pr-04/worker-6/native-backend.png`. Pass when exactly one constructor match is confirmed.
- [ ] Lane 7. Verify script execution under bash strict mode. Inspect `set -euo pipefail` at script start. Save `/tmp/swarm-pr-04/worker-7/bash-flags.png`. Pass when script uses strict error handling.
- [ ] Lane 8. Verify compatibility on macOS and Linux runners. Run script with standard BSD and GNU grep options. Save `/tmp/swarm-pr-04/worker-8/grep-compat.png`. Pass when script produces identical output on both platforms.
- [ ] Lane 9. Verify integration in `make verify`. Run `make verify` check targets. Save `/tmp/swarm-pr-04/worker-9/make-verify.png`. Pass when architecture checks execute during verify.
- [ ] Lane 10. Verify script cleans up temporary checks cleanly. Run `git status -s`. Save `/tmp/swarm-pr-04/worker-10/clean-tree.png`. Pass when working tree has zero untracked artifacts.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Metric. Execution latency of `bash scripts/check-architecture.sh`.
- [ ] Probe. Run `time bash scripts/check-architecture.sh` five times and record real elapsed time.
- [ ] Baseline. Trunk execution time of 0.12 seconds.
- [ ] Rule. Head execution time must remain under 0.35 seconds.

**Review gate.** None. PR-04 is not review-gated.

**Merge.**

- [ ] Root's clean verdict at the exact head SHA.
- [ ] Bugbot triage done.
- [ ] Rebased onto current trunk after the verdict, patch-id unchanged.
- [ ] The owner squash-merges its own PR into main.

## Create focused unit test runner and optimize pre-push hook (PR-05)

**Depends on.** PR-01.

**Files.**

- [ ] Create `scripts/test-unit.sh`.
- [ ] Edit `.pre-commit-config.yaml`.
- [ ] Edit `Makefile`.

**Build.**

- [ ] Create `scripts/test-unit.sh` accepting test filter arguments and mapping changed Swift files to corresponding tests.
- [ ] Add `test-unit` target in `Makefile` allowing fast execution of specific test classes.
- [ ] Update `.pre-commit-config.yaml` pre-push hook to run fast focused unit tests on staged files rather than compiling the full suite.

**You see.**

- [ ] Developers and agents can run `bash scripts/test-unit.sh SdpCodec` to execute targeted tests in under 8 seconds.
- [ ] Pre-push hook catches test regressions on modified modules without waiting 90 seconds for all 1,244 tests.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Run `bash scripts/test-unit.sh SdpCodecTests`.
- [ ] Confirm specific tests execute and report pass status.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Ten lanes on `grok-4.7-xhigh-fast` at the PR head, per the boot recipe.

- [ ] Lane 1. Regression lane against trunk. Run test on trunk and head. Trunk has no selective test runner. Save `/tmp/swarm-pr-05/worker-1/runner-diff.png`. Pass when head runs filtered test via test-unit.sh.
- [ ] Lane 2. Verify filtering by test suite name. Run `bash scripts/test-unit.sh PairingCryptoTests`. Save `/tmp/swarm-pr-05/worker-2/crypto-filter.png`. Pass when only PairingCryptoTests execute.
- [ ] Lane 3. Verify filtering by multiple test targets. Run `bash scripts/test-unit.sh SdpCodecTests OpusDecoderTests`. Save `/tmp/swarm-pr-05/worker-3/multi-filter.png`. Pass when both test targets execute.
- [ ] Lane 4. Verify exit code propagation on test failure. Run a test with an intentional failure flag and verify script returns non-zero. Save `/tmp/swarm-pr-05/worker-4/fail-exit.png`. Pass when script exits with xcodebuild exit code.
- [ ] Lane 5. Verify BuildInfo generation in test script. Inspect that `scripts/generate-build-info.sh` is invoked. Save `/tmp/swarm-pr-05/worker-5/buildinfo.png`. Pass when build info is up to date before testing.
- [ ] Lane 6. Verify pre-push hook execution. Run `pre-commit run make-test --hook-stage pre-push`. Save `/tmp/swarm-pr-05/worker-6/prepush-hook.png`. Pass when hook executes and validates staged targets.
- [ ] Lane 7. Verify unregistration of debug app bundle. Check that `lsregister -u` runs after test completion to keep LaunchServices clean. Save `/tmp/swarm-pr-05/worker-7/lsregister.png`. Pass when debug bundle is unregistered after tests.
- [ ] Lane 8. Verify clean handling of empty filter. Run `bash scripts/test-unit.sh` without arguments. Save `/tmp/swarm-pr-05/worker-8/help-output.png`. Pass when script displays usage instructions or defaults safely.
- [ ] Lane 9. Verify compatibility with derivedData caching. Check that test runner reuses existing derived data from `build.noindex`. Save `/tmp/swarm-pr-05/worker-9/cache-reuse.png`. Pass when second run avoids full recompilation.
- [ ] Lane 10. Verify clean working tree after tests. Run `git status -s`. Save `/tmp/swarm-pr-05/worker-10/clean-tree.png`. Pass when working tree has zero untracked artifacts.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Metric. Execution latency of running a single test suite (`SdpCodecTests`) via `scripts/test-unit.sh`.
- [ ] Probe. Run `time bash scripts/test-unit.sh SdpCodecTests` three times on a warm build.
- [ ] Baseline. Trunk `make test` execution time of 78.5 seconds for the full suite.
- [ ] Rule. Head filtered test execution time must remain under 12.0 seconds.

**Review gate.** None. PR-05 is not review-gated.

**Merge.**

- [ ] Root's clean verdict at the exact head SHA.
- [ ] Bugbot triage done.
- [ ] Rebased onto current trunk after the verdict, patch-id unchanged.
- [ ] The owner squash-merges its own PR into main.

## Author agent navigation map and contributor guidelines (PR-06)

**Depends on.** PR-01.

**Files.**

- [ ] Create `AGENTS.md`.
- [ ] Edit `docs/CONTRIBUTING.md`.

**Build.**

- [ ] Create a lean `AGENTS.md` specifying architecture boundaries, tool commands, fast test workflows, and trust zones.
- [ ] Update `docs/CONTRIBUTING.md` with instructions for running `pre-commit`, selective tests, and companion formatting.

**You see.**

- [ ] AI agents working in this repository immediately read `AGENTS.md` and know exact commands and boundaries without token-heavy tree explorations.
- [ ] Human contributors have a clear guide on pre-commit installation and PR expectations.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Run `markdownlint AGENTS.md docs/CONTRIBUTING.md`.
- [ ] Run `prettier --check AGENTS.md docs/CONTRIBUTING.md`.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Ten lanes on `grok-4.7-xhigh-fast` at the PR head, per the boot recipe.

- [ ] Lane 1. Regression lane against trunk. Inspect root directory for AGENTS.md on trunk and head. Trunk lacks AGENTS.md. Save `/tmp/swarm-pr-06/worker-1/agents-diff.png`. Pass when head contains AGENTS.md.
- [ ] Lane 2. Verify line count constraint. Run `wc -l AGENTS.md`. Save `/tmp/swarm-pr-06/worker-2/line-count.png`. Pass when AGENTS.md is under 120 lines to preserve agent context.
- [ ] Lane 3. Verify tool commands section. Check that `make app`, `make test`, and `scripts/test-unit.sh` are documented. Save `/tmp/swarm-pr-06/worker-3/commands-doc.png`. Pass when exact shell commands are present.
- [ ] Lane 4. Verify trust boundaries section. Check that network inputs and IPC surfaces are documented as untrusted. Save `/tmp/swarm-pr-06/worker-4/trust-doc.png`. Pass when untrusted boundaries are explicitly named.
- [ ] Lane 5. Verify companion boundaries documentation. Check that isolation between companion core and OS adapters is documented. Save `/tmp/swarm-pr-06/worker-5/companion-doc.png`. Pass when companion architecture rules are cited.
- [ ] Lane 6. Verify pre-commit setup instructions. Inspect `docs/CONTRIBUTING.md` for `pre-commit install` steps. Save `/tmp/swarm-pr-06/worker-6/precommit-doc.png`. Pass when pre-commit instructions are verified.
- [ ] Lane 7. Verify Rust companion contribution guide. Inspect `docs/CONTRIBUTING.md` for `cargo fmt` and `cargo clippy` rules. Save `/tmp/swarm-pr-06/worker-7/rust-contrib.png`. Pass when Rust contribution rules are clear.
- [ ] Lane 8. Verify markdown formatting across both files. Run `markdownlint AGENTS.md docs/CONTRIBUTING.md`. Save `/tmp/swarm-pr-06/worker-8/markdownlint.png`. Pass when markdownlint reports 0 errors.
- [ ] Lane 9. Verify absence of AI tells in prose. Check that unslop rules are respected. Save `/tmp/swarm-pr-06/worker-9/unslop-check.png`. Pass when prose is concise and free of long dashes or filler.
- [ ] Lane 10. Verify clean working tree after docs update. Run `git status -s`. Save `/tmp/swarm-pr-06/worker-10/clean-tree.png`. Pass when working tree has zero untracked artifacts.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Metric. Token footprint of `AGENTS.md` when ingested by an agent context.
- [ ] Probe. Measure character and word count of `AGENTS.md`.
- [ ] Baseline. Trunk has no AGENTS.md file (0 tokens, but agents burn ~40,000 tokens exploring the tree).
- [ ] Rule. `AGENTS.md` size must remain under 1,200 tokens (under 6,000 characters).

**Review gate.** None. PR-06 is not review-gated.

**Merge.**

- [ ] Root's clean verdict at the exact head SHA.
- [ ] Bugbot triage done.
- [ ] Rebased onto current trunk after the verdict, patch-id unchanged.
- [ ] The owner squash-merges its own PR into main.

## Close the program

- [ ] Every box above is checked with its evidence.
- [ ] Reply to the operator with the report the execution playbook names.

## Appendix A. Prototype evidence

During exploration, the following prototypes settled open technical questions:
1. Pre-commit hook execution prototype. Running `pre-commit run --all-files` revealed that exactly 16 files drifted from newline and Prettier formatting. Re-running the tool confirmed full idempotence.
2. Swift compiler flag prototype. Inspecting `build.noindex/Logs/Build` confirmed that `SWIFT_STRICT_CONCURRENCY = complete` is already active and that the sole build warning stemmed from AppIntents framework metadata extraction.
3. Architecture check prototype. Inspecting `scripts/check-architecture.sh` demonstrated that domain checks were hardcoded to `host.rs` and `ports.rs`. A dynamic loop over `companion/src/*.rs` successfully isolates domain logic without flagging OS adapters.
4. Selective test execution prototype. Running `xcodebuild test -only-testing:GlimmerTests/SdpCodecTests` completed in 9.2 seconds on a warm derived data cache, compared to 78.5 seconds for the full 1,244 test suite.

## Appendix B. Alternatives rejected

1. Overwriting or refactoring `companion/src/outputs.rs` in this plan. Rejected because another active agent session owns the monitor selection and output discovery feature. Touching these files would cause merge collisions and invalidate that agent's in-flight work.
2. Replacing SwiftLint with Apple swift-format. Rejected because swift-format reflows trailing-aligned function signatures, creating thousands of churn lines without improving type safety or bug prevention.
3. Running all 1,244 unit tests on pre-commit. Rejected because waiting 60 to 90 seconds on every commit introduces excessive friction. The plan runs fast linters and formatters on pre-commit, runs focused tests on pre-push, and runs the full suite in GitHub Actions CI.
4. Custom Python or Node architecture validation framework. Rejected under the Laziness Protocol (`principle-laziness-protocol`). The lightweight Bash script `scripts/check-architecture.sh` runs in 0.12 seconds and requires zero additional runtime dependencies.

## Appendix C. Risks

1. Pre-commit installation dependency. Contributor environments without Python or pre-commit could bypass local checks. Mitigated by enforcing `pre-commit run --all-files` in GitHub Actions CI (PR-02).
2. Xcode derivedData invalidation. Clean builds take longer when derived data is deleted. Mitigated by keeping `build.noindex` stable and caching build directories in CI.
3. Strict warning false positives on Xcode toolchain updates. Future Xcode toolchains may introduce new warnings. Mitigated by keeping SwiftLint warnings distinct from compiler fatal errors and scoping compiler warning gates to documented targets.

## Appendix D. Links and reading list

1. Execution playbook at [playbooks/autopilot-full.md](file:///Users/jagercooper/.gemini/config/skills/poteto-mode/playbooks/autopilot-full.md).
2. Architecture guide at [docs/ARCHITECTURE.md](file:///Users/jagercooper/GitHub/event-horizon/docs/ARCHITECTURE.md).
3. Security threat model at [docs/SECURITY.md](file:///Users/jagercooper/GitHub/event-horizon/docs/SECURITY.md).
4. Poteto mode workflow at [FULL_WORKFLOW.md](file:///Users/jagercooper/.gemini/config/skills/poteto-mode/FULL_WORKFLOW.md).
5. Unslop guide at [unslop/SKILL.md](file:///Users/jagercooper/.gemini/config/skills/unslop/SKILL.md).
6. Swarm verification at [swarm/SKILL.md](file:///Users/jagercooper/.gemini/config/skills/swarm/SKILL.md).

<!-- prettier-ignore-end -->
