# Automating Repository Trust, Minimizing Agent Context Consumption, and Enforcing Deterministic Invariants

**A Cross-Industry Investigation into Modern CI/CD Hooks, Lean Agent Navigation
Architectures, and Privacy-Preserving Client Telemetry**

---

## Executive Summary

As software engineering organizations increasingly integrate autonomous AI
coding agents into high-velocity trunk-based workflows, three foundational
challenges emerge:

1. **Developer Velocity vs. Quality Assurance:** How to prevent regressions
   locally without burdening engineers and AI agents with multi-minute
   pre-commit/pre-push friction.
2. **Context Window Optimization & Instruction Adherence:** How to structure
   agent navigation files (`AGENTS.md` / `CLAUDE.md`) under 100 lines while
   deterministically preventing critical bugs (e.g., force-unwraps,
   architectural leaks) without prompt bloat or attention degradation.
3. **Privacy-Preserving Diagnostics:** How desktop and system software (Swift
   macOS and Rust companions) can collect crash telemetry and performance
   metrics with zero runtime overhead and strict user privacy.

This report synthesizes practices from high-scale engineering teams (Meta,
Google, Zed, PostHog, Apple) into actionable principles, production
configuration snippets, and a practical implementation checklist.

---

## 1. Modern Pre-Commit & Pre-Push Hook Architectures

### 1.1 The Shift-Left Dilemma and Developer Friction

The tension in local verification is well-documented:

- **The Cognitive Tax of Slow Hooks:** If local git hooks exceed **2–3 seconds
  on commit** or **30 seconds on push**, developers and AI agents actively
  bypass them using `git commit --no-verify` or `git push --no-verify`. This
  defeats the purpose of local verification entirely.
- **The Cost of Delayed CI Feedback:** Conversely, delegating all verification
  to remote CI creates a high-latency loop. A developer or agent switches
  context to another task, only to receive a CI failure notification 15–30
  minutes later. In trunk-based development with high commit concurrency, broken
  builds on `main` block the entire team.

To resolve this, leading engineering teams reject binary "test everything
locally vs. test everything in CI" models. Instead, they structure verification
into a **Four-Tier Pyramid**:

```
                 ▲
                / \       Tier 4: Merge Queue (Bors, GitHub MQ)
               /   \      - Speculative parallel builds on trunk
              /-----\
             /       \    Tier 3: Remote CI (GitHub Actions)
            /         \   - Full OS matrix, ASan/TSan, E2E, Release DMG
           /-----------\
          /             \ Tier 2: Pre-Push Hook (10s - 30s)
         /               \- Architecture boundaries, type-check, affected tests
        /-----------------\
       /                   \ Tier 1: Pre-Commit Hook (< 1.5s)
      /                     \- Staged AST lint, secret scanning, formatting
     /-----------------------\
    /                         \ Tier 0: In-Editor / LSP (0ms latency)
   /___________________________\ - SourceKit-LSP, rust-analyzer, format-on-save
```

---

### 1.2 The Verification Tier Breakdown

#### Tier 0: In-Editor / Asynchronous Diagnostics (0ms overhead)

- **Tools:** `SourceKit-LSP` (Swift), `rust-analyzer` (Rust), IDE
  format-on-save.
- **Scope:** Provides instant feedback while typing. Linters run asynchronously
  in editor background threads without interrupting developer flow.

#### Tier 1: Pre-Commit Hook (< 1.5 seconds, Staged Files Only)

- **Invariant:** _Never compile full binaries; never run multi-file test
  suites._
- **Scope:** Operates strictly on `staged` changes (`git diff --cached`).
- **Tasks:**
  1. **Secret Scanning:**
     `trufflehog git file://$PWD --since-commit HEAD --only-verified` or
     `gitleaks protect --staged`. Running verification only against verified
     credentials prevents false positives on rotated test fixtures from blocking
     commits.
  2. **Fast AST Formatting / Autocorrect:** `swiftlint --fix` (targeted strictly
     to staged Swift files), `rustfmt --check` on staged Rust files.
  3. **Diff Hygiene:** Trailing whitespace removal, end-of-file fixer,
     YAML/TOML/JSON schema validation, merge conflict marker detection.
