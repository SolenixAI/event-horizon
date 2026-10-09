---
version: 1
slug: "glimmer-deskhome-swift"
primary_target: "Glimmer/DeskHome.swift"
related_targets: []
---

# Surface brief: Home (the PC on the desk)

Scope: Citadel's main window, Home state and the grow into the PC. Mode: Operate.
Audience: Mac owners with a gaming PC; job: open the PC or a game in one click, see what is running, come back Home without ending it.

## Direction contract
THESIS: The PC is a live screen on the desk inside the window; opening it grows that same screen to fill the window, and ⌘W puts it back, still running. Refuses the launcher-list-plus-separate-stream-window default.
OWN-WORLD: Native Liquid Glass on the window; one black 16:10 screen in a glass bezel as the only raised object; logo gold (accent) for what you press, logo blue for live/running; SF Pro, system controls, game covers as the only colour fields.
STORY: The user sees their PC and its games at once, knows if it is awake and what is running, clicks the screen or a cover, and is inside the PC; ⌘W returns Home with the PC live on the desk.
FIRST VIEWPORT: Screen centred, ~60% of the window height; under it the PC name, spec line, Running label (blue) and readiness chip on one row; a glass shelf of 2:3 covers along the bottom. The primary action is the screen itself.
FORM: "Your PC on the desk" (rank 1 of 7, dealt by the roll as card 2; chosen by the user over "Type to play" and "Top shelf"); seed key 4838ac34.
FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance

## Unresolved
- Live preview when no session exists (needs a last-frame snapshot).
- Running games started outside Sunshine (needs the PC companion).
- Multi-PC switcher on Home (Stream menu ⌘1-9 covers it for now).
