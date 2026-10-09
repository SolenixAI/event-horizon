# Product

<!-- impeccable:product-schema 1 -->

## Platform

ios

## Users

Mac owners with a gaming PC at home. They use the PC's whole desktop for
anything, and they play its games. Two scenes:

- on the couch with a MacBook on Wi-Fi (the main and harder scene);
- at a desk, with the Mac as the PC's screen.

Desktop work and games both matter. The first customer is the founder (one
MacBook Air M5, one Linux gaming PC running Sunshine).

## Product Purpose

Citadel makes a gaming PC feel like an app on the Mac: open Citadel, pick the PC
or a game, and the PC is there, sharp and immediate, inside a real Mac window.
Success is the user forgetting it is a stream while the Mac stays fully theirs.

## Positioning

**It never takes over your Mac.** Game-first clients (Moonlight, Glimmer, Steam
Remote Play) lock the pointer, cover the desktop and raise popups that trap the
user. Citadel is a Mac app around the PC: the cursor, gestures, Spaces, Stage
Manager and Mac shortcuts stay the user's, while the PC feels local.

- Desktop: a free cursor that is the PC's cursor; Mac shortcuts (⌘C ⌘V ⌘Z …)
  become Ctrl on the PC; ⌘Tab, ⌘Space, ⌘Q and gestures stay with the Mac.
- Games: the pointer locks only while the game is in front and frees itself when
  the user leaves.
- Engine: Glimmer's native Swift stream engine (decode, pacing, audio, input),
  which Citadel builds on. Solenix builds only the experience layer.

## Operating Context

- Open Citadel → Home with the paired PC(s) and their apps (Desktop + games).
- Pick one → the PC opens in Citadel's window; the green button gives Citadel
  its own full-screen Space; ⌘W returns Home while the PC keeps running; Quit
  disconnects.
- Home network or Tailscale from anywhere; Sunshine on the PC with a virtual
  display at the Mac's size.
- Setup for new users (later): a one-link PC companion that installs Sunshine
  underneath and pairs by itself.

## Capabilities and Constraints

- macOS 26 or later, Apple Silicon. The platform value above is `ios` because
  the schema has no macOS value; it selects Apple HIG guidance. Citadel is a Mac
  app: the macOS HIG applies, iPhone-specific guidance does not.
- Never an attention hijack: no popups over or before the stream, no forced
  activation, no cursor hidden or trapped outside an explicit game lock, never
  covering the user's desktop Space.
- Works against a current, unmodified Sunshine.
- No analytics, tracking or third-party network calls.
- Built on Glimmer (GPL-3): Citadel's source must be open when distributed; it
  is unsandboxed, so the Mac App Store is not an option as-is.
- Unsigned local builds cannot use the Wi-Fi (AWDL) helper; signed builds need
  the Apple Developer Program (undecided).
- Undecided: business model; public use of the name.

## Brand Commitments

- The name is Citadel (pending a public-name check).
- The icon is the three-body figure-eight orbit (`brand/`, `Glimmer/AppIcon.icon`).
- Accent: the logo's gold and blue, replacing Glimmer's purple.
- Credit Glimmer as the open-source engine.
- System controls only: SwiftUI and AppKit with Liquid Glass; a custom look is a
  style on a real control and keeps native focus, keyboard and VoiceOver.

## Evidence on Hand

- Founder test, 2026-10-08: "audio is working great, video quality is great,
  latency and input feel really good, already far surpassed the Remote Play and
  Glimmer experience".
- Measured: Mac↔PC Wi-Fi spread ±16–20 ms; host encode 4–6 ms; first frame
  0.9 s from launch.
- Founder, 2026-10-08: "the experience is very intuitive and native feeling, big time".
- No customers, benchmarks or testimonials beyond the founder. Do not invent them.

## Product Principles

1. The Mac stays the user's: nothing in Citadel may take the cursor, the
   keyboard, the screen or attention without the user asking.
2. The PC should feel local: fidelity and latency come before features.
3. One app, one window, one journey: Home → PC → Home, no detours.
4. Native first: use the macOS control or behaviour, style it, never redraw it.
5. Build only the experience; reuse the engine and the OS for everything else.
6. Everything automatic, real-time and in sync: every quirk the user meets becomes
   a native automatic fix (poka-yoke), never a setting or a step they must learn.

## Accessibility & Inclusion

Every surface carries VoiceOver labels and full keyboard navigation, and motion
respects Reduce Motion.
