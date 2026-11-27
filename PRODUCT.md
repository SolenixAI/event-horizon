# Product

<!-- impeccable:product-schema 1 -->

## Platform

macos

## Users

Mac owners with a Windows or Linux gaming PC at home. They want to harness their
PC's full graphics and compute power for high-refresh gaming and desktop work
alike directly from their Mac without technical friction. Two primary scenes:

- on the couch or in bed with a MacBook on Wi-Fi (watching on the Mac or a TV in
  the room);
- at a desk, with the Mac as the PC's screen.

The project exists because existing solutions have critical flaws:

- **Steam Remote Play:** Suffers from severe I/O latency, washed-out color
  grading, and erratic frame pacing on MacBooks over Wi-Fi.
- **Moonlight, Sunshine, and raw Glimmer:** Provide capable low-level streaming
  protocols, but suffer from rough, non-intuitive, and non-native user
  experiences. They trap mouse cursors, swallow native Mac gestures, present
  confusing configuration dialogs, and require complex manual network setup that
  alienates non-technical users.

Event Horizon bridges the gap between powerful streaming tech and everyday
users. It provides an intuitive, first-class native Mac experience that anyone
or an AI agent helping them can set up, use, and trust effortlessly.

## Product Purpose

Event Horizon is a native macOS portal to your other computer. Open Event
Horizon, select your PC or a game, and the PC is there instantly inside a clean
Mac window. Success is complete immersion: the user forgets the PC is in another
room because it behaves like a local Mac app, while their Mac remains completely
theirs.

## Positioning

**A native portal, not a screen takeover.** Traditional remote play clients
treat your Mac like a dumb monitor: they lock the cursor, swallow macOS
gestures, hijack the screen, and disrupt your workflow. Event Horizon surrounds
the remote PC with macOS conventions:

- **Natural desktop flow:** On the PC desktop, the pointer moves seamlessly
  between your Mac and the PC without locking. Standard Mac keyboard shortcuts
  (⌘C, ⌘V, ⌘Z, ⌘S, ⌘A) automatically translate to PC equivalents (Ctrl+C,
  Ctrl+V, Ctrl+Z, Ctrl+S, Ctrl+A), while Mac system controls (⌘Tab, ⌘Space, ⌘Q,
  Stage Manager, Mission Control) remain fully responsive.
- **Context-aware game lock:** Clicking into a game locks the cursor for precise
  3D input. Swiping to another Space or ⌘Tabbing away immediately frees the
  pointer.
- **All-in-one managed experience:** The user never configures Sunshine or
  virtual displays manually. The PC companion manages the streaming daemon,
  virtual screens, awake leases, and pairing under the hood.

## Operating Context

- **One-window mental model:** Open Event Horizon → Home shows paired PCs and
  available games. Pick one → the PC opens in a native window; the green zoom
  button grants its own full-screen Space; ⌘W returns Home while the PC keeps
  running; Quit disconnects.
- **All-in-one PC companion:** A single lightweight Rust companion program on
  the PC. Running it installs Sunshine underneath, creates the virtual display
  matching the Mac's native aspect ratio and resolution, supports dynamic output
  selection between virtual displays and physical room monitors/TVs (e.g. HDMI
  TV or desk monitor), and pairs with the Mac with a single "Allow" click.
- **Agent and human accessible:** Simple, deterministic setup that human users
  or autonomous AI agents can execute, verify, and maintain with single-command
  workflows.
- **Network reach:** Home LAN or Tailscale from anywhere, with zero port
  forwarding required.

## Capabilities and Constraints

- **Platform:** macOS 26 or later on Apple Silicon. Built with pure Swift,
  SwiftUI, AppKit, Metal, and VideoToolbox.
- **Zero-copy video presentation:** The primary presentation engine uses
  `AVSampleBufferDisplayLayer`. It connects directly to Apple Silicon's hardware
  VideoToolbox decoder, passing decoded `CVPixelBuffer`s straight to
  WindowServer with zero memory copies, automatic EDR/HDR10 tonemapping, and
  tear-free ProMotion vsync pacing. Metal compute shaders remain an
  architectural option for future post-processing filters (such as CRT scanlines
  or custom upscaling).
