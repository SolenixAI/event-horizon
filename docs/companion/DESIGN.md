# Event Horizon PC companion: design

The companion turns any gaming PC into an Event Horizon host. It is one Rust
program organized as a modular monolith. `main.rs` is the composition root: it
chooses the OS implementations, handles install and utility commands, builds the
host, and starts the TLS link server. The Host owns pairing and awake-lease
policy; the installer, game library, Sunshine client, and Link server are
separate modules around it.

**Bar:** a friend goes from solenix.dev to playing a game on their PC from their
Mac in 5 minutes or less, with no help and no terminal.

## The journey it serves

1. On the Mac, Event Horizon finds no PC. It shows "On your PC, open
   solenix.dev/eh" and a 6-letter code.
2. On the PC, the person downloads one installer and runs it. The installer
   installs Sunshine silently, sets its credentials, and starts the companion at
   login.
3. The companion advertises itself on the home network. The Mac finds it.
4. The Mac asks to pair. The PC shows "Allow <Mac name> to use this PC?" with
   the same 6-letter code. One click on **Allow** pairs them.
5. From now on the companion keeps the PC awake while the Mac is connected (no
   blanking, no sleep, no idle auto-lock), tells the Mac what is really on
   screen, and keeps the game shelf in step with the PC's library. A PC that was
   already locked still asks for its password once.

## Modules

```mermaid
flowchart TB
  subgraph Mac["Mac: Event Horizon.app"]
    M[Companion client]
  end
  subgraph PC["PC: companion (one binary per OS)"]
    MAIN["main.rs<br/>composition root"]
    L["Link<br/>TLS HTTP API"]
    H["Host<br/>pairing · awake lease"]
    S["LocalSunshine<br/>local config API"]
    LIB["Library sync"]
    G["Steam game source"]
    subgraph Seams["OS adapters"]
      I[Installer]
      A[Awake]
      P[Prompt]
    end
  end
  SUN[(Sunshine)]
  M <-->|"pair · lease · status"| L
  L --> H
  H --> A & P & S
  MAIN --> I & L & G
  G --> LIB --> S
  S --> SUN
```

### Host and its ports

`Host<S, P, A>` owns the pairing state machine and awake leases. Its generic
dependencies are the `SunshineApi`, `Prompt`, and `Awake` traits in
`companion/src/ports.rs`. `main.rs` constructs `LocalSunshine` and the platform
prompt and awake implementations, then passes the `Host` to `link::serve`. The
core does not import an OS adapter.

```rust
let host = Host::new(sunshine, prompt, awake);
link::serve(listener, tls, host, macs).await;
```

Host behavior is exercised through its public pairing and lease operations:

- **Pairing.** It holds a pending request, asks `Prompt` with the code, and on
  Allow submits the Mac's PIN to Sunshine. Two timers: the companion waits 2
  minutes for a click; Sunshine holds the Mac's started pairing for 5. A second
  request from the same Mac replaces the first. The Mac's id matches the PIN to
  its pending pairing in Sunshine (`GET /api/pin`, then `POST /api/pin` with
  `pairing_id`, `pin` and `name`).
- **Lease.** The Mac renews a lease every 30 s while it streams. While any lease
  is fresh, the core holds one `Awake` guard. When the last lease is older than
  90 s, it drops the guard. One guard, not one per Mac.
- **Library sync.** `library::keep_in_step` merges `GameSources` into Sunshine's
  apps and leaves apps it did not create alone. `main.rs` starts it when Steam
  is available; it is outside the Host state machine.
- **Status.** The Link returns the pairing and lease state the Mac needs. Game
  discovery and library synchronization are handled by their own modules.

### The OS seams

Platform behavior lives in `companion/src/os/windows/` and
`companion/src/os/linux/`. The installer is idempotent setup logic; platform
modules provide its command and filesystem implementations. The Linux display
installer keeps those effects behind the `Commands` and `Files` ports in
`companion/src/linux_install.rs`; its stream-display recovery state machine is
isolated in `companion/src/linux_install/display.rs`. Unit and integration tests
replace the system effects with fakes.

