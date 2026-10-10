---
name: Event Horizon
description:
  A Mac app around your gaming PC. The PC is a live screen on the desk inside
  one native window; a click grows it to fill the window.
colors:
  horizon-gold: "#C9700F"
  horizon-gold-night: "#F08A24"
  horizon-blue: "#3AA0FF"
  screen-black: "#000000"
  window-day: "#FFFFFF"
  window-night: "#1E1E1E"
  label: "#000000D9"
  secondary-label: "#00000080"
  ready-green: "#28CD41"
  caution-orange: "#FF9500"
  fault-red: "#FF3B30"
  space-night-top: "#03040A"
  space-night-bottom: "#0B0E19"
  space-dawn-top: "#E4ECF7"
  space-dawn-bottom: "#F6F1E8"
typography:
  pc-name:
    fontFamily: "SF Pro Display, -apple-system, system-ui, sans-serif"
    fontSize: "17px"
    fontWeight: 600
  screen-title:
    fontFamily: "SF Pro Display, -apple-system, system-ui, sans-serif"
    fontSize: "17px"
    fontWeight: 600
  body:
    fontFamily: "SF Pro Text, -apple-system, system-ui, sans-serif"
    fontSize: "13px"
    fontWeight: 400
  callout:
    fontFamily: "SF Pro Text, -apple-system, system-ui, sans-serif"
    fontSize: "12px"
    fontWeight: 400
  running:
    fontFamily: "SF Pro Text, -apple-system, system-ui, sans-serif"
    fontSize: "12px"
    fontWeight: 500
  caption:
    fontFamily: "SF Pro Text, -apple-system, system-ui, sans-serif"
    fontSize: "10px"
    fontWeight: 500
rounded:
  cover: "9px"
  screen: "12px"
  panel: "12px"
  bezel: "17px"
  shelf: "18px"
  capsule: "9999px"
spacing:
  xs: "3px"
  bezel: "5px"
  sm: "6px"
  md: "10px"
  row: "14px"
  section: "16px"
  shelf-gap: "18px"
  window-x: "32px"
  window-top: "38px"
components:
  desk-screen:
    backgroundColor: "{colors.screen-black}"
    rounded: "{rounded.screen}"
  desk-bezel:
    rounded: "{rounded.bezel}"
    padding: "5px"
  pc-name:
    textColor: "{colors.label}"
    typography: "{typography.pc-name}"
  spec-line:
    textColor: "{colors.secondary-label}"
    typography: "{typography.body}"
  running-label:
    textColor: "{colors.horizon-blue}"
    typography: "{typography.running}"
  stream-volume:
    textColor: "{colors.secondary-label}"
    size: "22px"
  readiness-chip:
    textColor: "{colors.label}"
    typography: "{typography.caption}"
    rounded: "{rounded.capsule}"
    padding: "4px 10px"
  game-shelf:
    rounded: "{rounded.shelf}"
    padding: "12px 14px"
  cover-tile:
    textColor: "{colors.label}"
    typography: "{typography.caption}"
    rounded: "{rounded.cover}"
  cover-tile-on-screen:
    textColor: "{colors.horizon-blue}"
  settings-button:
    rounded: "{rounded.capsule}"
    size: "26px"
  connect-banner:
    textColor: "{colors.label}"
    typography: "{typography.callout}"
    rounded: "{rounded.panel}"
    padding: "10px 14px"
---

# Design System: Event Horizon

## Overview

**Creative North Star: "The PC on the Desk"**

Event Horizon's Home is one Mac window with your PC on its desk. The PC is a
black screen in a glass bezel, and that screen is the main control. Click it and
the same screen grows to fill the window. Press ⌘W and it shrinks back onto the
desk, still running. Under the screen sit the PC's name, its state and a glass
shelf of its games.

The window sits in a deep-space field: near-black at night, and the same
composition at dawn in a pale sky. The window keeps its hidden title bar, SF Pro
and system controls. Event Horizon adds two colours from its logo. Gold is for
what you press. Blue is for what is live on the PC. The horizon light is
atmosphere under the field and never a signal. The game covers are the only
large fields of colour, and they come from the games, not from Event Horizon.

The stream engine underneath is Glimmer, an open-source Swift engine. Glimmer
is an engine credit only. It is not a look, and it is not a name on any
surface.

**Key Characteristics:**

