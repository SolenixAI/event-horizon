# Agent guide for Event Horizon

Event Horizon is a native macOS portal (Swift) to your Windows or Linux PC (Rust
companion for Sunshine). Before modifying code, read the relevant context
pointers below.

## Quick commands

- Build Mac app: `make app`
- Build PC companion: `cd companion && cargo build`
- Run all tests: `make test`
- Run focused unit test: `bash scripts/test-unit.sh <TestSuiteName>` or
  `make test-unit TEST=<TestSuiteName>`
- Check lint and format: `pre-commit run --all-files`
- Check architecture boundaries: `bash scripts/check-architecture.sh`
- Check Rust companion:
  `cd companion && cargo fmt --check && cargo clippy --all-targets -- -D warnings`

## Hard boundaries and invariants

1. **Unsandboxed execution:** The Mac app runs unsandboxed to manage the root
   AWDL helper (`helper/`).
2. **Untrusted network inputs:** All wire packets (RTSP, ENet, RTP) and
   companion REST inputs are untrusted. Parse defensively at the boundary; never
   trap, force-unwrap (`!`), or force-cast (`as!`).
3. **No URLSession in Stream:** Use `ControlTransport` (Network.framework mutual
   TLS) because the keychain locks on sleep.
4. **Backend instantiation:** Construct `NativeBackend` only in
   `Glimmer/AppModel+Streaming.swift`. Inject `StreamingBackendFactory`
   elsewhere.
5. **No swift-format:** We use SwiftLint with `--fix`. Do not run swift-format.
6. **Concurrent branch fence:** Do not touch `companion/src/outputs.rs` or
   `companion/tests/outputs.rs` (owned by an active display-selection session).
7. **Zero compiler warnings:** `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` and
   `GCC_TREAT_WARNINGS_AS_ERRORS = YES` are active. All code must compile with
   zero warnings.

## Progressive disclosure pointers

- Read [GLOSSARY.md](GLOSSARY.md) for ubiquitous terms (Home, Grow, Back to
  Home, PC, PC companion).
- Read [PRODUCT.md](PRODUCT.md) for product vision, portal positioning, and
  presentation architecture.
- Read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) when modifying streaming
  pipelines or connection lifecycle.
- Read [docs/SECURITY.md](docs/SECURITY.md) when modifying pairing, TLS cert
  pinning, or helper XPC protocols.
- Read [docs/PROFILING.md](docs/PROFILING.md) when measuring streaming latency,
  frame pacing, or audio cushion drift.
- Read [docs/companion/DESIGN.md](docs/companion/DESIGN.md) when editing the
  Rust companion or Linux/Windows adapters.
