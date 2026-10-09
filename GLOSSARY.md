# Event Horizon

Event Horizon makes a gaming PC feel like a Mac app: a Mac app that shows the
PC in one window, and a PC companion that sets the PC up for it.

## Places

**Home**:
The Mac app's main screen, where each paired PC sits as a live screen with a
shelf of its games.
_Avoid_: launcher, dashboard, menu

**Grow**:
Opening a PC or a game from Home, so the PC's screen fills the window.
_Avoid_: connect, launch, go full screen

**Back to Home**:
Leaving the grown PC (⌘W) while it keeps running on Home.
_Avoid_: disconnect, close, quit

## Things

**PC**:
A Windows or Linux computer, running Sunshine, that a Mac uses through
Event Horizon. Sunshine's protocol and the code call it the host.
_Avoid_: tower, server, remote

**Mac app**:
Event Horizon on the Mac.
_Avoid_: client, launcher

**PC companion**:
The small Event Horizon program on the PC that installs Sunshine, pairs with a
Mac after Allow, and keeps the PC awake while a Mac plays.
_Avoid_: agent, daemon, helper, host app

**Sunshine**:
The open-source program on the PC that streams its screen, sound and input.
_Avoid_: server, host software

**Game**:
An app on the PC that Home shows with its own cover.
_Avoid_: app (Sunshine's word), title

**Desktop**:
The PC's own desktop, opened as a stream with a free cursor.
_Avoid_: remote desktop

**Stream**:
One live session of the PC's picture, sound and input in the Mac app.
_Avoid_: session (except in code), connection

## Trust

**Pairing**:
The one-time trust between one Mac and one PC: Sunshine records the Mac's
certificate, and the PC companion gives the Mac a link token.
_Avoid_: login, registration

**Allow**:
The click on the PC that approves a Mac's pairing.
_Avoid_: accept, confirm

**Link token**:
The secret a paired Mac shows the PC companion to prove which Mac it is.
_Avoid_: API key, password

**Lease**:
The Mac's promise, renewed while it streams, that keeps the PC awake.
_Avoid_: heartbeat, keep-alive

## Input

**Free cursor**:
The pointer moves in and out of the PC's window like any Mac pointer. Used on
the desktop.
_Avoid_: absolute mouse

**Locked pointer**:
The pointer is held by the PC for raw aim while a game is in front, and freed
when you leave.
_Avoid_: captured mouse, mouse grab