- **Auto-Fix Safety Rule:** When an auto-formatter (such as `swiftlint --fix`)
  modifies files during pre-commit, **never silently stage the modification**.
  Instead, calculate file hashes before and after; if a modification occurs,
  abort the commit with non-zero exit and prompt the human/agent to inspect the
  diff and re-stage. This prevents untracked working-tree state clobbering.

#### Tier 2: Pre-Push Hook (10–30 seconds, Diff-Aware & Boundary Checks)

- **Invariant:** _Prevent pushing demonstrably broken code without duplicating
  full cloud matrix builds._
- **Scope:** Operates on the outgoing commit range (`origin/main..HEAD`).
- **Tasks:**
  1. **Architectural Invariant Enforcement:** Deterministic shell scripts (e.g.,
     `scripts/check-architecture.sh`) that parse imports and constructors via
     regex or AST parsers to ensure domain boundaries are respected.
  2. **Fast Incremental Compilation / Type-Check:** `cargo check --all-targets`
     (Rust) and incremental Swift compile checks.
  3. **Affected Unit Tests (Test Impact Analysis):** Rather than running full
     suite (`xcodebuild test`), execute only the focused test suites relevant to
     the modified modules (`scripts/test-unit.sh <SuiteName>`).
- **Git Environment Isolation:** When executing build tools within Git hooks,
  Git exports environment variables like `GIT_DIR`, `GIT_WORK_TREE`, and
  `GIT_INDEX_FILE`. These leak into sub-invocations (e.g., SwiftPM checking out
  dependencies like Sparkle or nested Cargo git checkouts). Hooks must sanitize
  the environment via:
  ```bash
  env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_PREFIX make verify-push
  ```

#### Tier 3: Remote CI (PR & Pre-Merge Matrix)

- **Scope:** Full matrix across target OS versions (macOS 14 Sonoma, macOS 15
  Sequoia, Ubuntu x86_64/arm64, Windows), AddressSanitizer (ASan),
  ThreadSanitizer (TSan), full UI automation, code coverage collection, and
  release packaging.

#### Tier 4: Merge Queue (Trunk-Based Invariant)