- One raised object: the PC's screen in a glass bezel. Everything else is flat
  or plain glass.
- Gold (the accent) marks what you can press: a 2pt ring on hover.
- Blue marks what is live: the Running label, its dot and the on-screen cover.
- The screen is always black. The PC's own picture or the idle face sits on it.
- Game covers at 2:3 are the only colour fields.
- The grow and shrink between Home and the PC is one continuous move.
- A deep-space field behind Home (dawn in light), system type, system controls.

## Colors

Two logo colours on a plain system window, with the macOS status colours.

### Primary

- **Horizon Gold** (light) and **Horizon Gold, night** (dark): the app's
  `AccentColor`, from the logo's warm ring. It is the hover ring on the bezel
  and on a cover, the tint of system controls, and the gold half of a cover's
  fallback gradient.

### Secondary

- **Horizon Blue**: the logo's cool ring (`Color.horizonBlue`). It marks what
  is live on the PC: the Running label and its 7pt dot, the ring and name of the
  cover that is on screen, the soft halo behind the logo on the idle screen, and
  the blue half of a cover's fallback gradient. On the field it also carries
  the live connection: particles and a pulse (Space Backdrop), at full strength,
  like the Running label. Blue means live, wherever it appears.
  **Open decision:** on the dawn field, the Running label measures about 2.3:1,
  below WCAG 4.5:1. It did the same on the old system window. A deeper live blue
  for light appearance would fix it, but that changes the signal colour, so the
  founder decides.

### Neutral

- **Screen Black**: the PC's screen, in light and dark appearance alike.
- **Space field, night** (`#03040A` at the top to `#0B0E19` at the bottom) and
  **Space field, dawn** (`#E4ECF7` to `#F6F1E8`): the backdrop behind Home, from
  the top of the window to its bottom edge. Night is deep space, and dawn is the
  same composition under a pale sky. They are set once in `SpacePalette`; no
  other view hard-codes a neutral.
- **Label** and **Secondary Label**: the system label colours. The PC name and
  cover names use the label. The spec line uses the secondary label. On the
  black screen, text is white, and the detail line is 60% white.

### Status

- **Ready Green**, **Caution Orange** and **Fault Red** are the system colours.
  They appear only as the readiness chip's 7pt dot and as the connect banner's
  red stroke and faint red tint.

### Named Rules

**The Press Gold, Live Blue Rule.** Gold means "you can press this". Blue means
"this runs on the PC now". Never swap them, and never use either for health.

**The Covers Are the Colour Rule.** Event Horizon paints no coloured slabs and
no coloured fields behind its content. The field behind Home is dark or pale and
never coloured. Large fields of colour come only from the PC's picture and the
games' cover art.

**The Horizon Is Atmosphere Rule.** The horizon light is gold and blue, low on
the field, at most 16% opacity at night and 20% at dawn. It is atmosphere, never
a signal: it never marks a control and never marks a live state. Press gold and
live blue stay at full strength. Against the field they measure at least 3:1,
while the horizon light stays near 1.2:1. This rule covers field light only.
Any new field light must stay under this bar. The live flow's particles and
pulse are live marks, not field light, so they use full live blue.

## Typography

**Font:** SF Pro, the system font, through system text styles only.

**Character:** Home reads like a first-party Mac app. It uses the same text
styles as Finder and System Settings, and it scales with the user's text size.

### Hierarchy

- **PC name** (semibold, title2): the PC's name under the screen, on the
  leading edge.
- **Screen title** (semibold, title2, white): the idle face's line on the
  screen ("Desktop", "<PC> is asleep", "Opening <game>…").
- **Body** (regular, body, secondary): the spec line under the PC name. Facts
  are joined by " · ".
- **Callout** (regular, callout): the screen's detail line ("Click to open your
  PC") and the permission row's sentence.
- **Running** (medium, callout, blue): "Running <game>".
- **Caption** (medium, caption): cover names, with two lines reserved, and the
  readiness chip's label.

### Named Rules

**The System Voice Rule.** Use text styles, not point sizes. Fixed sizes are
only for SF Symbol glyphs (the gear at 13pt, a fallback cover glyph at 30pt)
and the empty pairing state's 26pt headline.

## Layout

