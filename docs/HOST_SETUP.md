# PC setup: display modes (Sunshine + VDD)

Event Horizon asks the PC for an **exact** `width × height @ refresh`, whatever you
pick in **Settings ▸ Quality**. The presets there are _Sharpest_ (your panel's
own pixel grid), _Balanced_ (half that in each direction), and _Custom_.
Sunshine can only honor a mode the PC can actually present, so the PC's display
has to be able to produce every mode you might request. On Windows that means a
**Virtual Display Driver**; on Linux, a display output that already offers the
mode. Without one, the stream falls back to a wrong size or fails to start.

## Windows: Virtual Display Driver

A headless gaming PC, or one whose real monitor cannot do your Mac's exact mode,
needs a virtual display that can.

1. **Sunshine.** Install a current release:
   <https://github.com/LizardByte/Sunshine>
2. **Virtual Display Driver.** Install from
   <https://github.com/VirtualDrivers/Virtual-Display-Driver> (follow its
   README; it's a signed IDD driver plus a companion app).
3. **Configure the modes.** Copy [`vddsettings.xml`](vddsettings.xml) to the
   path your VDD build reads (the companion app shows it, commonly
   `C:\IddSampleDriver\vdd_settings.xml` or `C:\VirtualDisplayDriver\`). Then:
   - set `<gpu><friendlyname>` to your GPU exactly as Device Manager ▸ Display
     adapters shows it;
   - make sure every resolution and refresh rate you'll pick in Event Horizon has a
     `<resolution>` entry. The sample already covers the common Mac panels plus
     720p, 1080p, 1440p and 4K at 60, 120 and 240 Hz. **Add a block for anything
     missing.**
4. **Let Sunshine switch to it.** Sunshine activates the virtual display and
   sets the mode Event Horizon asked for on stream start, and reverts it on
   disconnect. It does not install or manage the driver itself. To turn the
   driver on and off per stream, add the VDD project's enable and disable
   scripts to Sunshine's “Command Preparations”: enable as the “Do Command”,
   disable as the “Undo Command”.
5. In Event Horizon, pick a resolution and refresh rate that exist in the config
   above.

## Linux: use a mode your output already has

Sunshine's display-mode options are Windows-only; on Linux it captures the
output as it is and does not change its mode. Pick a mode the output already
offers, or add it to the display server:

- **X11**: the mode must exist in `xrandr`. Add any custom Mac mode with
  `xrandr --newmode` plus `--addmode` (or a modeline in your X config), then
  switch the output to it before you stream.
- **Wayland**: set the mode in the compositor (KDE: Display Configuration or
  `kscreen-doctor`). A virtual output that Sunshine streams through
  `output_name` keeps its mode across sessions.

## The one rule

Whatever Event Horizon requests must exist on the PC. Event Horizon accepts any
`640-7680 × 480-4320 @ 30-240`, so if you stream an unusual mode, add it to the
VDD config (Windows) or the display server's mode list (Linux) first.