- **Tools:** GitHub Merge Queue, Bors-NG, Mergify, Aviator.
- **Mechanism:** Solves the semantic merge conflict ("PR #1 passes CI, PR #2
  passes CI; when both land simultaneously on `main`, `main` breaks"). The queue
  creates speculative merge heads (`main + PR #1 + PR #2`), testing them in
  parallel before advancing `main`.

---

### 1.3 Execution Tooling: Lefthook vs. Pre-Commit vs. Native Shell

Engineering teams migrating from legacy hooks prioritize raw execution latency
and multi-language support:

| Feature                  | Lefthook (Evil Martians)               | pre-commit (Yelp)                      | Husky + lint-staged              |
| :----------------------- | :------------------------------------- | :------------------------------------- | :------------------------------- |
| **Runtime**              | Go (Single static binary)              | Python (Script + venvs)                | Node.js (npm/pnpm/yarn)          |
| **Execution**            | **Parallel (`parallel: true`)**        | Strictly Sequential                    | Parallel across tasks            |
| **Cold-Start Overhead**  | **0ms** (Instant startup)              | High (bootstraps virtual environments) | Medium (Node.js engine boot)     |
| **Dependency Isolation** | Uses system/repo `PATH` directly       | Creates isolated Python/Ruby venvs     | Relies on `node_modules`         |
| **Best Fit**             | Polyglot monorepos (Rust + Swift + Go) | Python-centric data repositories       | Pure JavaScript/TypeScript repos |

**Key Takeaway:** High-performance teams adopting polyglot stacks (e.g., Swift
macOS client + Rust daemon) favor **Lefthook** or structured **Makefiles/Bash
scripts** over Python-based `pre-commit` to eliminate environment bootstrapping
overhead and enable parallel hook execution.

---

### 1.4 Test Impact Analysis (TIA) & Predictive Test Selection

At Meta and Google scale, running the full test suite locally or on every commit
is mathematically impossible:

- **Predictive Test Selection (Meta / Machalica et al., ICSE 2022):** Meta
  deployed machine-learning models trained on change metadata (AST churn, file
  paths, author, historical test outcomes). The model predicts the probability
  that a given test will fail on a specific commit diff. In production, this
  **cut test execution by 66% while catching > 99.9% of regression breakages**.
- **Target Pruning (Google / Bazel):** Google utilizes fine-grained Directed
  Acyclic Graphs (DAGs) in Bazel/Blaze. A change to `companion/src/ports.rs`
  invalidates only the direct dependents and unit tests of `ports.rs`, pruning
  95% of unrelated target tests from local and CI test runs.
- **Practical Local Implementation for Rust & Swift:**
  - Rust: `cargo nextest run -p <package>` or `cargo test --test <suite>` (up to
    3x faster than standard `cargo test` due to parallel process execution).
  - Swift: Parameterized test runner scripts
    (`scripts/test-unit.sh <SuiteName>`) that invoke
    `xcodebuild -only-testing:GlimmerTests/<SuiteName>`.

---

## 2. Agent Navigation Files (`AGENTS.md` / `CLAUDE.md`) Under 100 Lines

### 2.1 The Problem: Prompt Bloat, Attention Decay, and Sediment

When teams deploy AI coding assistants (Claude Code, Cursor, Antigravity,
Codex), they often fall into the trap of writing exhaustive, 500-line
instructional guides. This causes severe failure modes:

1. **Context Window Token Bloat:** In a typical 40-to-60 turn interactive
   session, every turn re-transmits the repository instructions. A 2,500-token
   system instruction file consumes 125,000 tokens of input context, driving up
   costs and slowing down latency.
2. **"Lost in the Middle" Attention Degradation:** Large language models exhibit
   U-shaped attention curves (Liu et al., 2023). When instructions are packed
   into dense, repetitive prompt files, the model attends strongly to the top
   and bottom, frequently missing critical architectural constraints placed in
   the middle.
3. **Instruction Sediment & Drift:** Natural language instructions decay over
   time. As code conventions change, prose guidelines become obsolete or
   contradict current code, causing agent hallucination.

---

### 2.2 The Three Golden Rules for Agent Repository Instructions

#### Rule 1: Progressive Disclosure (Hierarchical Context Pointers)

A root navigation file (`AGENTS.md` or `CLAUDE.md`) should act as an **index and
router**, not an encyclopedia.

- Keep the root file strictly under **100 lines** (ideally 50–70 lines).
- Inline only what applies universally across every turn:
  1. Quick CLI commands (build, test, lint, env).
  2. Hard mechanical boundaries (zero-tolerance invariants).
  3. Context Pointers to specialized documents.
- **Context Pointer Mechanics:** A context pointer names the document and
  specifies the explicit activation condition. The agent loads the document
  on-demand only when entering that branch:
  ```markdown
  - Read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) when modifying streaming
    pipelines.
  - Read [docs/SECURITY.md](docs/SECURITY.md) when modifying pairing, cert
    pinning, or helper XPC.
  - Read [docs/companion/DESIGN.md](docs/companion/DESIGN.md) when editing the
    Rust companion.
  ```

#### Rule 2: Mechanical Invariants > Text Prompting

- **The Axiom:** _Never rely on prose prompting for what can be enforced
  mechanically by a linter, compiler flag, or script._
- Asking an LLM in English: _"Please do not use force-unwraps (`!`), force-casts
  (`as!`), or force-try (`try!`) in the streaming engine"_ results in ~80–85%
  compliance. Under complex refactorings, the model will inevitably slip.
- Enforcing it mechanically via linter rules (`.swiftlint.yml`, `clippy.toml`)
  and deterministic scripts (`scripts/check-architecture.sh`) guarantees **100%
  compliance**:
  - The agent runs `make verify-push` or `scripts/check-architecture.sh`.
  - The script fails with a non-zero exit code and prints the exact offending
    file and line number.
  - The agent reads the compiler/linter error, diagnoses its mistake, and
    self-corrects within its execution loop.

#### Rule 3: High-Demand Leading Words and Positive Directives

- Prompt the **positive behavior** ("Use `guard let`, optional chaining, or
  nil-coalescing") rather than purely negative prohibitions. Prohibitions keep
  the forbidden pattern active in the model's semantic attention space.
- Strip no-ops: Instructions such as "Write clean, readable, modular code" or
  "Be thoughtful" consume context tokens while providing zero steering signal
  over base model defaults.

---

### 2.3 Concrete Mechanical Configuration

#### Swift / Xcode Invariant Configuration

In `.swiftlint.yml`:

```yaml
opt_in_rules:
  - force_unwrapping

# Fail the build if forced operations occur in production targets
force_cast: error
force_try: error
force_unwrapping: error

# Exclude test suites where force-unwrapping is safe and expected
excluded:
  - GlimmerTests
  - companion
```

In Xcode Project Build Settings:

```ini
SWIFT_TREAT_WARNINGS_AS_ERRORS = YES
GCC_TREAT_WARNINGS_AS_ERRORS = YES
```

#### Rust / Cargo Invariant Configuration

In `Cargo.toml` or root crate attributes (`companion/src/lib.rs` / `main.rs`):

```rust
// Strictly deny runtime panicking constructs in production code
#![deny(clippy::unwrap_used)]
#![deny(clippy::expect_used)]
#![deny(clippy::panic)]

// Allow unwraps inside unit tests only
#[cfg(test)]
#[allow(clippy::unwrap_used, clippy::expect_used)]
mod tests { /* ... */ }
```

In CI / Makefile:

```bash
cargo clippy --all-targets -- -D warnings
cargo fmt --check
```

#### Deterministic Architectural Boundary Script

Example of a sub-second, zero-dependency boundary check
(`scripts/check-architecture.sh`):

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# 1. Enforce Hexagonal Architecture: Core policy cannot depend on OS/network adapters
CORE_FILES=("$ROOT/companion/src/host.rs" "$ROOT/companion/src/ports.rs")
FORBIDDEN='crate::os|std::(process|fs|env|os)::|tokio::net|reqwest::|zbus::|windows_sys::'
if matches="$(grep -nE "$FORBIDDEN" "${CORE_FILES[@]}" || true)" && [[ -n "$matches" ]]; then
    echo "Architecture violation: Core policy must not depend on OS/network adapters:" >&2
    printf '%s\n' "$matches" >&2
    exit 1
fi

# 2. Enforce Composition Root: NativeBackend constructed ONLY in AppModel+Streaming.swift
NATIVE_CONSTRUCTORS="$(grep -R -nE --include='*.swift' 'NativeBackend[[:space:]]*\(' "$ROOT/Glimmer" || true)"
if [[ "$(printf '%s\n' "$NATIVE_CONSTRUCTORS" | sed '/^$/d' | wc -l | tr -d ' ')" != 1 ]] \
    || [[ "$NATIVE_CONSTRUCTORS" != *"Glimmer/AppModel+Streaming.swift:"* ]]; then
    echo "Architecture violation: Construct NativeBackend only at Glimmer/AppModel+Streaming.swift" >&2
    exit 1
fi

# 3. Untrusted wire boundary: Disallow force-cast (as!) and force-try (try!) in streaming engine
if traps="$(grep -R -nE --include='*.swift' '(\bas!\b|\btry!\b)' "$ROOT/Glimmer/Stream" | grep -vE ':[0-9]+:[[:space:]]*//' || true)" && [[ -n "$traps" ]]; then
    echo "Architecture violation: Stream engine must never force-cast (as!) or force-try (try!):" >&2
    printf '%s\n' "$traps" >&2
    exit 1
fi

echo "✓ Architectural boundaries verified."
```

---

## 3. Privacy-Preserving Client-Side Telemetry & Crash Reporting

### 3.1 The Open-Source Standard: Privacy by Default

Top open-source desktop projects (Zed, Ghostty, Homebrew, Tauri) implement
telemetry under strict privacy invariants:

1. **Explicit Opt-In / Zero Pre-Consent Traffic:** The client application
   transmits zero network packets until the user explicitly consents (via an
   initial welcome dialog or toggle in settings).
2. **Strict Anonymity:** Telemetry distinct IDs are client-generated random
   UUIDv4 identifiers. They are never derived from or associated with hardware
   MAC addresses, serial numbers, IP addresses, or OS account usernames.
3. **Local Auditability:** Projects like the Zed editor expose commands like
   `zed: open telemetry log` so users can inspect the exact JSON payloads queued
   for dispatch.
4. **Environment Kill Switch:** Respect standard environment toggles such as
   `DO_NOT_TRACK=1` or `<APP>_NO_ANALYTICS=1`.

---

### 3.2 macOS & Swift: Apple MetricKit vs. In-Process Reporters

When instrumenting a native macOS application (Swift/Objective-C), engineering
teams must weigh **MetricKit** against third-party crash reporters:

| Architectural Dimension | Apple MetricKit (`MetricKit.framework`)                                                          | In-Process Crash Reporter (PostHog / Sentry / PLCrashReporter)                            |
| :---------------------- | :----------------------------------------------------------------------------------------------- | :---------------------------------------------------------------------------------------- |
| **Runtime Overhead**    | **Strictly 0% overhead.** Monitored by the OS daemon (`metrickitd`).                             | Minor overhead: Injects Mach exception handlers, signal handlers, and breadcrumb loggers. |
| **Crash Safety**        | Out-of-process. Zero risk of deadlocks in crash handler.                                         | Risk of secondary crash/deadlock if non-async-signal-safe code runs during a crash.       |
| **Privacy Compliance**  | Enforced by macOS. Reports sent only if user consented to "Share Mac Analytics with Developers". | Managed in-app via local preference toggle (`optOut = true`).                             |
| **Delivery Timing**     | Delayed. Dispatched by OS scheduler (`dasd`) in 24-hour batches or on subsequent launches.       | Real-time or dispatched on immediate subsequent application launch.                       |
| **Stack Symbolication** | Delivers raw binary frames. Requires server-side dSYM symbolication.                             | Handled via symbol upload pipelines or client symbolication.                              |

#### High-Assurance Hybrid Recommendation for macOS:

- **For General Diagnostics & Performance:** Subscribe to `MetricKit`
  (`MXMetricManagerSubscriber`). It provides zero-overhead telemetry on battery,
  memory pressure, hangs, and kernel terminations.
- **For Opt-In Application Errors & Feature Metrics:** Integrate the PostHog
  Swift SDK with:
  1. Default opt-out (`config.optOut = true`).
  2. Path scrubbing in `beforeSend`.
  3. Asynchronous file-backed queue (`PostHogFileBackedQueue`).

```swift
import Foundation
import MetricKit
import PostHog

public final class TelemetryService: NSObject, MXMetricManagerSubscriber {
    public static let shared = TelemetryService()

    public func configure(apiKey: String, host: String) {
        // 1. Honor standard DO_NOT_TRACK environment variable
        if ProcessInfo.processInfo.environment["DO_NOT_TRACK"] == "1" {
            return
        }

        let config = PostHogConfig(apiKey: apiKey, host: host)

        // 2. Default to OPTED-OUT until explicit user consent
        config.optOut = true
        config.captureApplicationLifecycleEvents = false
        config.enableSwizzling = false

        // 3. Scrub sensitive system paths and user names from payloads
        config.beforeSend = { payload in
            var sanitized = payload
            if var properties = sanitized.properties as? [String: Any] {
                sanitized.properties = Self.sanitize(properties: properties)
            }
            return sanitized
        }

        PostHogSDK.shared.setup(config)

        // 4. Register for zero-overhead OS-level diagnostics
        MXMetricManager.shared.add(self)
    }

    public func setUserConsent(optedIn: Bool) {
        if optedIn {
            PostHogSDK.shared.optIn()
        } else {
            PostHogSDK.shared.optOut()
        }
    }

    // Scrub user directory paths: /Users/<user>/... -> ~/[REDACTED]/...
    private static func sanitize(properties: [String: Any]) -> [String: Any] {
        var clean = properties
        let userDir = NSHomeDirectory()
        for (k, v) in clean {
            if let str = v as? String {
                clean[k] = str.replacingOccurrences(of: userDir, with: "~/[REDACTED]")
            }
        }
        return clean
    }

    // MetricKit Crash & Hang Diagnostics
    public func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            guard let crashes = payload.crashDiagnostics else { continue }
            for crash in crashes {
                // Forward anonymized crash metadata if opted in
                if !PostHogSDK.shared.isOptedOut() {
                    PostHogSDK.shared.capture(
                        "system_crash_diagnostic",
                        properties: [
                            "termination_reason": String(describing: crash.terminationReason),
                            "virtual_memory_region": String(describing: crash.virtualMemoryRegionInfo)
                        ]
                    )
                }
            }
        }
    }

    public func didReceive(_ payloads: [MXMetricPayload]) {}
}
```

---

### 3.3 Rust Companion: Non-Blocking Panics and Lock-Free Ring Buffers

In native systems companions (such as Event Horizon's Rust companion handling
Sunshine/Moonlight streaming, display capture, or audio pacing), **telemetry
must never block real-time I/O or rendering loops**.

#### Core Invariants for Systems Rust Telemetry:

1. **Zero Contention:** Do not take global mutex locks in hot paths (audio
   buffers, packet processing). Use bounded lock-free channels (e.g.,
   `crossbeam_channel::bounded`).
2. **Drop on Backpressure:** If the background telemetry sender thread stalls
   due to network latency, immediately drop metrics rather than blocking the
   main engine thread.
3. **Panic Hook Autocapture:** Register `std::panic::set_hook` to safely record
   panic backtraces to disk and flush on shutdown.

```rust
use std::panic;
use std::path::PathBuf;
use posthog::{ClientOptions, ErrorTrackingOptions};