- **All-in-one abstraction:** Users do not install or manage Sunshine
  separately. The PC companion downloads, configures, and supervises Sunshine as
  an automated service, abstracting low-level daemon and firewall details behind
  a seamless pairing handshake.
- **Open-source flagship:** Event Horizon is free and open source (GPL-3) on
  GitHub. It serves as a community utility and a premier software engineering
  showcase. Packaged, signed release builds are distributed free of charge via
  GitHub Releases and Homebrew Cask, with potential future app packaging
  exploration.
- **Error capture and telemetry:** Anonymous error and crash reporting (PostHog)
  is off by default and opt-in through the Settings › General toggle. No
  personal data, keystrokes, or screen contents are ever transmitted.
- **Hardened security:** Mutual TLS authentication, out-of-band PIN pairing with
  strict certificate pinning, and minimal XPC boundary for the optional root
  Wi-Fi helper (`awdl0` suppression).

## Brand Commitments

- **Name:** Event Horizon.
- **Icon:** The three-body figure-eight orbit (`brand/`,
  `Glimmer/AppIcon.icon`).
- **Visual identity:** Deep space black with warm gold and event-horizon blue
  accents.
- **Native system controls:** SwiftUI and AppKit with Liquid Glass aesthetics.
  Real native controls only; zero web views, zero cross-platform UI shims.

## Evidence on Hand

- **Technical benchmarks:** Sub-frame hardware decode latency (under 4 ms for 4K
  HEVC/AV1), adaptive display pacing at 120Hz/240Hz, and sub-16 ms Wi-Fi jitter
  absorption via adaptive audio cushioning.
- **Verification evidence:** Automated test suite with 1,244 unit tests,
  deterministic fuzzing suites for all wire parsers, and live performance
  metrics visible in the in-app telemetry overlay (⌃⌥⌘D).
- **Visual evidence:** Live screen captures, latency traces, and reproducible
  profiling artifacts documented in [docs/PROFILING.md](docs/PROFILING.md).

## Settled Decisions

A pull request is not the place to reopen these.

- **The presentation engine is `AVSampleBufferDisplayLayer`:** Leverages Apple
  Silicon hardware VideoToolbox decoding and OS-level HDR tonemapping without
  copy overhead.
- **All-in-one PC companion management:** Sunshine is driven and supervised
  exclusively through the companion's automated installation and local API;
  users are never asked to configure Sunshine manually.
- **Zero compiler warnings:** `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` and
  `GCC_TREAT_WARNINGS_AS_ERRORS = YES` enforced across all targets.
- **Dual-language architecture:** Pure Swift client on macOS; pure Rust
  companion on Windows and Linux. The two meet only over authenticated network
  protocols.
- **The Mac stays the user's:** The app never traps the cursor on desktop mode,
  never blocks system gestures, and never raises modal popups over active
  streams.
- **Command-line interface:** Pure Swift CLI built into the app binary
  (`event-horizon`), sharing the app's models and distributed notification
  channels.

## Product Principles

1. **The Mac stays the user's:** Nothing in Event Horizon may take the cursor,
   the keyboard, the screen, or attention without the user explicitly asking.
2. **A native portal, not a screen takeover:** The remote PC behaves like a
   natural resident of macOS, respecting Spaces, gestures, shortcuts, and window
   management.
3. **Stand on the shoulders of giants:** Leverage Apple's native frameworks
   (VideoToolbox, AVSampleBufferDisplayLayer, CryptoKit, Network.framework) and
   battle-tested open-source modules (Sunshine, ENet wire protocol) rather than
   re-inventing low-level primitives.
4. **All-in-one abstraction:** Automate the technical plumbing (streaming
   daemons, virtual screens, firewall rules, awake leases) so non-technical
   users and AI agents never deal with low-level configuration.
5. **One app, one window, one journey:** Home → PC → Home, with zero unnecessary
   detours or setup mazes.

## Accessibility & Inclusion

Every surface carries complete VoiceOver labels, full keyboard navigation, and
respects macOS system settings (Reduce Motion, Increase Contrast, and Dynamic
Type).