Home is one column inside the window: 32pt side margins, 38pt from the top (the
title-bar line) and 22pt at the bottom. The window's minimum size is 640 by
600pt. Its ideal size is 1040 by 780pt, and it resizes freely.

The screen takes the space that is left (it has layout priority). It keeps the
PC's aspect ratio, 16:10 by default. The rows under it are exactly as wide as
the bezel: the screen's width plus 10pt. In order: the status row, 16pt below
the screen; the game shelf, 18pt below that; and the controller permission row,
12pt below the shelf, only when it is needed.

The status row puts the PC name and the spec line on the leading edge, 3pt
apart. The Running label follows 14pt after them, then a flexible gap, then the
readiness chip on the trailing edge. A connect banner, when there is one, sits
above the screen with 10pt below it.

The shelf is as wide as its covers when they fit, aligned to the leading edge.
When they do not fit, it takes the bezel's width and scrolls sideways, and its
last 10% fades out to show that there is more. Cover width follows the desk:
about nine across, from 100 to 150pt, 14pt apart.

The Settings gear sits on the title-bar line, 10pt in from the trailing edge,
across from the window buttons. There is no toolbar, so full screen is all PC.

### Named Rules

**The One Width Rule.** The status row, the shelf and any row under the screen
line up with the bezel's edges. Nothing under the screen is wider than it.

**The Screen Takes the Room Rule.** When the window grows, the screen grows.
The rows under it keep their natural height.

## Elevation & Depth

The field behind Home is flat: it casts no shadow and has no raised layer. Its
only light is the horizon, which is atmosphere. There is one raised object: the
bezel around the PC's
screen. It is regular Liquid Glass, 5pt wide, with a 1pt light catch on its top
edge that fades out by its middle (60% white in light, 28% in dark). In light
appearance it also casts a soft black shadow. In dark appearance it casts none,
and the light catch alone lifts it.

Everything else is plain glass with no shadow: the shelf, the readiness chip,
the gear and the banner. A cover gets a shadow only while the pointer is on it.

### Shadow Vocabulary

- **Bezel lift** (black 18%, radius 18, y 10; light appearance only): the
  bezel.
- **Cover lift** (black 35%, radius 10, y 6; hover only): a cover under the
  pointer, with a 1.03 scale.
- **Logo halo** (Horizon Blue 35%, radius 24, no offset): the app icon on the
  idle screen. It repeats the halo that the logo itself carries. It is used
  nowhere else.

### Named Rules

**The One Raised Object Rule.** Only the bezel is raised at rest. Anything else
that lifts does so only in answer to the pointer.

## Shapes

Every corner is continuous (a squircle). The radii nest: the 12pt screen sits
5pt inside the 17pt bezel. When the PC grows to fill the window, the screen's
corner goes to 0, and the window's own corner frames it. Covers are 2:3 with
9pt corners. The shelf is 18pt. Inset rows (the banner, the permission row) are
12pt. The readiness chip is a capsule, and the gear is a circle.

Rings carry state: a 2pt ring on the bezel or on a cover. It is gold on hover
and blue on the cover that is on screen. The screen has a 1pt edge at 12% white,
so its black stays separate from a dark bezel.

### Named Rules

**The Concentric Rule.** Inner radius = outer radius − inset. The bezel's
radius is the screen's radius plus its 5pt inset.

## Components

### Desk Screen (signature)

- **What it is:** a real `Button` that is the PC's screen. It is black, at the
  PC's aspect ratio, inside the glass bezel.
- **Idle face:** the app icon (84pt) with its blue halo, a white title and a
  60% white detail line, centred. While Event Horizon waits, a large progress
  spinner takes the icon's place.
- **Live:** the PC's stream sits exactly on the screen's frame, with 12pt
  corners, and keeps running while Home shows.
- **Hover:** a 2pt gold ring on the bezel, with a snappy 0.2s fade.
- **Accessibility:** "<PC> screen", with the state as its value and the action
  as its hint.

### Grow and Shrink (signature motion)

- **Grow:** the stream surface moves from the screen's frame to the whole
  window in 0.42s on a fast-out curve (0.2, 0.9, 0.25, 1). Then its corner goes
  to 0.
- **Shrink:** it moves back onto the desk in 0.38s on the same curve, with 12pt
  corners.
- **Window buttons:** while the PC fills the window, close, minimise and zoom
  step aside. They come back while the pointer is in the top 28pt strip, as in
  QuickTime.