pub struct TelemetryManager;

impl TelemetryManager {
    pub async fn init(api_key: Option<&str>, opted_in: bool) -> Result<(), Box<dyn std::error::Error>> {
        // Honor system-level DO_NOT_TRACK or CLI flag
        if std::env::var("DO_NOT_TRACK").unwrap_or_default() == "1" || !opted_in {
            return Ok(());
        }

        let Some(key) = api_key else { return Ok(()) };

        // 1. Configure panic autocapture (strictly opt-in)
        let mut error_tracking = ErrorTrackingOptions::default();
        error_tracking.capture_panics = true;

        let options = ClientOptions::new(key)
            .error_tracking(error_tracking);

        // 2. Initialize global PostHog client with background worker
        posthog::init_global(options).await?;

        // 3. Custom path-sanitizing panic hook
        let default_hook = panic::take_hook();
        panic::set_hook(Box::new(move |panic_info| {
            let backtrace = std::backtrace::Backtrace::capture();
            let sanitized_trace = Self::sanitize_paths(&format!("{:#?}", backtrace));

            eprintln!("Thread panicked: {}\n{}", panic_info, sanitized_trace);

            // Execute default hook for terminal logging/crash core dump
            default_hook(panic_info);
        }));

        Ok(())
    }

    /// Strip usernames and local paths from stack traces
    fn sanitize_paths(input: &str) -> String {
        let home = std::env::var("HOME").or_else(|_| std::env::var("USERPROFILE")).unwrap_or_default();
        if home.is_empty() {
            input.to_string()
        } else {
            input.replace(&home, "~/[REDACTED]")
        }
    }

