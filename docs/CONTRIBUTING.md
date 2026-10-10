# Contributing

Event Horizon is your other computer, as a Mac app. It has two parts:

- **The Mac app** (`Glimmer/`): a Mac-native client for
  [Sunshine](https://github.com/LizardByte/Sunshine), built on
  [Glimmer](https://github.com/Se7enbrc/glimmer)'s engine. Swift 6, Apple
  Silicon, macOS 26 and later. Socket, decoder, display, audio and input all run
  in one Swift process, with no external player and no C engine.
- **The PC companion** (`companion/`): one Rust program for Windows and Linux
  that installs Sunshine, pairs with the Mac after one Allow click, and keeps
  the PC awake while a Mac plays. Its design is
  [companion/DESIGN.md](companion/DESIGN.md).

The bar is one sentence: someone using Event Horizon should mistake it for
something Apple shipped. Everything below follows from it.

## Find your way

Read the part of [ARCHITECTURE.md](ARCHITECTURE.md) for the area you change
before you change it. Before UI work, read [DESIGN.md](../DESIGN.md) (the visual
system) and [PRODUCT.md](../PRODUCT.md) (who it's for, and the settled
decisions). [PROFILING.md](PROFILING.md) gets the telemetry an engine change
needs, and [SECURITY.md](SECURITY.md) covers the root helper.

| Path                         | What lives there                                                                             |
| ---------------------------- | -------------------------------------------------------------------------------------------- |
| `Glimmer/`                   | The app: SwiftUI and AppKit UI, `AppModel+*`, menu bar, settings, logging (`LogStore.swift`) |
| `Glimmer/Stream/`            | The stream around the protocol: decode, display, audio playout, input, pairing, telemetry    |
| `Glimmer/Stream/Native/`     | Sunshine's protocol: RTSP, the ENet control channel, RTP video and audio, FEC                |
| `Glimmer/Stream/HIDGamepad/` | Raw-HID game controllers and the generated controller database                               |
| `Glimmer/CLI/`               | The `event-horizon` command line, in the app binary                                          |
| `Glimmer/Models/`            | The PC record and a few settings types                                                       |
| `helper/`                    | The opt-in root daemon that parks AirDrop's radio during a stream                            |
| `LoginHelper/`               | The login item                                                                               |
| `GlimmerTests/`              | Hostless unit tests                                                                          |
| `companion/`                 | The PC companion (Rust)                                                                      |
| `scripts/`                   | Build, signing and release tooling the Makefile calls                                        |
| `docs/agents/`               | Where agent skills find the issue tracker, triage labels and domain docs                     |

## Setup

Required:

- macOS 26 or newer
- Xcode 27 or later, for the macOS 27 SDK and its toolchain (Swift 6, `swiftc`,
  `xcodebuild`, `xcrun`); the app still runs on macOS 26
- Homebrew

Brew prerequisites:

```bash
brew install swiftlint trufflehog pre-commit
```

The app links no third-party library: crypto, TLS and audio decode use Apple's
frameworks (CryptoKit, CommonCrypto, Security, Network, AudioToolbox), not
OpenSSL or libopus. There are no submodules and no vendored C library.
`swiftlint` and `trufflehog` back pre-commit hooks, and the commit fails without
them.

Clone:

```bash
git clone https://github.com/SolenixAI/event-horizon.git
cd event-horizon
```

Install pre-commit hooks:

```bash
pre-commit install                      # lint + secret scan, per commit
pre-commit install --hook-type pre-push # `make test`, per push
```

## Build

```bash
make app        # compile-only check (Debug), no signing
make test       # unit tests
make verify     # strict lint + unit tests: the gate
make            # notarized Release build, installed to /Applications
make open       # same, then open it
```

One suite, after `make test` has run once:

```bash
xcodebuild test -project Glimmer.xcodeproj -scheme Glimmer -configuration Debug \
    -xcconfig Glimmer/StreamLib.xcconfig CODE_SIGNING_ALLOWED=NO -derivedDataPath build \
    -destination 'platform=macOS' -only-testing:GlimmerTests/DatagramBatchTests
```

`make verify` does not fail on compiler warnings, so read the build log: it must
have none.

Never run the publishing or keychain targets (`dist`, `release-publish`,
`brew-bump`, `sparkle-keys`, `creds-init`, `setup-notary`, `codesign-setup`,
`codesign-teardown`) unless the maintainer asks for that exact target. They
publish to users or rewrite signing state. Signing material lives outside the
repo, in `~/Library/Keychains/developer-id.keychain-db` and
`~/.config/developer-id/`; `make app`, `make test` and `make verify` never touch
it. Never read, print, copy or change it.

`make` and `make open` run the full shipping pipeline: Developer ID signing,
notarization, strict library validation. That is deliberate: there is no ad hoc
or Debug divergence in daemon registration, TCC or library validation to chase,
because you always run what ships. Without a Developer ID certificate on the
machine it falls back to an ad hoc Release build (not notarized, and TCC asks
again).

The canonical xcodebuild invocation (what `make app` runs) is:

```bash
scripts/generate-build-info.sh
xcodebuild -project Glimmer.xcodeproj -scheme Glimmer -configuration Debug \
    -xcconfig Glimmer/StreamLib.xcconfig \
    CODE_SIGNING_ALLOWED=NO \
    -derivedDataPath ./build -destination 'platform=macOS' build
```

The script writes `Glimmer/BuildInfo.generated.swift`, the commit and build date
that telemetry stamps on every session. The project compiles that file but it is
not checked in, so a fresh clone fails with a missing input file until the
script has run once. `CODE_SIGNING_ALLOWED=NO` leaves signing to the Makefile's
`sign` target; without it, Xcode's Automatic signing asks for the keychain once
per nested bundle.

To run what you're working on, either use `make dev` (unit tests, then the
notarized Release build, installed and relaunched on the same signing path as
`make install`), or work in Xcode against `Glimmer.xcodeproj`:

1. Run `scripts/generate-build-info.sh` once so
   `Glimmer/BuildInfo.generated.swift` exists (`make app` and `make test` run it
   for you).
2. Base the Debug configuration on `Glimmer/StreamLib.xcconfig` (project editor
   → Info → Configurations), and keep that change out of commits. It supplies
   the bridging header and the version from `Glimmer/Version.xcconfig`.
3. Build and run.

Useful log tails:

```bash
log stream --predicate 'subsystem == "dev.solenix.eventhorizon"' --level info
```

See [PROFILING.md](PROFILING.md) for per-category predicates.

### Build hygiene: don't mint app copies

**Build once per thing you actually want to look at.** Not once per edit.

macOS gives every distinct copy of the bundle its own privacy identity. Anything
that registers an `Event Horizon.app` with LaunchServices (and `make app`
re-registers its Debug bundle on _every_ run) earns a separate row under
**System Settings → Privacy & Security → Local Network**. Those rows are TCC
records: they survive deleting the app, and they survive a reboot.

One session of rebuild-on-every-edit produced **nine** registered copies (two
checkouts' `build/`, two DerivedData trees, `/Applications`, Trash, Downloads)
and eight Local Network entries. The app then could not reach a PC on the LAN,
and the failure surfaced as `Couldn't reach <ip>`, which reads as a network
problem and is not one.

Keep the inner loop cheap and batch the install:

```bash
make app     # compile-only check: fast, no install
make test    # unit tests
make dev     # ONLY when you want to actually use the build
```

Clean up copies you created:

```bash
LSREG=/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/\
LaunchServices.framework/Versions/A/Support/lsregister
"$LSREG" -dump | grep -oE '/.*Event Horizon\.app' | sort -u   # what macOS knows about
"$LSREG" -u /path/to/stale/Event Horizon.app                      # unregister one
rm -rf build ~/Library/Developer/Xcode/DerivedData/Glimmer-*
```

Unregistering does **not** retract the privacy grants. Only this does, and only
the user can run it:

```bash
sudo tccutil reset All dev.solenix.eventhorizon
```

`tccutil reset LocalNetwork <bundle-id>` is rejected: `LocalNetwork` is not a
service name `tccutil` accepts. `All` is the working form, and it also clears
Input Monitoring (the DualSense raw-HID grant), so expect to re-approve that.

## UI changes

The launcher window is **sized to its content and not resizable**
(`.windowResizability(.contentSize)` in `GlimmerApp`). That only holds while
every view in the column states a _definite_ size, which makes ordinary SwiftUI
idioms load-bearing in a way that is easy to miss:

- `minHeight:` / `minWidth:` are **floors, not sizes**. A view with a floor
  accepts any larger size it is offered, so one of them anywhere in the column
  hands the window something to grow into: the window becomes resizable again
  and the offending view stretches to fill whatever the user drags out.
- `.frame(maxWidth: .infinity)` has no size of its own to measure.
- A trailing `Spacer()` exists to push content against a container taller than
  itself. In a content-sized window there is no such space, so it can only
  invent some.
- `ConnectSurface` and `EmptyPairingState` therefore end in
  `.fixedSize(horizontal: false, vertical: true)`: they take their ideal height
  rather than the offered one. Keep it that way.

The window's `minWidth` in `GlimmerApp` must equal the connect surface's real
width (card width plus twice its horizontal padding). A floor _below_ the true
content width leaves the window that much range to be dragged through, and it
opens at the bottom of that range with the margins squeezed flat.

**Verify geometry against the running app, not the source.** Every one of the
above was shipped at least once on a source reading that looked right. Build,
install, launch, then ask the window what it actually did:

```bash
osascript <<'EOS'
tell application "System Events"
  tell process "Event Horizon"
    set w to first window
    set s0 to size of w
    set out to "opens at " & ((item 1 of s0) as integer) & "x" & ((item 2 of s0) as integer)
    try
      set size of w to {1200, 900}
    end try
    delay 0.7
    set s1 to size of w
    return out & "  after_grow=" & ((item 1 of s1) as integer) & "x" & ((item 2 of s1) as integer)
  end tell
end tell
EOS
```

If `after_grow` differs from the opening size, something in the column is still
flexible. This takes about a minute and is not optional for a geometry change: a
resize regression once survived two releases because it was only ever read,
never run.

A UI pull request should say which of these it touches, and include a
before/after screenshot at the smallest and largest window the change allows.
“Builds clean” is not evidence about layout.

### Copy

- Copy is short, plain and specific, like the app's own “Couldn't reach Den PC.
  Make sure it's awake and on the same network.” Sentence case. No em dashes, no
  emoji, no exclamation marks, no jargon a player wouldn't use.
- The machine is “the PC” or its name, never “host” or “server”, in anything a
  person reads.
- Sunshine is the server application on the PC. Moonlight is a separate client
  that inspired Glimmer, not a host and not the protocol's name. The protocol is
  Sunshine's RTSP-based one.
- `…` is one character. A command that needs more input before it finishes ends
  with it (Pair a PC…, Rename…); one that only opens a window does not.
  Quotation marks are curly (“ ”); apostrophes stay straight.
- An error says what happened and the one thing to do next, names the PC, and
  reuses the shared failure copy rather than new words for the same failure.
- Every surface keeps its VoiceOver labels and keyboard navigation.

## Lint

`swiftlint` runs as a pre-commit hook over `Glimmer/`, `GlimmerTests/`,
`helper/` and `LoginHelper/`; `scripts/` is build-time tooling and is not held
to the product lint bar. The commit hook blocks only on errors, but
`make verify` lints with `--strict`, where any warning fails, and the release
build runs it. Treat a warning as a failure. Thresholds worth knowing from
`.swiftlint.yml`:

- `force_unwrapping`, `force_cast`, `force_try`: warnings, so strict fails them.
- File length and type body warn at 600, function body at 80, and strict holds
  every file to that.
- `line_length` warns at 140, errors at 280, ignoring URLs and comments.

The pre-commit wrapper runs `swiftlint --fix` first; if it rewrites any Swift
file, the commit is **refused** and you are told to re-stage the diff. The hook
never stages for you, so you see what changed.

`swift-format` is intentionally NOT enforced: Apple's formatter reflows the
codebase's trailing-aligned function arguments into a noisier style.

A `trufflehog` secret scan runs per commit against verified detectors, and
`prettier`, `markdownlint`, and `yamllint` cover the non-Swift files.
Credentials never belong in the tree; see [SECURITY.md](SECURITY.md).

## Style

- 4-space indent, opening brace on the same line, trailing newline. Match
  neighbouring files.
- File / type names match the load-bearing type they contain
  (`VideoDecoder.swift` → `class VideoDecoder`). Extensions split out by feature
  (`VideoDecoder+HDR.swift`, `VideoDecoder+Bitstream.swift`).
- Protocol constants mirror their upstream C names verbatim
  (`COLORSPACE_REC_2020`, `DR_NEED_IDR`) so a reader can grep the spec.
  `identifier_name.allowed_symbols: ["_"]` exists for exactly that.
- Comments in new and changed code earn their keep and stay at three lines or
  fewer, doc comments and file headers included: what the code is for and the
  one-line why. If a future maintainer would have to dig through an upstream PR
  thread to understand a line, the why goes in the source; the full story goes
  in the commit message.
- No emoji in source files.
- Zero warnings, from the compiler and `swiftlint lint --strict` both. Fix the
  cause: no inline `swiftlint:disable` (the generated controller database is the
  one exception), no raised thresholds, no warning moved into a helper the
  linter can't see. A 17-way `if` chain becomes a table, not a function with the
  same 17 branches.
- Reuse before you write. The codebase has a helper for most things (failure
  copy, route addresses, host matching, probes). Change shared logic once, where
  every caller routes through.
- Less code: no protocol with one conformer, no configuration for a constant, no
  scaffolding for later. Delete dead code; never comment it out. No new
  dependency for what the platform or a few lines can do.
- No force unwraps, casts or `try!`, including `URL(string:)!` on a literal,
  which strict lint does not catch.
- New tests use Swift Testing (`@Test`, `#expect`). Pure logic gets a test; a
  bug fix gets a test that fails without it. The project has no synchronized
  folders, so add a new file to `project.pbxproj` by hand: file reference, build
  file, group and Sources phase.

## Concurrency

Swift 6 strict concurrency mode is on. The codebase is `@MainActor`-heavy on UI
code and `actor`-heavy in the streaming engine.

Rules:

- **`@MainActor`** for anything that touches `NSWindow`, `NSEvent`,
  `AVSampleBufferDisplayLayer` configuration, or SwiftUI bindings.
  `VideoDecoder`, `InputForwarder`, `StreamWindow`, and `AppModel` are all
  `@MainActor`-isolated at the class level.
- **`actor`** for engine subsystems with non-trivial cross-thread state:
  `StreamSession`, `NetworkClient`, `PairingClient`, `IdentityManager`.
- **`@unchecked Sendable` with a documented lock** when a system framework
  forces callbacks onto its own threads:
  - `AudioDecoder` (AVAudioEngine callbacks on Core Audio threads, internal
    state lock-guarded).
  - `StatsCollector` (touched from the engine's receive thread, the VT decode
    queue, AND the main actor; guarded by an internal `OSAllocatedUnfairLock`).
  - `StreamBridgeContext` (the receive-thread callback target).

### `nonisolated(unsafe)`

`nonisolated(unsafe)` IS acceptable in this codebase, and there are about 70 of
them. Every use must document the invariant in a comment on the property: what
the synchronisation discipline is, and why a regular actor or lock isn't viable.

Acceptable patterns:

- **Receive-thread callback bridging.** The native engine hands us frames and
  control events on its own receive threads, on hot paths that can't afford an
  actor hop per frame. The weak refs on `StreamBridgeContext` are
  `nonisolated(unsafe)` because Swift weak storage is atomic per spec and the
  engine serialises its callbacks per stream. Swift 6 strict concurrency can't
  see through to that guarantee, but the load is sound.
- **VT decode-queue state.** `decompressionSession`, `formatDescription`, SPS /
  PPS / VPS, stream parameters in `VideoDecoder.swift` are touched from the
  engine's receive thread (submit) and the VT output callback (decode). They
  live on `decodeQueue` (a serial `DispatchQueue`) and are serialised by it.
- **Single-writer-from-MainActor reads-from-anywhere.**
  `VideoDecoder.hdrEnabled` is written on the main actor, read by the VT output
  callback. A Bool load/store is naturally atomic on every supported arch; the
  eventually-consistent read is correct here (HDR-flip → next-frame fallback
  colorspace).
- **MainActor-only `Foundation.Timer` slots on an actor.**
  `StreamSession.statsOverlayTimer` is allocated and invalidated on the main
  actor (the only thread that may touch a `Timer`), but the _actor_ needs to
  schedule those mutations via `await MainActor.run`. The actual mutation only
  ever runs on the main thread.

NOT acceptable:

- “It compiled” without an invariant comment.
- Multi-writer races. If two threads can write the same slot,
  `nonisolated(unsafe)` is wrong: use a lock or hop to an actor.
- Anything with a Sendable-incomplete type behind it (`CALayer`,
  `AVSampleBufferDisplayLayer`). Wrap with an `NSLock` around the load/store
  (`VideoDecoder._displayLayer` is the reference pattern).

### Event-yield discipline

The canonical place to surface a stream event to the consumer is
`StreamBridgeContext.eventContinuation?.yield(_:)`. `AsyncStream.Continuation`
is `Sendable` and FIFO-ordered, so yielding from the engine's receive thread
preserves the order the native engine delivered them in. The previous
`Task { await deliver(...) }` pattern lost ordering because consecutive Tasks
land on the global concurrent executor without inter-Task happens-before; see
the comment at `StreamBridgeContext.eventContinuation` (in
`StreamBridgeContext.swift`) for the motivating regression.

## Logging

`Logger` from `os`, never `print`, never `os_log`.

- Subsystem: **`dev.solenix.eventhorizon`** (capital G). Every `Logger` in the
  app uses this string; no `.Stream` suffix on the subsystem. The privileged
  AWDL helper is a separate process and uses `dev.solenix.eventhorizon.helper`.
- Category: per-file, dotted form `Stream.<Area>` for streaming-engine files.
  The current list is in [PROFILING.md](PROFILING.md#unified-log); add to it
  when you add a file, don't reuse a neighbour's category. Signposts sit on the
  same subsystem with their own categories (`Stream.Decode`, `Stream.Render`,
  `Stream.Network`, `Stream.Pairing`, `Stream.Audio`) in
  `Glimmer/Stream/Signposts.swift`.
- Privacy:
  - `privacy: .public` for non-sensitive diagnostic data (stage names, decode
    timings, codec format ints, error codes).
  - `privacy: .private` (the default) for anything PII-adjacent: PC addresses,
    PC names, error message strings, Sunshine versions.
  - `Diag.*` takes the same `privacy:` argument as `Logger`, but defaults to
    `.public`, so mark those values `.private` there too:
    `Diag.info("Connecting to \(address, privacy: .private)", "Stream")`.
    Private values reach only the in-app log viewer and what you copy from it.
    The system log and the session file, which people attach to public issues,
    show `<private>` in their place. Telemetry names the PC and the Mac by
    per-install pseudonyms, never their names.
  - Never log:
    - Key characters from `keyDown` events (a later change fixed the regression
      where `chars=...` leaked at `.public`).
    - URLs carrying `rikey`, `rikeyid`, `gcmkey`, `gcmkeyid`, `uuid`, or
      `uniqueid`. `NetworkClient.sensitiveQueryKeys` is the set; the redaction
      that consumes it lives in `NetworkClient+Endpoints.swift`.
    - Cert PEMs or fingerprints at `.public` (a hostile log scraper could read
      the pinned cert; see [SECURITY.md](SECURITY.md)).
    - PIN values, AES keys, signed pairing-secret bytes.

The current Swift 6 strict-concurrency posture means
`Logger.info("\(value, privacy: .public)")` is the standard form. Logging on
long-running paths (per-frame, per-mouseMoved) is gated behind explicit
conditions: never log per-frame at `.info`.

## Commits

CalVer for releases (`YYYY.M.MICRO`). See [RELEASE.md](RELEASE.md).

Conventional-commit-style prefixes are used in the repo's history; match what's
there. Common prefixes:

- `fix(area)`: bug fix scoped to a subsystem
- `feat(area)`: new behaviour
- `perf(area)`: performance fix
- `refactor(area)`: non-behavioural rework
- `test`: tests only
- `build`: Xcode, Makefile, scripts
- `chore`: repo hygiene
- `docs` or `docs(area)`: these files

Subject line: imperative mood, lowercase after the prefix, no trailing period.
Body wrapped at about 72 columns when one's needed.

**No attribution to tools or agents.** No `Co-Authored-By` trailer, no session
trailers or links, no “Generated with” line, no model or tool names: not in
commits, pull request titles or bodies, the changelog, or code comments. Hard
rule of repo policy. No emoji in commit messages either.

Never commit with `--no-verify`: a failing hook is telling you something. If
`swiftlint --fix` rewrote files, review them and stage them again. No keys,
tokens, certificates, signing material or credentials in the tree, in commits,
in logs or in pull request text.

## The bar

When a change would make Event Horizon worse (less tasteful, noisier, slower,
less reliable, less like a Mac app, or more complex than it earns), say no at
once and plainly. Name the cost in a sentence or two, then describe the version
that would be accepted. “Add a setting” is not an answer to a design problem: a
toggle that exists because nobody made the decision is a bug.

**“It builds clean” is table stakes, not evidence.** Neither is “the tests
pass”. Both are necessary; neither says anything about whether the thing is any
good.

The bar for anything a user can see or feel is: **would someone with taste,
looking at this for two seconds, be appalled?** If you would not put it in a
demo, it is not done, however green the checks are.

This is not hypothetical. Glimmer shipped a launcher whose PC card floated in
several hundred points of empty window. It compiled without a warning, the tests
passed, SwiftLint was clean, and it was obviously wrong to anyone who opened it.
Walking it back took the rest of a release train: 2026.8.3 pinned the window to
its content and left the card nearly touching the frame, and 2026.8.4 put the
margins back. Each attempt had been validated by reading the diff instead of
looking at the app.

Practically, before you call something done:

- **Run it.** Not the test suite: the app, the way a user meets it.
- **Look at it**, in the states a user will hit: empty, one PC, many apps,
  mid-stream, disconnected, light and dark, the smallest and largest window you
  allow.
- **Prove the claim you are making.** If the claim is “no longer resizable”,
  drive the window and read the size back (see [UI changes](#ui-changes)). If it
  is “reconnects cleanly”, pull the cable. A claim you have not exercised is a
  guess with a commit message.
- **Say what you did NOT verify.** An honest “the dropdown has never rendered
  with more than two apps” is worth more than silence, and it is what lets the
  next person aim their attention.

## Pull requests

- Start with an issue. Describe the problem or the change, and wait for the
  maintainer to agree on the approach before you write code. A pull request that
  doesn't link an agreed issue is closed.
- `event-horizon` is the default branch; releases are tags on it.
- Fork, push your branch to the fork, and open the PR from there against
  `event-horizon`. Only the maintainer can push branches to this repository or
  merge into `main`.
- Keep a PR scoped to one area, so it can land independently.
- Leave `CHANGELOG.md` and `Glimmer/Version.xcconfig` alone: the maintainer
  picks the version and writes the release notes when a change ships. Each
  release there is a `## <version> - <date>` heading over a flat list of
  bullets, one per change a player will notice, written for them. See
  [RELEASE.md](RELEASE.md).
- The maintainer's own changes that a person will notice carry a `CHANGELOG.md`
  bullet and bump both lines of `Glimmer/Version.xcconfig` in the same pull
  request: Sparkle orders updates by `CURRENT_PROJECT_VERSION`, so a build
  number that doesn't rise is never offered.
- The pull request says what changed and why, what you ran and looked at, and
  what you did not verify.
- Before you ask for a merge, run the thing and look at it. [The bar](#the-bar)
  is the checklist.

What gets closed:

- A pull request from outside that doesn't link an issue the maintainer agreed
  to.
- Warnings, lint suppressions, raised thresholds, or skipped and disabled tests.
- A file over 600 lines or a comment over 3 lines.
- UI that nobody ran and looked at; layout that floats, clips, jumps or
  stretches; placeholder copy, em dashes, “host” in copy.
- Engine, pacing or bitrate changes without telemetry.
- A Metal renderer, Game Mode, web views, Electron or cross-platform layers.
- New dependencies for what the platform already does.
- Speculative abstractions, dead or commented-out code, `TODO`s with no issue.
- Tool or agent attribution anywhere, secrets anywhere, or `--no-verify`.

## Working in a fork

Event Horizon is GPLv3 (a fork of Glimmer), and forks are welcome. The rules
here decide what merges here; in a fork they're the fork's call. Before a fork's
build reaches anyone else:

- **Change every identifier**: the bundle IDs (`dev.solenix.eventhorizon`,
  `dev.solenix.eventhorizon.LoginHelper`, `dev.solenix.eventhorizon.helper`),
  the product name, the logging subsystem and the data folders. Shared IDs make
  macOS mix the fork's permissions, login item and data with Event Horizon's.
- **Give Sparkle your own feed.** Replace `SUFeedURL` and `SUPublicEDKey` in
  `Glimmer/Info.plist` with your appcast and your key (`make sparkle-keys`).
  Left as they are, the fork keeps checking the original feed: it either
  installs the original over itself or rejects every update.
- **Sign as yourself.** The Makefile uses whatever Developer ID is in your
  keychain. Without one, builds are ad hoc and not notarized.
- **Keep `LICENSE` and `CREDITS.md`**, including the moonlight-common-c credit.
- **A change offered back starts as an issue** the maintainer agrees to, then
  comes as a pull request from the fork, on top of the current default branch,
  one area per pull request.