- **Reduce Motion:** the surface jumps to its frame with no animation.

### Status Row

- The PC name with the spec line under it, then the Running label in blue with
  its 7pt dot (hidden for the Desktop), and the readiness chip on the trailing
  edge. A right-click opens the PC's menu.

### Readiness Chip

- A plain glass capsule with 10 by 4pt of padding: a 7pt status dot, the state
  in caption medium and, when ready, a quiet route glyph (Wi-Fi or Ethernet) in
  secondary. The dot pulses while connecting, unless Reduce Motion is on.

### Stream Volume

- **Placement:** on the status row, between the Running label and the readiness
  chip, at the chip's height (22pt). It yields first: when the Running label
  would truncate, the row drops it (`ViewThatFits`). The menu bar panel keeps
  the same control under Stream.
- **Style:** a 13pt medium speaker symbol in secondary label, with no glass, no
  ring and no shadow. It is a press target, but it is quiet, so it never competes
  with the chip's glass or the bezel.
- **Popover:** a headline "Stream volume" (hidden from VoiceOver), then a mute
  button and a level slider in 16 steps. Mute is announced as "Mute stream" or
  "Unmute stream". The slider is "Level".
- **Accessibility:** "Stream volume", with the percentage or "Muted" as its
  value, and adjustable up and down by one step.

### Game Shelf

- One plain glass panel (18pt corners) with 12 by 14pt of padding. It holds the
  PC's games as a row of cover tiles. The Desktop is not on the shelf, because
  the screen is the Desktop.

### Cover Tile

- A real `Button`: the game's own 2:3 art with 9pt corners, and the name under
  it in caption medium on two reserved lines.
- **Hover:** a 2pt gold ring, a 1.03 scale and the cover lift, with a snappy
  0.18s animation.
- **On screen:** a 2pt blue ring and a blue name. The same source drives this
  and the Running label, so they always agree.
- **Launching:** a progress spinner over the cover.
- **No art yet:** a blue-to-gold gradient (55% and 45%) with the app's SF
  Symbol in white.

### Settings Button

- The gear SF Symbol (13pt medium) in a 26pt interactive glass circle on the
  title-bar line. It is a `SettingsLink`, so ⌘, works too.

### Connect Banner

- It sits above the screen only when a connection fails: a warning glyph, the
  error in callout medium, a glass action button and a dismiss button. Glass
  tinted red at 0.12, with a 1pt red stroke and 12pt corners. It slides in from
  the top, and it fades under Reduce Motion.

### Controller Permission Row

- A quiet plain-glass row (12pt corners) under the shelf. It shows only when a
  controller needs Input Monitoring: a controller glyph, one sentence, "Allow…"
  and a borderless "Not Now". It is never an alert.

### Space Backdrop

- **What it is:** the field behind Home, under the whole window, title bar
  included. A static sky, the stars (night only) and the horizon light. Over
  them, the live connection flows as faint blue particles on an undrawn round
  trip: from the Mac's side of the bottom horizon, along the margin left of the
  PC's bezel, and back. Nothing is stroked; the path is felt through the motion.
- **Density follows the bitrate.** Up to 36 particle slots show, all at the
  stream's bitrate of 80 Mbps. Idle shows none.
- **The pulse follows the latency.** One crisp pulse makes the round trip. Its
  lap is 1 s plus 0.12 s per ms, up to 9 s, so a quick ping reads quick and a
  spike reads stretched.
- **Where the numbers come from.** While the PC is ready, the readiness ping
  behind the chip (the same figure the chip shows). While a PC streams, the
  stream's own latency and bitrate, the same stats the stats overlay reads. No
  new network call. The numbers are sampled once a second, smoothed, and applied
  only when they change by more than 2%.
- **Still:** with no live data (asleep, unreachable, checking, connecting), the
  flow shows nothing and runs no animation.
- **Drift:** the flow runs on the render server as keyframe path animations on
  CALayers, with no main-thread frames. Density changes fade particles in and
  out over 0.6 s, and each particle keeps its phase, so the others never jump.
  The field, the stars, the horizon light and the grain are static layers
  painted at the window's backing scale. The flow freezes when the window is
  not key or the app is in the background, and while a stream fills the window.
  It is hidden under Reduce Motion, and it resumes without a jump.