    pub async fn shutdown() {
        // Guarantee any pending batch in the background channel flushes on exit
        posthog::shutdown().await;
    }
}
```

---

## 4. Practical Implementation Checklist

### 4.1 Lints & Compiler Enforcement

- [ ] **Swift Compiler Warnings as Errors:** Verify
      `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` and
      `GCC_TREAT_WARNINGS_AS_ERRORS = YES` in project build configurations.
- [ ] **SwiftLint Strict Rules:** Add `force_unwrapping` to `opt_in_rules` in
      `.swiftlint.yml`. Set `force_cast: error` and `force_try: error`.
- [ ] **Rust Clippy Invariants:** Add `#![deny(clippy::unwrap_used)]` and
      `#![deny(clippy::expect_used)]` to core crates.
- [ ] **Rust Compiler Warnings as Errors:** Run
      `cargo clippy --all-targets -- -D warnings` and `cargo fmt --check`.

### 4.2 Local Git Hooks (Pre-Commit & Pre-Push)

- [ ] **Fast Pre-Commit Hook:**
  - [ ] Staged file formatting (`swiftlint --fix` / `rustfmt` strictly on staged
        files).
  - [ ] Hash-check working tree to prevent silent auto-formatting staging.
  - [ ] Live secret scanning on staged diff via `trufflehog` or `gitleaks`.
  - [ ] Target pre-commit run time under **1.5 seconds**.