| Boundary              | Current entry point or port                                                       | Windows implementation                                                           | Linux implementation                                                                                                                      |
| --------------------- | --------------------------------------------------------------------------------- | -------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| Install orchestration | `os::{windows,linux}::install(&Path)` (idempotent setup entry point; not a trait) | Silent Sunshine installer; Virtual Display Driver with `docs/vddsettings.xml`    | Flatpak `dev.lizardbyte.app.Sunshine`; user service; uinput setup; on KDE Wayland a krfb virtual screen at 2560×1600 (`linux_install.rs`) |
| `Awake`               | `hold() -> AwakeGuard` (dropping the guard releases it)                           | Power request: display + system required (proven: `powercfg /requests` lists it) | `org.freedesktop.ScreenSaver.Inhibit` + login1 `idle:sleep` inhibit, from the desktop session                                             |
| `Prompt`              | `ask_allow(mac_name, code) -> Decision` (times out to Deny)                       | Native dialog from the tray app                                                  | KDE notification with actions, fallback dialog                                                                                            |
| `GameSources`         | `installed() -> Vec<LibraryGame>`                                                 | Steam library                                                                    | Steam library (native + Flatpak)                                                                                                          |

`SunshineApi` (pin, apps, restart) is the same on both OSes. It has one real
adapter (HTTPS to `localhost:47990` with the credentials the installer set) plus
a fake, so it is an internal seam for tests, not an OS seam.

### Link: the Mac's way in

- **Discovery.** mDNS service `_eventhorizon._tcp` with TXT `v=1` and
  `fp=<SHA-256 of the companion's certificate, DER, in lowercase hex>`. The Mac
  does not browse this service yet, so it learns the fingerprint on first use
  (next bullet).
- **Transport.** HTTPS on TCP 47970 with the companion's own self-signed
  certificate, made on first run and kept as `companion-cert.der` and
  `companion-key.der` beside `macs.json` (the key file is 0600 on Unix). No
  certificate authority: the Mac pins the fingerprint, not a name.
- **Trust (v1).** Trust on first use, then pinned. The Mac trusts the first
  certificate a PC shows and keeps its fingerprint in the Keychain beside the
  token; every later request must show that fingerprint. Pairing trusts the PC
  afresh, because the code on both screens is the check made at that moment. A
  man in the middle during the first pairing could relay the code, so that first
  step has no defence beyond the code check; the TXT record closes it once the
  Mac browses the service.
- **Pairing (two steps).** `POST /pair` with `{mac_id, mac_name, pin?}` answers
  at once with `{code, ticket}`. The code is six random digits. The PC shows it
  on its Allow dialog, with the Mac's name. The Mac shows the same code, then
  waits on `GET /pair/{ticket}` for up to 2 minutes. The ticket is random, so
  only the Mac that asked can collect the answer. On Allow the companion gives
  Sunshine the PIN, and the answer is `{outcome: "paired", token}`: a random
  256-bit token, of which the companion keeps only the SHA-256. The Sunshine PIN
  goes only over TLS and is never shown as the code. A second `POST /pair` from
  the same Mac replaces the first, whose answer is `replaced` (409).
- **Lease.** `POST /lease` with the token keeps the PC awake for 90 s. The Mac
  renews every 30 s.
- **Unpair.** `DELETE /pair` with the Mac's own token removes its record here
  and its client in Sunshine (see Rules). If Sunshine cannot be reached, nothing
  is removed and the answer is 502, so the Mac can try again. On the PC,
  `event-horizon-companion --list-macs` and `--unpair <mac id>` do the same
  without the Link running.
- **Protocol.** JSON over HTTPS: `GET /hello`, `POST /pair`,
  `GET /pair/{ticket}`, `POST /lease`, `DELETE /pair`. Versioned by the `v` TXT
  field and by `/hello`. `GET /status` is the next slice.