- **Placement:** the flow stays in the margin beside the bezel. It never
  crosses the status row, the readiness chip or the game shelf.
- **Accessibility:** hidden from VoiceOver. The chip and the stream's stats
  already speak the same numbers, so the flow adds nothing for a screen reader.
- **Contrast:** labels keep WCAG contrast on the field. Night labels measure at
  least 12.9:1 and their secondary text at least 5.7:1. Dawn labels measure at
  least 14:1 and their secondary text at least 5:1.

### First-Launch Pass

- **What it is:** the five-screen first run, in the main window and not in a
  sheet: Welcome, Find your PC, Pair your PC, Set up controls and alerts, and
  the PC's Ready screen. Each screen has one title (title2, bold), one short
  body and one footer action. The find and pair screens are the pairing view
  in its embedded form, so the pairing state survives the step change.
- **Progress:** five 22 by 4pt capsules above the title. The current and done
  steps are filled at 70% label, the rest at 15%. VoiceOver reads "Step n of 5".
- **Explain first:** every system prompt sits behind a Mac-side explanation
  with one button, "Continue". Discovery starts on Continue, so the Local
  Network prompt follows the reason on screen. The PC's own Allow follows the
  Mac's explanation, never comes first.

### Permission Card and Rail

- **What it is:** one card per optional item: a 26pt symbol, the name in
  headline, the live state as a caption label, one sentence of reason, and one
  action. The states are Allowed, Waiting, Off, Needs approval and Not in this
  build. "Continue" shows only while the choice is open, "Open Settings" once
  it is refused, and nothing once it is settled.
- **Not now:** a borderless line under the card, outside its glass, and never
  on the explanation. Skipping replaces the card with one quiet sentence.
- **Rail:** the cards read macOS on every appearance and each return to the
  app, and nothing is stored. The same rail sits in Settings › General under
  Permissions, so a grant later reads the same way. Settings also lists Open at
  login, which the pass does not offer; its only action is Open Login Items,
  shown when macOS waits for approval.
- **Surface:** regular glass at 12pt corners, 14pt padding. It is a card, not
  a raised object, so it has no shadow.

### Companion Keep-Awake Row

- **What it is:** a quiet glass row above the game shelf, shown before the
  first stream of a Mac that has no companion token, to a PC that runs the
  companion. It has one sentence of reason, "Allow on <PC>" (prominent) and
  "Stream without it" (borderless). A presence check reads the PC first. No
  pairing request is sent before Allow.
- **Code:** after Allow, the row shows the code the PC is asked to match, and
  the Allow button is disabled until the PC answers. If the PC refuses, the row
  says so and offers "Try again".
- **Once per PC:** "Stream without it" is kept for that PC, so the row is not
  shown again for it. A companion token from pairing makes the row unnecessary.

## Do's and Don'ts

### Do:

- **Do** make the PC's screen the primary action. Any new way into the PC grows
  the same screen.
- **Do** keep gold for what you press and blue for what is live.
- **Do** build every custom look as a style on a real control (`Button`,
  `SettingsLink`), so focus, keyboard and VoiceOver stay native.
- **Do** use the system window background and system text styles.
- **Do** line up every row under the screen with the bezel's edges.
- **Do** nest radii concentrically, and use continuous corners.
- **Do** honour Reduce Motion in the grow, the shrink, hovers, pulses and the
  field's drift.
- **Do** let the games' own cover art carry the colour on the shelf.

### Don't:

- **Don't** give anything but the bezel a resting shadow or a raised look.
- **Don't** use blue for something you press, or gold for something that is
  running.
- **Don't** put colour slabs, coloured gradients or tinted cards behind Home's
  content. The field is the one exception: dark or pale, never coloured. The
  only other gradient is a cover's fallback tile.
- **Don't** add a toolbar to the main window. Full screen is all PC.
- **Don't** open the PC in a second window. The PC opens in this window.
- **Don't** use a coloured glow, except the logo's own halo on the idle screen,
  the horizon light on the field, and the live flow's particles and pulse,
  which are live marks. The horizon light is never a signal.
- **Don't** redraw, recolour or reinterpret the app icon (the three-body
  figure-eight orbit).
- **Don't** show "Glimmer" anywhere a person reads, except the engine credit.
- **Don't** use em dashes, emoji, exclamation marks, or "host" or "server" in
  anything a person reads.