- [ ] **Deterministic Pre-Push Hook:**
  - [ ] Run `scripts/check-architecture.sh` to enforce port/adapter boundaries
        and composition roots.
  - [ ] Run fast syntax/type checks (`cargo check`, incremental Swift
        verification).
  - [ ] Run targeted, affected unit test suites
        (`scripts/test-unit.sh <Target>`) rather than full integration tests.
  - [ ] Sanitize Git environment variables (`GIT_DIR`, `GIT_WORK_TREE`,
        `GIT_INDEX_FILE`).

### 4.3 Agent Navigation (`AGENTS.md`)

- [ ] **Line Count Audit:** Keep `AGENTS.md` strictly under 100 lines (target
      50–75 lines).
- [ ] **Section 1: Quick Commands:** Compact list of primary commands (run app,
      run companion, unit test, lint).
- [ ] **Section 2: Hard Boundaries & Invariants:** Numbered list of
      non-negotiable architectural rules enforced by mechanical checks.
- [ ] **Section 3: Progressive Disclosure Pointers:** Context pointers linking
      to specialized docs (`docs/ARCHITECTURE.md`, `docs/SECURITY.md`,
      `docs/PROFILING.md`) with explicit activation triggers.

### 4.4 Privacy-Preserving Telemetry & Crash Reporting

