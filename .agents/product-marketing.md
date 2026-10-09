# Product Marketing Context

**Document version:** v3
**Last updated:** 2026-10-09

## Product Overview
**One-liner:** Your gaming PC, as a Mac app.
**Name:** Event Horizon (founder decision 2026-10-09). The black hole's flat surface that holds everything inside: your PC's world, flattened onto your Mac's screen. "Event Horizon" is the codename.
**What it does:** Event Horizon puts the gaming PC in the other room inside a Mac window. Home shows the PC as a live screen on a desk with a shelf of its games; one click grows the PC into the window, and ⌘W puts it back on the desk while it keeps running. The Mac stays yours: free cursor on the PC's desktop, pointer lock only in games, Mac shortcuts on the PC.
**Product category:** Remote play / game streaming client for Mac (shelf neighbours: Moonlight, Steam Remote Play, Parsec, Jump Desktop).
**Product type:** Native macOS app (Apple Silicon, macOS 26), sold direct. The PC runs Sunshine (free, open source).
**Business model:** $29 one-time with a 14-day trial and a year of updates, optional renewal after (founder decision 2026-10-09). Sold direct (merchant of record: Paddle or Lemon Squeezy), never the Mac App Store. Constraint: Event Horizon is GPL-3 (built on Glimmer and Moonlight), so the source is public; the paid product is the signed, updated, supported build plus the one-link PC setup.

## Target Audience
**Target customers:** Mac owners who also own a Windows or Linux gaming PC at home.
**Decision-makers:** The player themselves (B2C).
**Primary use case:** Use the whole PC, its desktop and its games, from the Mac without getting up and without losing the Mac.
**Jobs to be done:**
- Play my PC games from the couch on my MacBook, sharp and with low latency.
- Use my PC's desktop like a Mac window (copy-paste, ⌘Tab, Spaces) when I need something on it.
- Leave the game running and come back to it without restarting anything.
**Use cases:**
- Couch: MacBook on Wi-Fi, PC in the other room (the main and harder scene).
- Desk: the Mac as the PC's screen.

## Problems & Pain Points
**Core problem:** Every way to reach the PC from a Mac either lags, looks soft, or takes over the Mac.
**Why alternatives fall short:**
- Steam Remote Play: soft picture and lag on a Mac; Steam games only.
- Moonlight and Glimmer: excellent engines, but game-first clients that lock the pointer, cover the desktop and raise popups that trap the user.
- Remote-desktop apps (Jump, Screens, Chrome Remote Desktop): built for work, not 60 fps games.
**What it costs them:** Getting up to play, or giving up and playing nothing; a Mac that feels hijacked while streaming.
**Emotional tension:** "Is it going to grab my mouse again?" Unpredictability makes people fall back to the worse but predictable option.

## Competitive Landscape
**Direct:** Moonlight / Glimmer — same engine class, free; fall short on the Mac experience (pointer, popups, no library).
**Direct:** Steam Remote Play — free and predictable; falls short on picture, latency and non-Steam apps.
**Secondary:** Parsec, Jump Desktop — general remote access; game feel and Mac integration vary. `<?>` current prices (research 2026-10-09 pending).
**Indirect:** Cloud gaming (GeForce NOW, Shadow) — no PC needed, but not *your* PC, library or mods.

## Differentiation
**Key differentiators:**
- It never takes over your Mac: no popups, cursor free on the desktop, locked only after you click into a game.
- The PC is a place in one window: Home → PC → Home, the PC keeps running live on the desk.
- Your games with their own covers, pulled from the PC.
- Everything automatic: a game that needs an update waits for it and opens; quirks become automatic fixes, not settings.
**How we do it differently:** An experience layer on a proven open engine (Sunshine + Glimmer's native Swift stream), built natively in SwiftUI/AppKit with Liquid Glass.
**Why that's better:** Mac-native feel at the engine's latency.
**Why customers choose us:** It feels like the PC is a Mac app.

## Objections
| Objection | Response |
|-----------|----------|
| Moonlight is free. | It is, and Event Horizon's source is too. You pay for the Mac experience, signed updates and the one-link PC setup. |
| Setting up Sunshine is hard. | The PC companion (planned) installs and pairs it in one link. `<!>` Not built yet. |
| Will it lag on Wi-Fi? | Same engine class as Moonlight; measured 0 dropped frames over 5 h on home Wi-Fi (2026-10-08). |

**Anti-persona:** People without a gaming PC (cloud gaming fits them); competitive esports players who need wired, local play.

## Switching Dynamics
**Push:** Remote Play's soft picture and lag; Moonlight/Glimmer trapping the Mac.
**Pull:** "Your PC, as a Mac app": one window, one click, one ⌘W.
**Habit:** Steam Remote Play is already installed and predictable.
**Anxiety:** Setup effort on the PC; whether it grabs the mouse.

## Customer Language
**How they describe the problem:**
- "it took over my primary desktop view"
- "my mouse only appears on my dock… totally hijacks my macOS attention"
- "at least its predictable" (why people stay on Steam Remote Play)
**How they describe us:**
- "already far surpassed the remote play experience and glimmer experience"
- "the experience is very just intuitive and native feeling big time"
- "100000x better then steam remote play"
- "super seamless"
**Words to use:** your PC, as a Mac app; seamless; native; on the desk; one click; keeps running.
**Words to avoid:** remote desktop, streaming client, hijack (except about others), setup jargon (RTSP, HEVC) in headlines.
**Glossary:**
| Term | Meaning |
|------|---------|
| Home / the desk | Event Horizon's main screen; the PC as a live screen with its games |
| Grow | Opening the PC: it fills the window |
| PC companion | Planned one-link installer for Sunshine on the PC |

## Brand Voice
**Tone:** Calm, confident, Mac-native.
**Style:** Short and concrete; show, don't claim.
**Personality:** native, quiet, precise, playful underneath (the three-body logo), honest.

## Proof Points
**Metrics:** 0 dropped frames in a 5-hour home Wi-Fi session; host encode 4–6 ms; first frame 0.9 s from launch (founder tests, 2026-10-08).
**Customers:** None yet. Do not invent any.
**Testimonials:**
> "the experience is very just intuitive and native feeling big time" — founder, first user (2026-10-08)
**Value themes:**
| Theme | Proof |
|-------|-------|
| Never takes over your Mac | Free cursor on the desktop, click-to-lock in games, no popups |
| Feels local | 0 dropped frames over 5 h; HEVC 2560×1600 @ 60 |
| One window | Home → PC → Home with ⌘W |

## Goals
**Business goal:** First paying customers outside the founder.
**Conversion action:** Download and pair a PC.
**Current metrics:** None (pre-launch).

## Changelog
*Newest first. One line per revision: what changed and why.*
- v3 (2026-10-09) — Product name: Event Horizon.
- v2 (2026-10-09) — Business model set to $29 one-time + 14-day trial + 1 year of updates; rename before launch; direct sales only (GPL-3 rules out the Mac App Store).
- v1 (2026-10-09) — Initial context, auto-drafted from PRODUCT.md, the Phase 1–2 builds and the founder's own words.
