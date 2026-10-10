---
type: research
sources: 70
generated: 2026-10-09T19:12-02:30
verified: false
status: draft
stale_after: 2027-01-09
---

# Event Horizon PC companion: primary-source research

This note answers eight questions for the v1 PC companion. It uses primary sources only: project source at a pinned ref, official docs, first-party APIs, and specs.

Reading rules:

- Each claim has its source URL and the source date, in the -02:30 offset.
- `<~>` marks a claim that I did not measure or fully read.
- `<?>` marks an open question. Each one has a timestamp, a description, and a source.
- `<!>` marks a landmine. `<⊥>` marks a contradiction between two sources.
- Sunshine claims cite the release tag. A tag does not change, so the link stays valid.

## Pinned references

| Project | Pin | Date (-02:30) | License |
|---|---|---|---|
| LizardByte/Sunshine | tag `v2026.914.233613`, commit `63d35f702ee9e362e43263742981836ec0710384` | 2026-09-14T22:47-02:30 (tag published) | GPL-3.0 (https://github.com/LizardByte/Sunshine/blob/v2026.914.233613/LICENSE) |
| KDE/kwin | commit `c55a16fcc589c18f5edac1907b6136d80f40bbdc` (default branch) | 2026-10-08T23:24-02:30 (commit) | GPL-2.0-or-later `<~>` (not read) |
| KDE/kscreenlocker | commit `e77531aef569db551d0fd1e18b5253bdd1e1ca3e` | `<~>` (commit date not read) | `<~>` |
| KDE/powerdevil | commit `61d4b551c452d5164cafc50c4b15dca2526c2431` (default branch) | 2026-10-07T23:32-02:30 (commit) | `<~>` |
| VirtualDrivers/Virtual-Display-Driver | default branch; last push 2026-09-19T09:06-02:30 | 2026-09-19T09:06-02:30 | MIT (https://api.github.com/repos/VirtualDrivers/Virtual-Display-Driver, field `license.spdx_id`) |
| VirtualDrivers/Virtual-Driver-Control | default branch `main`; last push 2026-06-12T19:55-02:30 | 2026-06-12T19:55-02:30 | none (GitHub returns `license: null`) |

Sunshine's own release files are named `Sunshine-Windows-AMD64-installer.msi` and `Sunshine-Windows-ARM64-installer.msi`. The Flathub app ID is `dev.lizardbyte.app.Sunshine`.

---

## 1. Silent install and setup of Sunshine

### 1.1 Windows: the MSI and its silent path

- The release MSI is `https://github.com/LizardByte/Sunshine/releases/download/v2026.914.233613/Sunshine-Windows-AMD64-installer.msi`. Its SHA-256 is `1D7FED8BEECD5889DC7FF14CF9F42D6D38F37C3066C13C6C2A5F4E91847E0CCF`. Source: winget manifest `https://github.com/microsoft/winget-pkgs/blob/master/manifests/l/LizardByte/Sunshine/2026.914.233613/LizardByte.Sunshine.installer.yaml` (manifest `ReleaseDate` 2026-09-15; branch ref, not pinned to a commit `<~>`).
- The winget manifest sets `InstallerType: wix`, `Scope: machine`, and `DefaultInstallLocation: '%ProgramFiles%/./Sunshine'`. Source: same manifest.
- A silent install is `msiexec /i "Sunshine-Windows-AMD64-installer.msi" /qn /l*v install.log`. The `/q n` option means no UI. Source: `https://learn.microsoft.com/en-us/windows/win32/msi/command-line-options` (page updated 2025-11-25T19:06-02:30).
- The MSI adds two deferred custom actions. Each runs `sunshine-setup.ps1 -Action install`. The silent variant adds `-Silent` and runs when `UILevel <= 3`. Source: `https://github.com/LizardByte/Sunshine/blob/v2026.914.233613/cmake/packaging/wix_resources/sunshine-installer.wxs` (2026-09-14T22:47-02:30). Whether `/qn` takes the silent branch is inferred from the wxs comment `<~>`.
- The install script runs six steps. It resets permissions on the install folder with `icacls /reset`. It adds the install folder to PATH. It migrates config. It adds firewall rules. It installs the service. It sets autostart. Source: `https://github.com/LizardByte/Sunshine/blob/v2026.914.233613/src_assets/windows/misc/sunshine-setup.ps1` (install branch, about lines 282-430; 2026-09-14T22:47-02:30).
- Firewall rules are per program path. The script runs `netsh advfirewall firewall add rule name=Sunshine dir=in action=allow protocol=tcp|udp program="<install>\sunshine.exe"`. Source: `https://github.com/LizardByte/Sunshine/blob/v2026.914.233613/src_assets/windows/misc/firewall/add-firewall-rule.bat` (2026-09-14T22:47-02:30). The companion needs its own rule for its own program path and for mDNS `<?>`.
- The service is `SunshineService`. Its binary is `tools\sunshinesvc.exe`. It starts on demand by default and is set to auto by `autostart-service.bat` (`sc config SunshineService start= auto`). Source: `https://github.com/LizardByte/Sunshine/blob/v2026.914.233613/src_assets/windows/misc/service/install-service.bat` and `.../autostart/autostart-service.bat` (2026-09-14T22:47-02:30).
- `sunshinesvc` runs with a duplicate of the LocalSystem token. It starts `Sunshine.exe` in the active console session with `CreateProcessAsUserW`. Source: `https://github.com/LizardByte/Sunshine/blob/v2026.914.233613/tools/sunshinesvc.cpp` (about lines 104, 251-273; 2026-09-14T22:47-02:30). So the streaming process runs in the user session, and the service runs in session 0.

### 1.2 Linux: Flatpak, user service, and one privileged step

- The Flathub repo is `https://github.com/flathub/dev.lizardbyte.app.Sunshine`. It is not archived. Its last push was 2026-09-15T00:30-02:30. Source: GitHub API for that repo (fetched 2026-10-09T19:12-02:30).
- The documented install is `flatpak install --system flathub dev.lizardbyte.app.Sunshine`. Source: `https://github.com/LizardByte/Sunshine/blob/v2026.914.233613/docs/getting_started.md` (install section; 2026-09-14T22:47-02:30).
- The Flatpak grants `--device=all`, `--filesystem=home`, `--socket=wayland`, `--socket=fallback-x11`, `--socket=pulseaudio`, `--system-talk-name=org.freedesktop.Avahi`, `--talk-name=org.freedesktop.Flatpak`, and `--talk-name=org.kde.StatusNotifierWatcher`. Source: `https://github.com/LizardByte/Sunshine/blob/v2026.914.233613/packaging/linux/flatpak/dev.lizardbyte.app.Sunshine.yml` (finish-args; 2026-09-14T22:47-02:30).
- The post-install script is `flatpak run --command=additional-install.sh dev.lizardbyte.app.Sunshine`. It copies the user unit to `~/.config/systemd/user/app-dev.lizardbyte.app.Sunshine.service`. It also runs `flatpak-spawn --host pkexec` to write `/etc/modules-load.d/60-sunshine.conf`, run `modprobe uhid`, write `/etc/udev/rules.d/60-sunshine.rules`, and reload udev. Source: `https://github.com/LizardByte/Sunshine/blob/v2026.914.233613/packaging/linux/flatpak/scripts/additional-install.sh` (2026-09-14T22:47-02:30).
- The `pkexec` steps need a privilege prompt on the host. So this step cannot be fully silent on a default system `<!>`. A polkit rule could remove the prompt, but that is a system change and needs the user's approval. Source for the commands: the same script.
- The udev rules are: `/dev/uinput` with `GROUP="input"`, `MODE="0660"`, and `TAG+="uaccess"`. `/dev/uhid` gets the same group and mode. hidraw nodes import `HID_*` from the parent. Source: `https://github.com/LizardByte/Sunshine/blob/v2026.914.233613/src_assets/linux/misc/60-sunshine.rules` (2026-09-14T22:47-02:30).
- The user unit is `app-dev.lizardbyte.app.Sunshine`. The docs also alias it as `sunshine.service`. Start it with `systemctl --user --now enable app-dev.lizardbyte.app.Sunshine`. Source: `docs/getting_started.md` at the same tag.
- For KMS capture, Sunshine needs `setcap cap_sys_admin,cap_sys_nice+p`. The docs say post-install scripts handle this for distro packages. Source: `https://github.com/LizardByte/Sunshine/blob/v2026.914.233613/docs/building.md` (about lines 67-72; 2026-09-14T22:47-02:30). The Flatpak's KMS status is not stated `<?>`. The AppImage docs say it does not support KMS, so KMS is not a v1 path.
- Sunshine's KWin capture lists KWin outputs by name and selects one with `output_name`. Source: `https://github.com/LizardByte/Sunshine/blob/v2026.914.233613/src/platform/linux/kwingrab.cpp` (`get_output_names` about line 352; `start` about lines 387-396; 2026-09-14T22:47-02:30).

### 1.3 Credentials and config locations

- `sunshine --creds <username> <password>` sets the Web UI login. The help text is in `src/logging.cpp` (line 272). The handler is `src/entry_handler.cpp` (`args::creds`, lines 42-48). It saves through `http::save_user_creds(config::sunshine.credentials_file, ...)`. Source: `https://github.com/LizardByte/Sunshine/blob/v2026.914.233613/src/entry_handler.cpp` (2026-09-14T22:47-02:30).
- The credentials file is the state file `sunshine_state.json`. Source: `https://github.com/LizardByte/Sunshine/blob/v2026.914.233613/src/config.cpp` (`file_state` about line 836; `credentials_file` assigned about line 1733; 2026-09-14T22:47-02:30).
- The config file is `sunshine.conf`, the log is `sunshine.log`, and the apps file is `apps.json`. All three sit under `appdata()`. Source: same file (lines 61, 883, 888).
- Windows `appdata()` is `<directory of sunshine.exe>\config`. For the default MSI path that is `C:\Program Files\Sunshine\config` (inferred from the winget default location). Source: `https://github.com/LizardByte/Sunshine/blob/v2026.914.233613/src/platform/windows/misc.cpp` (`appdata`, about lines 147-151).
- Linux `appdata()` is `$XDG_CONFIG_HOME/sunshine`, or `~/.config/sunshine` when `XDG_CONFIG_HOME` is unset. It also has a one-time migration step. Source: `https://github.com/LizardByte/Sunshine/blob/v2026.914.233613/src/platform/linux/misc.cpp` (about lines 279-315).
- macOS `appdata()` is `~/.config/sunshine`. Source: `https://github.com/LizardByte/Sunshine/blob/v2026.914.233613/src/platform/macos/misc.mm` (about lines 105-111).
- The Flatpak config path is not confirmed `<?>`. Test it on a real install, because the Flatpak sandbox may set `XDG_CONFIG_HOME` to a different folder.
- The Web API is HTTPS on port 47990. The confighttp port is the base port plus 1. The base is 47989. Source: `src/confighttp.h` (`PORT_HTTPS = 1`, line 29) and `src/config.cpp` (base port 47989, line 885), at the same tag.
- Web API auth is HTTP Basic over HTTPS. The password is checked against a salted hash. If no username is set, the server redirects to `/welcome`. Source: `src/confighttp.cpp` (function `authenticate`; 2026-09-14T22:47-02:30).
- `authenticate` denies a client whose class is above `origin_web_ui_allowed`. Source: `src/confighttp.cpp` (`authenticate`). The address classes are set in `src/network.cpp` (about line 200). That loopback falls in the allowed class under the default setting is `<~>`.
- Every POST on the Web API needs a JSON content type, an authenticated session, and a CSRF token. The token comes from `GET /api/csrf-token`. Source: `src/confighttp.cpp` (`check_content_type`, `validate_csrf_token`, and the route table near line 2371).
- The companion's TLS trust for Sunshine's self-signed certificate is not decided `<?>`. The choice is to pin the certificate in the appdata folder, or to trust a custom root. Test this.

---

## 2. Local config API (port 47990)

Source for every route below: `https://github.com/LizardByte/Sunshine/blob/v2026.914.233613/src/confighttp.cpp` (route table at about lines 2357-2382; 2026-09-14T22:47-02:30).

| Need | Route | Notes |
|---|---|---|
| CSRF token | `GET /api/csrf-token` | Required before any POST. |
| Pairing: list pending | `GET /api/pin` | Returns `pairings: [{id, name, address}]`. |
| Pairing: submit PIN | `POST /api/pin` | Body: `{"name", "pairing_id" (32 hex), "pin" (4 digits)}`. Calls `nvhttp::pin`. |
| Pairing: cancel | `DELETE /api/pin` | Body: `{"pairing_id"}`. |
| Apps: list | `GET /api/apps` | |
| Apps: add or edit | `POST /api/apps` | Use `index: -1` to add. Fields: `name`, `output`, `cmd`, `prep-cmd`, `detached`, `image-path`. Source: `confighttp.cpp` (doc block about lines 1085-1108). |
| Apps: delete | `DELETE /api/apps/{id}` | |
| Current app: stop | `POST /api/apps/close` | Closes the running app. |
| Restart | `POST /api/restart` | Auth and CSRF required. Calls `platf::restart()`, which may not return. |
| Clients | `GET /api/clients/list`, `POST /api/clients/unpair`, `POST /api/clients/unpair-all` | |
| Config | `GET /api/config`, `POST /api/config` | |
| Password | `POST /api/password` | |

Pairing behaviour, from `https://github.com/LizardByte/Sunshine/blob/v2026.914.233613/src/nvhttp.cpp` and `src/nvhttp.h` (2026-09-14T22:47-02:30):

- A client calls the HTTP `/pair` endpoint on port 47989 with `uniqueid`, `salt`, `devicename`, and `clientcert`.
- The server creates a random 32-hex pairing ID. It waits for the PIN.
- A pending pairing expires after 5 minutes (`PAIRING_SESSION_TIMEOUT`, `nvhttp.h`).
- The server keeps at most 32 pending pairings (`MAX_PENDING_PAIRING_SESSIONS`, `nvhttp.h`).

Current app, from `src/nvhttp.cpp` (serverinfo, about lines 1264-1267):

- There is no GET route for the current app in the config API.
- The serverinfo XML carries `root.currentgame` (the running app ID, `0` if none) and `root.state` (`SUNSHINE_SERVER_BUSY` or `SUNSHINE_SERVER_FREE`).
- `currentgame` tracks only apps Sunshine launched. It does not track the real foreground window. This matches the note in `docs/companion/DESIGN.md` (internal observation, 2026-10-09).

Recommendation for `SunshineApi`: use the calls above. Read the current app from serverinfo. Do not treat `currentgame` as the truth for the foreground app (section 5).

---

## 3. Virtual display

### 3.1 Windows: does Sunshine have a virtual display?

- Sunshine has no virtual display driver code. A search of `src/` for `IddCx`, `Virtual-Display-Driver`, and `VirtualDisplay` found nothing. The text "virtual display" appears only in one HDR note in `docs/configuration.md` and in locale strings. Source: `https://github.com/LizardByte/Sunshine/tree/v2026.914.233613` (2026-09-14T22:47-02:30).
- Sunshine has display options that apply to Windows only. There are ten `dd_*` sections in `docs/configuration.md`, and each says "Applies to Windows only". Source: `https://github.com/LizardByte/Sunshine/blob/v2026.914.233613/docs/configuration.md` (sections from about line 1093; 2026-09-14T22:47-02:30).
- `dd_configuration_option` chooses one mode: `disabled`, `verify_only`, `ensure_active` (activate the display if it is inactive), `ensure_primary`, or `ensure_only_display` (also disables all others). Source: same file.
- `dd_resolution_option` chooses `disabled`, `auto` (match the client's request), or `manual`. Source: same file (about line 1138).
- `dd_config_revert_on_disconnect` reverts the display configuration when all clients disconnect. It does not uninstall or disable any driver. Source: same file (about line 1338).
- `output_name` picks the display by device ID. The Windows example is a GUID. Source: `docs/configuration.md` (`output_name`, about line 978). The code sets the device ID from `output_name` (`src/display_device.cpp`, about line 932).

What `HOST_SETUP.md` claims for VDD: "Sunshine enables the VDD on stream start, sets it to the resolution Glimmer asked for, and tears it down on disconnect."

- Partly supported. Sunshine can activate a display by device ID (`ensure_active`), set a resolution (`auto`), and revert on disconnect. Sources above.
- Not supported. Sunshine does not install, enable, or remove the VDD driver. The driver is only a display device to Sunshine.
- Whether `ensure_active` activates a VDD on a real machine is untested `<?>`.

### 3.2 Windows: the Virtual Display Driver project

- The VDD project is `https://github.com/VirtualDrivers/Virtual-Display-Driver`. Its license is MIT (GitHub license field). Last push 2026-09-19T09:06-02:30. Source: GitHub API (fetched 2026-10-09T19:12-02:30).
- The README says the Windows driver is signed. Free signing comes from SignPath.io, and the certificate is by SignPath Foundation. Source: the project README (default branch, fetched 2026-10-09T19:12-02:30).
- The README says to install with the Virtual Driver Control app. The `winget` line is `winget install --id=VirtualDrivers.Virtual-Display-Driver -e`. Source: the same README.
- The winget package is a portable zip of the control app (`VDD Control.exe`, version 25.7.23). It is not a silent driver install. Source: `https://github.com/microsoft/winget-pkgs/blob/master/manifests/v/VirtualDrivers/Virtual-Display-Driver/25.7.23/` (manifest date 2025-07-23; branch ref `<~>`).
- The latest driver release is `Virtual Display Driver (25.5.2, with Beta Control App)`, published 2025-05-03T02:08-02:30. The control app's own release, `25.7.23`, is marked `Latest` and was published 2025-07-23T13:20-02:30. Source: `https://github.com/VirtualDrivers/Virtual-Display-Driver/releases` (fetched 2026-10-09T19:12-02:30).
- `<!>` The newest driver release is more than a year old. Check that it works on current Windows 11 and with current GPU drivers before v1.
- Driver install steps in Virtual Driver Control: an elevated PowerShell script trusts the signer (TrustedPublisher), runs `pnputil /add-driver`, and creates the root device with nefcon. The script pins nefcon v1.17.40. Source: `https://github.com/VirtualDrivers/Virtual-Driver-Control/blob/main/VirtualDriverControl/src/main/services/installer-service.ts` (about lines 15-22, 109-111, 278-283; fetched 2026-10-09T19:12-02:30).
- The control app repo has no license (`license: null`). Do not copy its code `<!>`. Re-implement the documented steps, and use the MIT-licensed nefcon (`https://github.com/nefarius/nefcon`, MIT, last push 2026-10-09T16:20-02:30).
- Whether that install runs with no UI and no reboot prompt is untested `<?>`.

### 3.3 Linux KDE: virtual outputs and resizing

- Sunshine has no mode-setting code for Linux. A search of `src/platform/linux` and `src/display_device.cpp` for resize, `setMode`, modeset, `xrandr`, and `RRSetCrtcConfig` found only buffer resizes. Source: `https://github.com/LizardByte/Sunshine/tree/v2026.914.233613/src/platform/linux` (2026-09-14T22:47-02:30).
- The `dd_*` options are Windows only (section 3.1).
- `<⊥>` Contradiction: `docs/HOST_SETUP.md` says "a current Sunshine resizes the session to the requested mode on connect and restores it on disconnect" on Linux. The Sunshine docs and source at this tag do not support that. Record it as a fragment and fix the doc (section "Repo docs to fix").
- KWin has a virtual backend. `kwin_wayland --virtual` renders to a virtual framebuffer. `--output-count N` sets how many outputs to create, with a default of 1. Both are set at startup. Source: `https://github.com/KDE/kwin/blob/c55a16fcc589c18f5edac1907b6136d80f40bbdc/src/main_wayland.cpp` (about lines 353, 372-375, 510-511, 554-580; commit 2026-10-08T23:24-02:30).
- The virtual backend exposes `addOutput` and `setVirtualOutputs`. Source: `https://github.com/KDE/kwin/blob/c55a16fcc589c18f5edac1907b6136d80f40bbdc/src/backends/virtual/virtual_backend.h` (lines 52-53; same commit).
- A search of the KWin source at that commit found no D-Bus or Wayland call that creates or removes a virtual output while KWin runs `<?>`. The search covered `VirtualOutput` in `src/`. A runtime-created virtual output would need a new KWin feature or a different approach. Test on KDE Plasma 6.
- Revised 2026-10-10: this recommendation is superseded. The KWin source search above missed `krfb-virtualmonitor`, which makes a runtime output through a userspace tool. The founder's PC runs it. Sunshine captures it with `capture = kwin`. Build: `companion/src/linux_install.rs`. Sources and open items are in the PR; the clean-PC test is still open.

---

## 4. Keep the display awake and the screen unlocked

### 4.1 Windows

What Sunshine does today:

- During capture, Sunshine calls `SetThreadExecutionState(ES_CONTINUOUS | ES_DISPLAY_REQUIRED)` and clears it on exit with a fail guard. Source: `https://github.com/LizardByte/Sunshine/blob/v2026.914.233613/src/platform/windows/display_base.cpp` (about lines 243-249; 2026-09-14T22:47-02:30).
- If no output is found, it calls `SetThreadExecutionState(ES_DISPLAY_REQUIRED)` and waits 500 ms, to wake the display. Source: same file (about lines 548-553).

Win32 facts:

- `SetThreadExecutionState` resets the display idle timer with `ES_DISPLAY_REQUIRED`. With `ES_CONTINUOUS` the state stays until a later call clears it. Source: `https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-setthreadexecutionstate` (page updated 2025-07-01T16:11-02:30).
- The same page says the function "does not stop the screen saver from executing." It also says it cannot stop the user from putting the computer to sleep. Source: same page.
- `PowerSetRequest` with `PowerRequestDisplayRequired` must be paired with `PowerRequestSystemRequired`. Requests end on user-started sleep (power button, lid, Start menu). Create the request with a `REASON_CONTEXT` string. Source: `https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-powersetrequest` (updated 2025-07-01T16:11-02:30).
- `PowerCreateRequest` creates the request object. Clean up with `CloseHandle` before the process exits or the service stops. Source: `https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-powercreaterequest` (updated 2025-07-01T16:11-02:30).

Session 0:

- The MS pages do not discuss services or session 0 `<?>`.
- The design keeps the awake guard in the user-session companion, not in the LocalSystem service. That fits `sunshinesvc` starting Sunshine in the console session (section 1.1). Test the awake guard from a service and from a user process, to be sure.

Unlocked:

- None of these APIs unlocks the screen or stops a lock.
- `<!>` `DESIGN.md` says the awake seam keeps the PC "awake and unlocked". The awake seam cannot do the unlock part. Any lock prevention is a separate system or policy setting. That is a security decision. Ask the user before the companion changes any lock settings.

### 4.2 Linux KDE Wayland

What Sunshine does today:

- Sunshine does not call `org.freedesktop.ScreenSaver`, `org.freedesktop.login1`, or any `Inhibit` method. The only D-Bus use is the XDG portal code (`portalgrab.cpp`). Source: `https://github.com/LizardByte/Sunshine/tree/v2026.914.233613/src/platform/linux` (2026-09-14T22:47-02:30).

kscreenlocker (KDE's lock screen):

- `org.freedesktop.ScreenSaver.Inhibit` maps to `Interface::Inhibit`. It creates a `PowerInhibitor`, asks the PolicyAgent for an inhibition, and calls `KSldApp::inhibit()`. Source: `https://github.com/KDE/kscreenlocker/blob/e77531aef569db551d0fd1e18b5253bdd1e1ca3e/interface.cpp` (about line 152; commit date `<~>`).
- `KSldApp::inhibit()` increments an inhibit counter. `updateIdleTimeout()` removes the idle auto-lock timeout while the counter is above zero. Source: `https://github.com/KDE/kscreenlocker/blob/e77531aef569db551d0fd1e18b5253bdd1e1ca3e/ksldapp.cpp` (`inhibit` about lines 471-476; `isInhibited` about lines 370-372; `updateIdleTimeout` about lines 485-495).
- The auto-lock settings are `autolock` and `timeout`. Source: `https://github.com/KDE/kscreenlocker/blob/e77531aef569db551d0fd1e18b5253bdd1e1ca3e/settings/kscreenlockersettings.kcfg`.
- Whether an inhibit stops a lock that is already due is not confirmed `<?>`. Line 144 of `ksldapp.cpp` checks `isInhibited()`, but I did not read that branch.

PowerDevil (KDE's power daemon):

- `org.freedesktop.PowerManagement.Inhibit` maps to the `InterruptSession` policy. The comment says "Inhibit here means we cannot interrupt the session." Source: `https://github.com/KDE/powerdevil/blob/61d4b551c452d5164cafc50c4b15dca2526c2431/daemon/powerdevilfdoconnector.cpp` (about lines 84-91).
- PowerDevil has a DPMS action (`daemon/actions/bundled/dpms.cpp`). Whether any inhibit stops display-off is not confirmed `<?>`. Source: same commit.

systemd-logind:

- Lock types are `idle`, `sleep`, `shutdown`, `handle-power-key`, and `handle-lid-switch`. Modes are `block` (blocks until released) and `delay` (temporary). Releasing happens when the returned file descriptor closes. Source: `https://systemd.io/INHIBITOR_LOCKS/` (no page date `<~>`).

XDG desktop portal (for sandboxed companions):

- `org.freedesktop.portal.Inhibit` flags are 1 (logout), 2 (user switch), 4 (suspend), and 8 (idle). Remove an inhibit with `Request.Close()`. Source: `https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.Inhibit.html` (no page date `<~>`). The XML is `https://github.com/flatpak/xdg-desktop-portal/blob/main/data/org.freedesktop.portal.Inhibit.xml` (`<~>` commit not pinned).

Recommendation for the Linux awake seam:

- While leases are fresh, hold `org.freedesktop.ScreenSaver.Inhibit` from the user session. This stops the KDE idle lock.
- Also hold a login1 `Inhibit("idle", ..., "block")`, and keep its file descriptor open. Release both when the last lease ends.
- Whether these holds stop DPMS display-off on KDE is `<?>`. Test it.
- The unlock part is the same decision as on Windows (section 4.1).

---

## 5. The real foreground app

### 5.1 Windows

- `GetForegroundWindow` returns the window the user is working in. The return value can be `NULL` while a window is losing activation. Source: `https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getforegroundwindow` (updated 2025-07-01T16:11-02:30).
- Mapping the window to its process (`GetWindowThreadProcessId`, `QueryFullProcessImageNameW`) was not fetched in this pass `<~>`. Check these two calls with their MS docs before building.
- Some apps (for example UWP games) may show a host process such as `ApplicationFrameHost.exe`. The mapping for those windows is `<?>`.

### 5.2 KDE Wayland: KWin scripting

KWin's scripting D-Bus entry point (commit `c55a16fcc589c18f5edac1907b6136d80f40bbdc`, 2026-10-08T23:24-02:30):

- The scripting object is exported at `/Scripting`, with interface `org.kde.kwin.Scripting`. Sources: `https://github.com/KDE/kwin/blob/c55a16fcc589c18f5edac1907b6136d80f40bbdc/src/scripting/scripting.cpp` (about line 681) and `.../scripting.h` (`Q_CLASSINFO("D-Bus Interface", "org.kde.kwin.Scripting")`, line 317).
- `loadScript(filePath, pluginName)` is `Q_SCRIPTABLE Q_INVOKABLE int`, and `unloadScript(pluginName)` is also scriptable. Source: `.../scripting.h` (about lines 333-336).
- A loaded script runs through `run()` on `/Scripting/Script<N>`. Source: `.../scripting.h` (`Q_SCRIPTABLE void run()`, about line 264).
- `workspace.activeWindow` is `WorkspaceWrapper::activeWindow()`. Source: `https://github.com/KDE/kwin/blob/c55a16fcc589c18f5edac1907b6136d80f40bbdc/src/scripting/workspace_wrapper.cpp` (about lines 110-112).
- `Window.pid` is a constant property: `Q_PROPERTY(int pid READ pid CONSTANT)`. Source: `https://github.com/KDE/kwin/blob/c55a16fcc589c18f5edac1907b6136d80f40bbdc/src/window.h` (line 396). Also available: `resourceClass` (line 191) and `desktopFileName` (line 713).
- A KWin script can call D-Bus with `callDBus(service, path, interface, method, ...)`. Source: `.../scripting.h` (`callDBus`, about lines 115-116).

Plan for the Linux foreground seam: the companion loads a small KWin script on start. The script reports `activeWindow.pid`, `resourceClass`, and `desktopFileName` on focus change, using `callDBus` to the companion's bus name. The companion maps the pid to a Sunshine app.

- `<?>` A Flatpak-sandboxed companion probably cannot read host `/proc/<pid>/exe` (the PID namespace). Recommend a host user service for the companion. Test before deciding.

---

## 6. LAN discovery

- Sunshine advertises `_nvstream._tcp`. The constant is `SERVICE_TYPE` in `src/platform/common.h` (lines 1286-1287). Source: `https://github.com/LizardByte/Sunshine/blob/v2026.914.233613/src/platform/common.h` (2026-09-14T22:47-02:30).
- The instance name is built from the hostname by `mdns_instance_name`. It truncates to 63 characters, turns spaces into dashes, stops at the first other invalid character, and falls back to `Sunshine`. Source: `https://github.com/LizardByte/Sunshine/blob/v2026.914.233613/src/network.cpp` (about lines 258-285).
- The advertised port is `nvhttp::PORT_HTTP`, which is the base port 47989. Source: `src/nvhttp.h` (`PORT_HTTP = 0`, line 47; base port in `src/config.cpp` line 885).
- Linux (avahi): `avahi_entry_group_add_service` is called with `SERVICE_TYPE`, the port, and a `nullptr` TXT list. Source: `https://github.com/LizardByte/Sunshine/blob/v2026.914.233613/src/platform/linux/publish.cpp` (about lines 455-475).
- Windows: `DnsServiceRegister` is loaded at run time. The host name is `<hostname>.local`. The TXT list has one empty string, which the code calls RFC 1035-compliant. Source: `https://github.com/LizardByte/Sunshine/blob/v2026.914.233613/src/platform/windows/publish.cpp` (about lines 151-190).
- macOS uses `DNSServiceRegister`. Source: `src/platform/macos/publish.cpp` (same tag).
- Sunshine's Flatpak needs `--system-talk-name=org.freedesktop.Avahi` to register on avahi (section 1.2).
- The companion can use its own type, `_eventhorizon._tcp`, as in `DESIGN.md`. It does not clash with `_nvstream._tcp`.
- The Rust crate `mdns-sd` is at version 0.21.5, with an Apache-2.0 license, last updated 2026-10-05T03:01-02:30. Source: `https://crates.io/api/v1/crates/mdns-sd` and `https://github.com/keepsimple1/mdns-sd` (fetched 2026-10-09T19:12-02:30).
- The DNS-SD TXT rules (key length, 255-byte limit) were not fetched `<~>`.
- A Windows firewall rule for the companion's mDNS traffic is not yet defined `<?>`.

---

## 7. Packaging and UX

### 7.1 Tray, window, and the Allow prompt

- `tray-icon` 0.26.1 (Apache-2.0; updated 2026-10-07T13:29-02:30). It supports Windows, Linux, and FreeBSD. On Linux it uses either the AppIndicator (GTK 3) backend, enabled by default, or the KSNI StatusNotifierItem D-Bus backend. Windows and AppIndicator need an event loop on the thread. Source: `https://github.com/tauri-apps/tray-icon` (README, fetched 2026-10-09T19:12-02:30).
- `tao` 0.37.1 (Apache-2.0; updated 2026-09-26T08:19-02:30) is the window and event-loop crate that goes with it. Source: `https://crates.io/crates/tao`.
- Linux Allow prompt: `org.freedesktop.Notifications.Notify` takes an `actions` list of key and label pairs. It emits `ActionInvoked(id, action_key)` when a button is clicked. It emits `NotificationClosed(id, reason)` with reasons 1 (expired), 2 (dismissed by the user), 3 (closed by `CloseNotification`), and 4 (reserved). Source: `http://specifications.freedesktop.org/notification/latest/protocol.html` (spec version 1.3, page date 2024-08-18).
- `notify-rust` 4.18.2 (updated 2026-10-07T14:36-02:30) is the Rust client for that spec. Source: `https://crates.io/crates/notify-rust`.
- `rfd` 0.17.2 (updated 2026-01-12T18:27-02:30) is a native dialog crate, useful as a fallback. Its platform coverage was not checked `<~>`. Source: `https://crates.io/crates/rfd`.
- The `windows` crate 0.62.2 (updated 2025-10-06T16:49-02:30) gives the Win32 calls in sections 4.1 and 5.1. Source: `https://crates.io/crates/windows`.
- `zbus` 5.19.0 (updated 2026-08-09T15:18-02:30) is the Rust D-Bus crate for the Linux adapters. Source: `https://crates.io/crates/zbus`.
- `windows-service` 0.8.1 (updated 2026-05-08T11:05-02:30) is only needed if the companion runs as a Windows service. The design says it should not `<~>`. Source: `https://crates.io/crates/windows-service`.

### 7.2 Windows installer

- `cargo-dist` 0.32.0 (updated 2026-05-22T03:28-02:30) builds an MSI with WiX Toolset v3.14.1. The docs say WiX v4 is not supported. It can sign the MSI with SignTool and the Windows SDK. It has no silent-install or custom-action section. It has an "unmanaged" mode that allows hand edits to `main.wxs`. Source: `https://axodotdev.github.io/cargo-dist/book/installers/msi.html` (page date `<~>`).
- `cargo-wix` 0.3.9 (updated 2025-03-13T17:20-02:30) is the older alternative. Its README was not read `<~>`. Source: `https://crates.io/crates/cargo-wix`.
- Chaining Sunshine's MSI: the simplest path is for the companion's installer to run `msiexec /i <Sunshine MSI> /qn /norestart` as a step, then check the exit code. The MSI exit codes (for example 3010 for reboot) were not read `<~>`. A WiX Burn bundle could chain packages, but I did not read its docs `<~>`.
- NSIS was not researched `<~>`.

### 7.3 SmartScreen

- SmartScreen checks a downloaded app against known-bad lists. It also checks against "a list of files that are well known and downloaded frequently". A file not on that list shows a warning. Source: `https://learn.microsoft.com/en-us/windows/security/operating-system-security/virus-and-threat-protection/microsoft-defender-smartscreen/` (page ms.date 2026-04-23; updated 2026-04-25T01:07-02:30).
- The reputation check covers "the digital signature used to sign a file". "If there's no reputation, the item is marked as a higher risk and presents a warning." Source: same page.
- Result: an unsigned installer shows warnings for a long time. A signed installer shows fewer warnings, but reputation still builds over time. Plan for warnings in v1 either way.

### 7.4 Code signing options

- Azure Artifact Signing (renamed from Trusted Signing; the billing API still uses the name "Trusted Signing"). The Basic tier is 9.99 USD per account per month, with 5,000 signatures a month. Premium is 99.99 USD per account per month, with 100,000 signatures. The overage is 0.005 USD per signature. Source: `https://prices.azure.com/api/retail/prices?$filter=serviceName%20eq%20'Trusted%20Signing'&currencyCode=USD` (first-party API, retrieved 2026-10-09T19:12-02:30). These meters have `effectiveStartDate` 2024-05-31T21:30-02:30 (2024-06-01T00:00Z). The pricing page `https://azure.microsoft.com/en-us/pricing/details/artifact-signing/` renders its numbers as placeholders, so the API is the source.
- Identity validation and eligibility by country were not researched `<?>`.
- SignPath Foundation: free code signing for open-source projects. The requirements are an OSI-approved license with no dual licensing, an active and released project, documentation, and "a certain verifiable reputation" for executables. The certificate is issued to SignPath Foundation, which becomes the publisher. Source: `https://signpath.org/terms.html` (page marked as a draft; fetched 2026-10-09T19:12-02:30).
- The companion is GPL-3 and public, so it meets the license rule. The reputation rule is not defined on the page `<?>`. The VDD project uses SignPath (section 3.2), which is evidence the path works for a driver project.

---

## 8. Licensing

- Sunshine is GPL-3.0. Source: `https://github.com/LizardByte/Sunshine/blob/v2026.914.233613/LICENSE` (2026-09-14T22:47-02:30).
- Downloading Sunshine's MSI from LizardByte's release URL at install time means the companion does not convey Sunshine's object code. This is my reading `<~>`, and a lawyer should confirm it.
- If the companion bundles the Sunshine MSI or its files inside its own installer, it conveys object code. GPL-3 section 6 then requires that you "convey the machine-readable Corresponding Source" in one of the listed ways, such as a written offer or the source itself. Source: the same LICENSE file, section 6 ("Conveying Non-Source Forms").
- A GPL-3 companion is compatible with a GPL-3 Sunshine.
- VDD is MIT. Source: GitHub license field for `VirtualDrivers/Virtual-Display-Driver` (fetched 2026-10-09T19:12-02:30). nefcon is MIT. Source: `https://github.com/nefarius/nefcon` (fetched 2026-10-09T19:12-02:30).
- Virtual Driver Control has no license. `<!>` Do not copy its code. The re-implementation in section 3.2 uses the documented steps.
- Sunshine's Virtual HID Driver is a paid optional upgrade. v1 does not need it. Source: `docs/getting_started.md` (Windows section) at the same tag.

---

## Recommendations for v1

Each line is the simplest path for one question. Open items are `<?>`.

1. **Sunshine install (Windows).** Download the pinned MSI, check its SHA-256, then run `msiexec /i ... /qn`. Set credentials with `sunshine.exe --creds`. Check that `SunshineService` runs. (Sections 1.1, 1.3.)
2. **Sunshine install (Linux).** Install the Flathub app. Run `additional-install.sh` once. Its `pkexec` prompt cannot be silent, so v1 has one visible step on Linux. `<!>` (Section 1.2.)
3. **Pairing.** Poll `GET /api/pin`. When the user clicks Allow, `POST /api/pin` with the pairing ID and the PIN. Sunshine gives 5 minutes. (Section 2.)
4. **Keep awake.** Windows: `SetThreadExecutionState(ES_CONTINUOUS | ES_DISPLAY_REQUIRED | ES_SYSTEM_REQUIRED)` from the user-session process while leases are fresh. KDE: hold `ScreenSaver.Inhibit` and a login1 idle inhibit. (Section 4.)
5. **Unlocked.** Not solved by the awake seam. Ask the user which lock behaviour they accept before any change. `<!>` (Section 4.1.)
6. **Foreground app.** Windows: `GetForegroundWindow`, then the process image (verify the two extra calls). KDE: load a KWin script that reports `activeWindow.pid`, `resourceClass`, and `desktopFileName` through `callDBus`. (Section 5.)
7. **Virtual display (Windows).** Install the MIT-licensed VDD driver with the documented steps (signer trust, `pnputil`, nefcon). Test `dd_configuration_option = ensure_active` against it. Check the driver's age first. `<!>` (Section 3.2.)
8. **Virtual display (Linux).** None for v1. Use the existing output. Fix `HOST_SETUP.md` (`<⊥>`). (Section 3.3.)
9. **Discovery.** Advertise `_eventhorizon._tcp` with `mdns-sd` 0.21.5. Leave `_nvstream._tcp` to Sunshine. (Section 6.)
10. **Packaging and signing.** Windows: a cargo-dist 0.32.0 MSI (WiX 3.14.1) that runs the Sunshine MSI as a step. Sign with Artifact Signing Basic (9.99 USD a month) or SignPath (free, if accepted). Expect SmartScreen warnings. Linux: run the companion as a host systemd user service, not in Flatpak `<?>`.

---

## Repo docs to fix

- `docs/HOST_SETUP.md`, Linux section: "A current Sunshine resizes the session" is `<⊥>` against section 3.3. Fix or remove the claim.
- `docs/HOST_SETUP.md`, Windows section: "Sunshine enables the VDD on stream start … tears it down on disconnect" is partly supported. Sunshine activates and reverts displays but does not manage the driver (section 3.1). Reword it.
- `docs/companion/DESIGN.md`, Awake seam: "keeps the PC awake and unlocked" is `<!>`. The awake seam keeps the PC awake only (section 4.1).
- `docs/companion/DESIGN.md`, Pairing: a 2-minute expiry is the companion's own request timer. Sunshine's pending PIN lasts 5 minutes (section 2). Both can stand, but name them as two timers.

---

## Open questions

- `<?>` 2026-10-09T19:12-02:30 — Does a companion-side awake guard work from a LocalSystem service (session 0) as well as from a user-session process? Source: `https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-setthreadexecutionstate` (silent on services).
- `<?>` 2026-10-09T19:12-02:30 — Does `dd_configuration_option = ensure_active` enable a VDD that Sunshine did not install? Source: `https://github.com/LizardByte/Sunshine/blob/v2026.914.233613/docs/configuration.md` (section `dd_configuration_option`).
- `<?>` 2026-10-09T19:12-02:30 — Can the VDD driver be installed silently (no UI, no reboot prompt) with the pnputil and nefcon steps? Source: `https://github.com/VirtualDrivers/Virtual-Driver-Control/blob/main/VirtualDriverControl/src/main/services/installer-service.ts`.
- `<?>` 2026-10-09T19:12-02:30 — Can a KDE Plasma 6 session get a new virtual output at runtime? Source: `https://github.com/KDE/kwin/blob/c55a16fcc589c18f5edac1907b6136d80f40bbdc/src/main_wayland.cpp` (startup-only options).
- `<?>` 2026-10-09T19:12-02:30 — Do KDE's ScreenSaver and login1 inhibits stop DPMS display-off, and do they stop a lock that is already due? Source: `https://github.com/KDE/kscreenlocker/blob/e77531aef569db551d0fd1e18b5253bdd1e1ca3e/ksldapp.cpp` (line 144 branch not read).
- `<?>` 2026-10-09T19:12-02:30 — Can a Flatpak-sandboxed companion read host `/proc/<pid>/exe` for a KWin window pid? Source: none yet (test).
- `<?>` 2026-10-09T19:12-02:30 — What is the Flatpak's Sunshine config folder? Source: `https://github.com/LizardByte/Sunshine/blob/v2026.914.233613/src/platform/linux/misc.cpp` (XDG logic; Flatpak path not read).
- `<?>` 2026-10-09T19:12-02:30 — Which TLS certificate should the companion trust for `https://localhost:47990`? Source: `src/confighttp.cpp` and the cert settings in `src/config.cpp`, not yet read in full.
- `<?>` 2026-10-09T19:12-02:30 — Does the Flatpak Sunshine give KMS capture? Source: `docs/building.md` (setcap note) and the Flatpak manifest (no KMS grant found).
- `<?>` 2026-10-09T19:12-02:30 — Does Fedora Atomic or Bazzite have a supported way to run a host systemd user service for the companion? Source: none yet.
- `<?>` 2026-10-09T19:12-02:30 — What are the identity and eligibility rules for Azure Artifact Signing, and what is SignPath's reputation bar? Source: `https://learn.microsoft.com/en-us/azure/trusted-signing/` (not read) and `https://signpath.org/terms.html`.
- `<?>` 2026-10-09T19:12-02:30 — Which Windows firewall rule does the companion need for mDNS and its own program? Source: `https://github.com/LizardByte/Sunshine/blob/v2026.914.233613/src_assets/windows/misc/firewall/add-firewall-rule.bat` (pattern only).
- `<~>` 2026-10-09T19:12-02:30 — Not yet read: GetWindowThreadProcessId, QueryFullProcessImageNameW, WiX Burn, NSIS, and the MSI exit codes. Source: none yet.