## Rules learned the hard way

- **One pairing per Mac identity.** Sunshine accepts a client certificate only
  when exactly one paired record matches it (`is_client_enabled`,
  `src/nvhttp.cpp`). Pairing the same Mac twice locks it out until the duplicate
  is removed (seen on the tower, 2026-10-09T19:23-02:30). The Mac checks
  `PairStatus` before it pairs, and never pairs a PC it is paired with.
- **No system OpenSSL.** Sunshine's API uses reqwest: rustls on Linux, the OS's
  TLS on Windows and macOS (dev). Sunshine's local certificate is self-signed,
  so that client accepts it on the loopback address only. The Link's server uses
  rustls on the same provider as reqwest on each OS: aws-lc-rs on Linux, ring on
  Windows and macOS (ring builds without NASM or CMake).
- **Sunshine names a pairing by its device name, not a client id.** Its pending
  list (`GET /api/pin`) gives an approval id, a name and an address, and nothing
  that identifies the client. So the Mac names its Sunshine pairing with its own
  id (the `devicename` it sends Sunshine), and the companion matches on that id.
  Two Macs with one display name never match each other's pairing. The client is
  then listed under the display name.
- **Sunshine's client id is its own.** Sunshine gives each paired client a
  random uuid, not the Mac's id, and `GET /api/clients/list` does not show which
  client is which Mac. The companion lists the clients before and after a
  pairing, under one lock, and keeps the new uuid in `macs.json`. Unpair posts
  that uuid to `POST /api/clients/unpair`. A Mac paired with Sunshine before the
  companion has no recorded uuid, so Unpair removes only the companion's record;
  that Sunshine client stays until it is removed in Sunshine's own web page.
- **Unpairing the last client ends Sunshine's apps.** Sunshine's unpair stops
  its running apps when no client is left (`src/confighttp.cpp`, `unpair`). That
  is harmless when the last Mac leaves a stream.
- **Sunshine skips its CSRF check for API clients** (no `Origin` or `Referer`
  header), so the companion needs only its Basic login.

## Errors the core owns

- Sunshine not reachable: the core reinstalls or restarts it once, then reports
  `SunshineDown` in `status`. The Mac shows it on the desk.
- Allow not clicked in 2 minutes: `PairOutcome::Expired`. The Mac offers to try
  again.
- Credentials lost (user reset Sunshine): the installer sets new ones on the
  next run, and pairing still works because the Mac's trust is Sunshine's.

## How it is tested

- `Host` tests use the fakes for every port and a fake clock. They cover pairing
  (Allow, Deny, expiry, replace), lease (hold, renew, release, two Macs),
  library merge (add, keep user apps, remove gone games), and status mapping. No
  OS, no network, no Sunshine.
- `Link` tests run the real HTTPS server on a loopback port over the fakes: the
  two-step pairing and its code, replace, lease with the token, unpair here and
  in Sunshine, and a client that pins the advertised fingerprint connects while
  another does not. Sunshine's pending pairings are matched by the Mac's id,
  with two Macs of one display name.
- Each OS adapter has a small contract test that runs on its own OS in CI: free
  GitHub runners for Windows and Linux.
- One end-to-end test per OS installs the real Sunshine on the runner and pairs
  with a scripted Mac client.

## Build order (test-first, one slice at a time)

1. Workspace + `Host` with fakes: pairing state machine.
2. Lease → `Awake` (both adapters).
3. `SunshineApi` adapter + Link (mDNS, `/pair`), first real pairing from the
   Mac.
4. `Installer` (both OSes) + the installer packages.
5. `GameSources` + library sync; `Foreground` + status.
6. Mac side: onboarding with the short link and code, lease renewal, status on
   the desk (and the Mac's own Home keep-awake nudge retires).

## Out of v1

Play away from home (needs a relay), macOS hosts, more launchers than Steam and
Jagex, auto-update of the companion (v1 checks and offers).