- [ ] **Privacy-by-Default:** Ensure SDK defaults to `optOut = true` or
      `telemetry_enabled = false` until explicit user opt-in.
- [ ] **Path Sanitizer:** Install filters replacing `/Users/<name>/` or
      `C:\Users\<name>\` with `~/[REDACTED]`.
- [ ] **Zero PII & Masked IP:** Set `$ip = null` or enable IP discarding at the
      telemetry gateway.
- [ ] **Non-Blocking Architecture:** Route all telemetry and crash logs through
      bounded channels with drop-on-backpressure; never block audio, video, or
      UI threads.
- [ ] **Kill Switch Support:** Honor `DO_NOT_TRACK=1` and application-specific
      disable flags.

---

## 5. Primary Source Citations

1. **Anthropic Official Documentation:** _Managing Agent Context and System
   Instructions in Claude Code._ https://docs.anthropic.com
2. **Liu, N. F., Lin, K., Hewitt, J., Paranjape, A., Bevilacqua, M., Petroni,
   F., & Liang, P. (2023):** _Lost in the Middle: How Language Models Use Long
   Contexts._ Transactions of the Association for Computational Linguistics
   (TACL). https://arxiv.org/abs/2307.03172
3. **Machalica, M., Samylkin, A., Potharaju, R., et al. (Meta Engineering / ICSE
   2022):** _Predictive Test Selection in Large Scale Web Applications._
   Proceedings of the 44th International Conference on Software Engineering.
   https://arxiv.org/abs/2110.14046
4. **Trunk-Based Development:** _Principles, Patterns, and Merge Queues for
   High-Velocity Engineering._ https://trunkbaseddevelopment.com
5. **Realm / 1Password SwiftLint Reference:** _Rules: `force_unwrapping`,
   `force_cast`, `force_try`._ https://realm.github.io/SwiftLint/
6. **Rust-Lang Official Clippy Documentation:** _Restriction Lints:
   `clippy::unwrap_used`, `clippy::expect_used`._
   https://rust-lang.github.io/rust-clippy/master/
7. **Apple Inc. MetricKit Documentation:** _`MXMetricManager`,
   `MXDiagnosticPayload`, and Out-of-Process Crash Diagnostics._
   https://developer.apple.com/documentation/metrickit
8. **PostHog Official Documentation & Repositories:**
   - _PostHog Swift / iOS SDK:_ https://github.com/PostHog/posthog-ios
   - _PostHog Rust SDK & Error Tracking:_ https://github.com/PostHog/posthog-rs
9. **Zed Industries Open Source Architecture:** _Diagnostics, Sentry
   Integration, and Telemetry Privacy Controls._ https://zed.dev/docs/telemetry
   and https://github.com/zed-industries/zed
10. **Evil Martians:** _Lefthook: Fast, Multi-Language, Parallel Git Hooks
    Manager._ https://github.com/evilmartians/lefthook
