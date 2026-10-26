//! Linux install: one run turns this PC into an Event Horizon host. The steps
//! run through the `Commands` and `Files` ports, so tests drive them with fakes.

use crate::virtual_screen::{self, GUARD_SERVICE, HDR_OUTPUT, OUTPUT, SCREEN_SERVICE, Size};
use serde_json::Value;
use std::path::{Path, PathBuf};
use std::time::Duration;

const SUNSHINE_APP: &str = "dev.lizardbyte.app.Sunshine";
pub const SUNSHINE_SERVICE: &str = "app-dev.lizardbyte.app.Sunshine.service";
const SUNSHINE_USER: &str = "eventhorizon";
const SERVICE: &str = "event-horizon-companion.service";
pub const WATCHDOG_SERVICE: &str = "event-horizon-sunshine-watchdog.service";
const VIRTUAL_TRIES: u32 = 15;
const VIRTUAL_WAIT: Duration = Duration::from_secs(1);
const UDEV_RULES: &str = "/etc/udev/rules.d/60-sunshine.rules";
const SCREEN_PASSWORD_FILE: &str = "virtual-screen-vnc";
const PLACE_TRIES: u32 = 40;
const PLACE_EVERY: Duration = Duration::from_millis(250);

/// Runs programs on the PC.
pub trait Commands {
    /// Runs a program with its output shown. Err when it fails.
    fn run(&self, program: &str, args: &[&str]) -> Result<(), String>;
    /// Runs a program and returns its stdout. Err when it fails.
    fn capture(&self, program: &str, args: &[&str]) -> Result<String, String>;
    fn pause(&self, how_long: Duration);
}

/// The PC's files.
pub trait Files {
    fn read(&self, path: &Path) -> Option<String>;
    /// Writes a file, making its folder first.
    fn write(&self, path: &Path, text: &str) -> Result<(), String>;
    fn exists(&self, path: &Path) -> bool;
    /// Makes a file readable by its owner only, where the OS can.
    fn restrict(&self, path: &Path);
    /// Copies a file over `to`, replacing it.
    fn copy(&self, from: &Path, to: &Path) -> Result<(), String>;
}

/// Where things live on this PC, and what its session is.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Layout {
    pub config_dir: PathBuf,
    pub home: PathBuf,
    /// The companion program that is running now.
    pub companion: PathBuf,
    pub path_dirs: Vec<PathBuf>,
    pub session_type: Option<String>,
    pub desktop: Option<String>,
}

impl Layout {
    pub fn from_env(config_dir: &Path, companion: PathBuf) -> Layout {
        let mut session_type = std::env::var("XDG_SESSION_TYPE").ok();
        let mut desktop = std::env::var("XDG_CURRENT_DESKTOP").ok();
        if session_type.is_none() || desktop.is_none() {
            let shown = std::process::Command::new("systemctl")
                .args(["--user", "show-environment"])
                .output()
                .map(|o| String::from_utf8_lossy(&o.stdout).into_owned())
                .unwrap_or_default();
            let (manager_type, manager_desktop) = virtual_screen::session_from_manager(&shown);
            session_type = session_type.or(manager_type);
            desktop = desktop.or(manager_desktop);
        }
        Layout {
            config_dir: config_dir.to_path_buf(),
            home: PathBuf::from(std::env::var_os("HOME").unwrap_or_default()),
            companion,
            path_dirs: std::env::var_os("PATH")
                .map(|p| std::env::split_paths(&p).collect())
                .unwrap_or_default(),
            session_type,
            desktop,
        }
    }

    pub fn installed_companion(&self) -> PathBuf {
        self.home.join(".local/bin/event-horizon-companion")
    }

    pub fn screen_unit(&self) -> PathBuf {
        self.units().join(SCREEN_SERVICE)
    }

    pub fn guard_unit(&self) -> PathBuf {
        self.units().join(GUARD_SERVICE)
    }

    pub fn sunshine_conf(&self) -> PathBuf {
        self.home
            .join(".var/app/dev.lizardbyte.app.Sunshine/config/sunshine/sunshine.conf")
    }

    /// The desktop file the Sunshine Flatpak exports for a user install.
    pub fn sunshine_exported_desktop(&self) -> PathBuf {
        self.home.join(format!(
            ".local/share/flatpak/exports/share/applications/{SUNSHINE_APP}.desktop"
        ))
    }

    /// The user's copy of Sunshine's desktop file. It wins over the exported one,
    /// and KWin reads its interface grant from it.
    pub fn sunshine_desktop_grant(&self) -> PathBuf {
        self.home
            .join(format!(".local/share/applications/{SUNSHINE_APP}.desktop"))
    }

    /// The active stream marker. A separate recovery journal keeps the complete
    /// display snapshot until the selected output's settings are restored.
    pub fn stream_screen_saved(&self) -> PathBuf {
        self.config_dir.join("stream-screen-outputs")
    }

    /// The selected output's settings before a stream temporarily changes them.
    pub fn stream_screen_target_state(&self) -> PathBuf {
        self.config_dir.join("stream-screen-target-state")
    }

    /// Marks that display restoration must retry after a prior stream ended.
    pub fn stream_screen_recovery_required(&self) -> PathBuf {
        self.config_dir.join("stream-screen-recovery-required")
    }

    /// Optional connector to use for the stream instead of the virtual screen.
    /// Citadel uses its firmware-backed HDMI connector for genuine HDR output.
    pub fn stream_output(&self) -> PathBuf {
        self.config_dir.join("stream-output")
    }

    fn sunshine_drop_in(&self) -> PathBuf {
        self.units()
            .join(format!("{SUNSHINE_SERVICE}.d/event-horizon.conf"))
    }

    pub fn units(&self) -> PathBuf {
        self.home.join(".config/systemd/user")
    }

    fn companion_env(&self) -> PathBuf {
        self.config_dir.join("companion.env")
    }

    fn screen_password(&self) -> PathBuf {
        self.config_dir.join(SCREEN_PASSWORD_FILE)
    }
}

/// A random secret of 36 hex digits, from the OS.
pub fn random_secret() -> String {
    let mut bytes = [0u8; 18];
    getrandom::fill(&mut bytes).expect("the OS gives random bytes");
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

/// Why this PC gets no virtual screen, in words for the person at it. None
/// when it can have one. It reads only the session and the files, never a secret.
pub fn screen_skip(files: &dyn Files, layout: &Layout) -> Option<String> {
    if !virtual_screen::is_kde_wayland(layout.session_type.as_deref(), layout.desktop.as_deref()) {
        return Some(
            "This session is not KDE on Wayland, so Sunshine streams the physical screen.".into(),
        );
    }
    if find_on_path(files, layout, "krfb-virtualmonitor").is_none() {
        return Some(
            "Install the krfb package (krfb-virtualmonitor) for a Mac-sized screen. Until then, Sunshine streams the physical screen.".into(),
        );
    }
    if find_on_path(files, layout, "kscreen-doctor").is_none() {
        return Some(
            "Install KScreen (kscreen-doctor) for a Mac-sized screen. Until then, Sunshine streams the physical screen.".into(),
        );
    }
    None
}

/// Installs Sunshine, the companion, and the virtual screen where the session
/// allows it. Safe to run again: a second run changes nothing already right.
pub fn install(
    cmd: &dyn Commands,
    files: &dyn Files,
    layout: &Layout,
    size: Size,
    secret: &dyn Fn() -> String,
) -> Result<(), String> {
    copy_companion(files, layout)?;
    install_sunshine(cmd, files)?;
    if screen_skip(files, layout).is_none() {
        virtual_screen(cmd, files, layout, size, secret)?;
    }
    sunshine_login(cmd, files, layout, secret)?;
    companion_service(cmd, files, layout)?;
    watchdog_service(cmd, files, layout)
}

fn copy_companion(files: &dyn Files, layout: &Layout) -> Result<(), String> {
    let installed = layout.installed_companion();
    if layout.companion != installed {
        files.copy(&layout.companion, &installed)?;
    }
    Ok(())
}

fn install_sunshine(cmd: &dyn Commands, files: &dyn Files) -> Result<(), String> {
    if cmd.capture("flatpak", &["info", SUNSHINE_APP]).is_err() {
        cmd.run(
            "flatpak",
            &[
                "remote-add",
                "--user",
                "--if-not-exists",
                "flathub",
                "https://dl.flathub.org/repo/flathub.flatpakrepo",
            ],
        )?;
        cmd.run(
            "flatpak",
            &["install", "-y", "--user", "flathub", SUNSHINE_APP],
        )?;
    }
    if !files.exists(Path::new(UDEV_RULES)) {
        // Sunshine's own setup: user unit and uinput/uhid rules (asks once via pkexec).
        cmd.run(
            "flatpak",
            &["run", "--command=additional-install.sh", SUNSHINE_APP],
        )?;
    }
    Ok(())
}

/// The virtual screen: the krfb unit at the requested size, the display guard,
/// and Sunshine pointed at the output. Only called where `screen_skip` is None.
fn virtual_screen(
    cmd: &dyn Commands,
    files: &dyn Files,
    layout: &Layout,
    size: Size,
    secret: &dyn Fn() -> String,
) -> Result<(), String> {
    let krfb = find_on_path(files, layout, "krfb-virtualmonitor")
        .ok_or("krfb-virtualmonitor is not on the PATH")?;
    let placer = layout.installed_companion();
    let password = screen_password(files, layout, secret)?;
    let screen_text = virtual_screen::unit_text(&krfb, &placer, size, &password);
    let guard_text = virtual_screen::guard_unit_text(&placer);

    let screen_changed = user_unit(files, &layout.screen_unit(), &screen_text, true)?;
    let guard_changed = user_unit(files, &layout.guard_unit(), &guard_text, false)?;
    let drop_in = virtual_screen::sunshine_drop_in(&placer, &layout.config_dir);
    let drop_in_changed = user_unit(files, &layout.sunshine_drop_in(), &drop_in, false)?;
    write_sunshine_conf(files, layout)?;

    if screen_changed || guard_changed || drop_in_changed {
        cmd.run("systemctl", &["--user", "daemon-reload"])?;
    }
    start_unit(cmd, SCREEN_SERVICE, screen_changed)?;
    start_unit(cmd, GUARD_SERVICE, guard_changed)
}

/// Writes a user unit when its text changed. Returns whether it changed. A unit
/// with a secret in it is kept private.
fn user_unit(files: &dyn Files, path: &Path, text: &str, private: bool) -> Result<bool, String> {
    if files.read(path).as_deref() == Some(text) {
        return Ok(false);
    }
    files.write(path, text)?;
    if private {
        files.restrict(path);
    }
    Ok(true)
}

/// Enables a unit, and restarts it when its text changed or it is not running.
/// A running screen is left alone otherwise, so a stream is not cut.
fn start_unit(cmd: &dyn Commands, unit: &str, changed: bool) -> Result<(), String> {
    cmd.run("systemctl", &["--user", "enable", unit])?;
    let running = cmd
        .run("systemctl", &["--user", "is-active", "--quiet", unit])
        .is_ok();
    if changed || !running {
        cmd.run("systemctl", &["--user", "restart", unit])?;
    }
    Ok(())
}

/// Sunshine captures the virtual screen by its output name through KWin, and runs
/// the one-screen switch around each stream. KWin capture needs no saved choice of
/// screen, so it keeps working while a stream turns the desk monitor off; the
/// portal's saved choice names a monitor and goes black when that monitor is off.
/// Other settings in the file stay as they are.
fn write_sunshine_conf(files: &dyn Files, layout: &Layout) -> Result<(), String> {
    let path = layout.sunshine_conf();
    let before = files.read(&path).unwrap_or_default();
    let mut after = virtual_screen::with_setting(
        &before,
        "output_name",
        configured_stream_output(files, layout),
    );
    after = virtual_screen::with_setting(&after, "capture", "kwin");
    let existing = virtual_screen::setting(&after, "global_prep_cmd").map(str::to_string);
    if let Some(prep) = virtual_screen::prep_cmd(
        existing.as_deref(),
        &layout.installed_companion(),
        &layout.config_dir,
    ) {
        after = virtual_screen::with_setting(&after, "global_prep_cmd", &prep);
    }
    if after != before {
        files.write(&path, &after)?;
    }
    write_kwin_grant(files, layout)
}

/// KWin offers its screencast interface only to an app whose desktop file names
/// it in `X-KDE-Wayland-Interfaces`; without it Sunshine logs
/// `zkde_screencast_unstable_v1 not found in registry`. The user's copy of the
/// Flatpak's desktop file carries the grant, so the menu entry stays the same.
fn write_kwin_grant(files: &dyn Files, layout: &Layout) -> Result<(), String> {
    const GRANT: &str = "X-KDE-Wayland-Interfaces=zkde_screencast_unstable_v1";
    let exported = files
        .read(&layout.sunshine_exported_desktop())
        .unwrap_or_else(|| {
            format!(
                "[Desktop Entry]\nType=Application\nName=Sunshine\nExec=flatpak run {SUNSHINE_APP}\nNoDisplay=true\n"
            )
        });
    let mut grant = String::new();
    for line in exported
        .lines()
        .filter(|l| !l.starts_with("X-KDE-Wayland-Interfaces="))
    {
        grant.push_str(line);
        grant.push('\n');
        if line.trim() == "[Desktop Entry]" {
            grant.push_str(GRANT);
            grant.push('\n');
        }
    }
    let path = layout.sunshine_desktop_grant();
    if files.read(&path).as_deref() != Some(grant.as_str()) {
        files.write(&path, &grant)?;
    }
    Ok(())
}

/// The VNC password for the screen. It is made once and kept, so the unit stays the same.
fn screen_password(
    files: &dyn Files,
    layout: &Layout,
    secret: &dyn Fn() -> String,
) -> Result<String, String> {
    let path = layout.screen_password();
    if let Some(kept) = files
        .read(&path)
        .map(|p| p.trim().to_string())
        .filter(|p| !p.is_empty())
    {
        return Ok(kept);
    }
    let made = secret();
    files.write(&path, &made)?;
    files.restrict(&path);
    Ok(made)
}

fn find_on_path(files: &dyn Files, layout: &Layout, name: &str) -> Option<PathBuf> {
    layout
        .path_dirs
        .iter()
        .map(|dir| dir.join(name))
        .find(|path| files.exists(path))
}

/// Sunshine's login for the companion, then Sunshine restarts to read its config.
fn sunshine_login(
    cmd: &dyn Commands,
    files: &dyn Files,
    layout: &Layout,
    secret: &dyn Fn() -> String,
) -> Result<(), String> {
    let password = secret();
    // The error names the command, and the command carries the password: say less.
    cmd.run(
        "flatpak",
        &["run", SUNSHINE_APP, "--creds", SUNSHINE_USER, &password],
    )
    .map_err(|_| "Sunshine did not take the companion's login".to_string())?;
    let env_path = layout.companion_env();
    files.write(&env_path, &companion_env(files, layout, &password))?;
    files.restrict(&env_path);
    cmd.run("systemctl", &["--user", "enable", SUNSHINE_SERVICE])?;
    cmd.run("systemctl", &["--user", "restart", SUNSHINE_SERVICE])
}

/// The companion's env file. Per-game launch overrides from an earlier install are kept.
fn companion_env(files: &dyn Files, layout: &Layout, password: &str) -> String {
    let kept: String = files
        .read(&layout.companion_env())
        .unwrap_or_default()
        .lines()
        .filter(|l| !l.starts_with("SUNSHINE_USER=") && !l.starts_with("SUNSHINE_PASSWORD="))
        .map(|l| format!("{l}\n"))
        .collect();
    format!("SUNSHINE_USER={SUNSHINE_USER}\nSUNSHINE_PASSWORD={password}\n{kept}")
}

fn companion_service(cmd: &dyn Commands, files: &dyn Files, layout: &Layout) -> Result<(), String> {
    let unit = "[Unit]\nDescription=Event Horizon companion: this PC as a Mac app\nPartOf=graphical-session.target\nAfter=graphical-session.target\n\n[Service]\nExecStart=%h/.local/bin/event-horizon-companion\nRestart=on-failure\n\n[Install]\nWantedBy=graphical-session.target\n";
    files.write(&layout.units().join(SERVICE), unit)?;
    cmd.run("systemctl", &["--user", "daemon-reload"])?;
    cmd.run("systemctl", &["--user", "enable", SERVICE])?;
    cmd.run("systemctl", &["--user", "restart", SERVICE])
}

/// The Sunshine watchdog's user unit: it restarts a wedged or stale Flatpak
/// Sunshine after a stream ends. Restart=always keeps the watchdog running.
fn watchdog_service(cmd: &dyn Commands, files: &dyn Files, layout: &Layout) -> Result<(), String> {
    let exe = layout.installed_companion();
    let unit = format!(
        "[Unit]\nDescription=Event Horizon Sunshine watchdog: repairs Sunshine health when no stream is live\nPartOf=graphical-session.target\nAfter=graphical-session.target\n\n[Service]\nExecStart={} sunshine-watchdog\nRestart=always\nRestartSec=10\n\n[Install]\nWantedBy=graphical-session.target\n",
        exe.display()
    );
    files.write(&layout.units().join(WATCHDOG_SERVICE), &unit)?;
    cmd.run("systemctl", &["--user", "daemon-reload"])?;
    cmd.run("systemctl", &["--user", "enable", WATCHDOG_SERVICE])?;
    cmd.run("systemctl", &["--user", "restart", WATCHDOG_SERVICE])
}

/// Places the virtual screen right of the desk monitor once KScreen lists it.
/// The screen's unit runs this after krfb-virtualmonitor starts.
pub fn place_virtual_screen(cmd: &dyn Commands) -> Result<(), String> {
    for _ in 0..PLACE_TRIES {
        if let Some(args) = kscreen_placement(cmd) {
            let refs: Vec<&str> = args.iter().map(String::as_str).collect();
            return cmd.run("kscreen-doctor", &refs);
        }
        cmd.pause(PLACE_EVERY);
    }
    Err("the virtual screen did not appear within 10 seconds".into())
}

/// The one-screen mode. `on`, as a stream starts: the virtual screen becomes the
/// only screen, and the outputs it turned off are saved. Nothing changes while the
/// virtual screen is missing. `off`, as a stream ends or Sunshine starts: the saved
/// outputs come back, the first one primary, and the list is cleared.
pub fn stream_screen(
    cmd: &dyn Commands,
    files: &dyn Files,
    layout: &Layout,
    on: bool,
) -> Result<(), String> {
    let saved_path = layout.stream_screen_saved();
    if on {
        let recovery_required = files
            .read(&layout.stream_screen_recovery_required())
            .is_some_and(|state| !state.trim().is_empty());
        if recovery_required {
            recover_stream_screen(cmd, files, layout)?;
        }
        if let Some(saved) = files
            .read(&saved_path)
            .filter(|saved| !saved.trim().is_empty())
        {
            if saved_stream_state(&saved).is_some() {
                return Ok(());
            }
            recover_stream_screen(cmd, files, layout)?;
        }
        if files
            .read(&layout.stream_screen_target_state())
            .is_some_and(|state| !state.trim().is_empty())
        {
            recover_stream_screen(cmd, files, layout)?;
            if files
                .read(&layout.stream_screen_target_state())
                .is_some_and(|state| !state.trim().is_empty())
            {
                return Err(
                    "previous stream display settings are pending until the target reconnects"
                        .into(),
                );
            }
        }
        let target = configured_stream_output(files, layout);
        let snapshot = screen_for_stream(cmd, target)?;
        let recovery_state = serde_json::json!({
            "target": target,
            "restore": snapshot.restore.clone(),
            "target_settings": snapshot.target_settings.clone(),
        });
        let recovery_state = serde_json::to_string(&recovery_state).map_err(|e| e.to_string())?;
        files.write(&layout.stream_screen_target_state(), &recovery_state)?;
        let state = serde_json::json!({ "target": target, "restore": snapshot.restore.clone() });
        let state = serde_json::to_string(&state).map_err(|e| e.to_string())?;
        files.write(&saved_path, &state)?;
        let mut args = vec![
            format!("output.{target}.enable"),
            format!("output.{target}.priority.1"),
        ];
        if target == HDR_OUTPUT {
            args.push(format!("output.{target}.scale.1.75"));
        }
        args.extend(
            snapshot
                .restore
                .iter()
                .map(|o| format!("output.{o}.disable")),
        );
        let refs: Vec<&str> = args.iter().map(String::as_str).collect();
        if let Err(error) = cmd.run("kscreen-doctor", &refs) {
            if let Err(restore_error) = recover_stream_screen(cmd, files, layout) {
                return Err(format!(
                    "{error}; display restoration failed: {restore_error}"
                ));
            }
            return Err(error);
        }
        if target == HDR_OUTPUT {
            if let Err(error) = cmd.run("kscreen-doctor", &["output.HDMI-A-1.hdr.enable"]) {
                return match recover_stream_screen(cmd, files, layout) {
                    Ok(()) => Err(error),
                    Err(restore_error) => Err(format!(
                        "{error}; display restoration failed: {restore_error}"
                    )),
                };
            }
        }
        return Ok(());
    }
    recover_stream_screen(cmd, files, layout)
}

fn recover_stream_screen(
    cmd: &dyn Commands,
    files: &dyn Files,
    layout: &Layout,
) -> Result<(), String> {
    let recovery_path = layout.stream_screen_recovery_required();
    files.write(&recovery_path, "1")?;
    restore_stream_screen(cmd, files, layout)?;
    files.write(&recovery_path, "")
}

/// Restores the user's screens after a stream. Old newline-only state files remain
/// readable so a Sunshine restart during an upgrade cannot strand the display.
fn restore_stream_screen(
    cmd: &dyn Commands,
    files: &dyn Files,
    layout: &Layout,
) -> Result<(), String> {
    let saved_path = layout.stream_screen_saved();
    let saved = files.read(&saved_path).unwrap_or_default();
    let state_path = layout.stream_screen_target_state();
    let saved_target_state = files.read(&state_path).unwrap_or_default();
    let journal = recovery_stream_state(&saved_target_state);
    let legacy_target_settings = serde_json::from_str::<Value>(&saved_target_state)
        .ok()
        .filter(|value| is_target_settings(value));
    let mut state = saved_stream_state(&saved);
    if let Some(saved_state) = state.as_mut() {
        if let Some(journal) = journal
            .as_ref()
            .filter(|journal| journal.target == saved_state.target)
        {
            saved_state.target_settings = journal.target_settings.clone();
        } else if let Some(settings) = legacy_target_settings.clone() {
            saved_state.target_settings = Some(settings);
        }
    } else if !saved.trim().is_empty() {
        // The display list may be damaged after a crash. The sidecar is written
        // first and contains the complete snapshot, so prefer it for recovery.
        state = journal;
        if state.is_none() {
            // Older sidecars stored only the selected output's settings. They
            // cannot recover other outputs, but can still restore this target.
            state = legacy_target_settings
                .clone()
                .map(|settings| SavedStreamState {
                    target: configured_stream_output(files, layout).to_string(),
                    restore: Vec::new(),
                    target_settings: Some(settings),
                });
        }
    } else if let Some(journal) = journal {
        // The main marker is cleared after the other screens return. Keep the
        // sidecar until a disconnected stream target can recover its settings.
        // Its restore list has already been applied, so do not replay it.
        state = Some(SavedStreamState {
            restore: Vec::new(),
            ..journal
        });
    } else if let Some(settings) = legacy_target_settings.clone() {
        state = Some(SavedStreamState {
            target: configured_stream_output(files, layout).to_string(),
            restore: Vec::new(),
            target_settings: Some(settings),
        });
    }

    let Some(SavedStreamState {
        target,
        restore,
        target_settings,
    }) = state
    else {
        if saved.trim().is_empty() && saved_target_state.trim().is_empty() {
            return Ok(());
        }
        // No trustworthy snapshot remains. Leave the user's current layout as
        // it is, but clear the unusable marker so Sunshine recovery cannot be
        // blocked forever by corrupt state.
        eprintln!("stream-screen: saved display state is invalid; displays were left unchanged");
        files.write(&saved_path, "")?;
        return files.write(&state_path, "");
    };

    let text = cmd.capture("kscreen-doctor", &["--json"])?;
    let json: Value = serde_json::from_str(&text).map_err(|e| e.to_string())?;
    let outputs = json["outputs"]
        .as_array()
        .ok_or("KScreen returned no outputs")?;
    let connected = |name: &str| {
        outputs
            .iter()
            .any(|o| o["name"] == name && o["connected"] == true)
    };
    let enabled = |name: &str| {
        outputs
            .iter()
            .any(|o| o["name"] == name && o["enabled"] == true)
    };
    let restore: Vec<String> = restore.into_iter().filter(|name| connected(name)).collect();
    let screens_left = !restore.is_empty()
        || outputs
            .iter()
            .any(|o| o["name"] != target && o["enabled"] == true);
    let mut args: Vec<String> = restore
        .iter()
        .map(|o| format!("output.{o}.enable"))
        .collect();
    if let Some(first) = restore.first() {
        args.push(format!("output.{first}.priority.1"));
    }
    let target_connected = connected(&target);
    if target_connected {
        if let Some(was_enabled) = target_settings
            .as_ref()
            .and_then(|state| state.get("enabled"))
            .and_then(Value::as_bool)
        {
            // Keep the pre-stream layout, unless that would leave the host with
            // no active display after a disconnect during streaming.
            let should_be_enabled = was_enabled || !screens_left;
            if should_be_enabled && !enabled(&target) {
                args.push(format!("output.{target}.enable"));
            } else if !should_be_enabled && enabled(&target) {
                args.push(format!("output.{target}.disable"));
            }
        } else if target == OUTPUT && enabled(&target) && screens_left {
            // Legacy virtual-screen state did not capture whether the target
            // was enabled. An HDR marker cannot establish HDMI's prior state.
            args.push(format!("output.{target}.disable"));
        }
    }
    if !args.is_empty() {
        let refs: Vec<&str> = args.iter().map(String::as_str).collect();
        cmd.run("kscreen-doctor", &refs)?;
    }

    if let Some(target_settings) = target_settings.as_ref().filter(|_| target_connected) {
        let args = restore_target_settings(&target, target_settings);
        if !args.is_empty() {
            let refs: Vec<&str> = args.iter().map(String::as_str).collect();
            cmd.run("kscreen-doctor", &refs)?;
        }
    }

    let target_settings_pending = target_settings
        .as_ref()
        .is_some_and(|settings| is_target_settings(settings))
        && !target_connected;
    if target_settings_pending {
        // Record that the other screens are already restored before clearing
        // the active marker. Later retries only restore this disconnected target.
        let pending = serde_json::json!({
            "target": target,
            "restore": [],
            "target_settings": target_settings,
        });
        let pending = serde_json::to_string(&pending).map_err(|e| e.to_string())?;
        files.write(&state_path, &pending)?;
        files.write(&saved_path, "")?;
        Ok(())
    } else {
        files.write(&saved_path, "")?;
        files.write(&state_path, "")
    }
}

fn restore_target_settings(target: &str, settings: &Value) -> Vec<String> {
    let mut args = Vec::new();
    if let Some(scale) = settings.get("scale").and_then(Value::as_f64) {
        args.push(format!("output.{target}.scale.{scale}"));
    }
    if let Some(priority) = settings.get("priority").and_then(Value::as_i64) {
        args.push(format!("output.{target}.priority.{priority}"));
    }
    for key in ["hdr", "wcg"] {
        if let Some(enabled) = settings.get(key).and_then(Value::as_bool) {
            let mode = if enabled { "enable" } else { "disable" };
            args.push(format!("output.{target}.{key}.{mode}"));
        }
    }
    args
}

#[derive(Clone)]
struct SavedStreamState {
    target: String,
    restore: Vec<String>,
    target_settings: Option<Value>,
}

fn saved_stream_state(saved: &str) -> Option<SavedStreamState> {
    if saved.trim().is_empty() {
        return None;
    }
    if let Ok(value) = serde_json::from_str::<Value>(saved) {
        let target = value["target"].as_str()?;
        if ![OUTPUT, HDR_OUTPUT].contains(&target) {
            return None;
        }
        let restore = saved_output_names(&value["restore"], target)?;
        return Some(SavedStreamState {
            target: target.to_string(),
            restore,
            target_settings: None,
        });
    }
    if saved.trim_start().starts_with(['{', '[']) {
        return None;
    }
    // Before the JSON format, the file contained one previously enabled output
    // name per line, and streams always used the virtual screen.
    let restore = saved
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .map(|line| line.to_string())
        .collect::<Vec<_>>();
    if restore.is_empty()
        || restore
            .iter()
            .any(|name| !valid_output_name(name) || name == OUTPUT || name == HDR_OUTPUT)
    {
        return None;
    }
    Some(SavedStreamState {
        target: OUTPUT.to_string(),
        restore,
        target_settings: None,
    })
}

pub(crate) fn stream_screen_marker_valid(saved: &str) -> bool {
    saved_stream_state(saved).is_some()
}

pub(crate) fn stream_screen_active(files: &dyn Files, layout: &Layout) -> bool {
    if files
        .read(&layout.stream_screen_recovery_required())
        .is_some_and(|state| !state.trim().is_empty())
    {
        return false;
    }
    let saved = files
        .read(&layout.stream_screen_saved())
        .unwrap_or_default();
    if saved.trim().is_empty() {
        return false;
    }
    if stream_screen_marker_valid(&saved) {
        return true;
    }
    let target_state = files
        .read(&layout.stream_screen_target_state())
        .unwrap_or_default();
    recovery_stream_state(&target_state).is_some()
        || serde_json::from_str::<Value>(&target_state)
            .ok()
            .is_some_and(|state| is_target_settings(&state))
}

#[cfg(target_os = "linux")]
pub(crate) fn virtual_screen_stream_active(files: &dyn Files, layout: &Layout) -> bool {
    stream_screen_active(files, layout) && stream_screen_target(files, layout) == Some(OUTPUT)
}

#[cfg(target_os = "linux")]
fn stream_screen_target(files: &dyn Files, layout: &Layout) -> Option<&'static str> {
    let saved = files
        .read(&layout.stream_screen_saved())
        .unwrap_or_default();
    let state = saved_stream_state(&saved).or_else(|| {
        let recovery = files.read(&layout.stream_screen_target_state())?;
        recovery_stream_state(&recovery)
    })?;
    match state.target.as_str() {
        OUTPUT => Some(OUTPUT),
        HDR_OUTPUT => Some(HDR_OUTPUT),
        _ => None,
    }
}

fn recovery_stream_state(saved: &str) -> Option<SavedStreamState> {
    let value = serde_json::from_str::<Value>(saved).ok()?;
    let target = value["target"].as_str()?;
    if ![OUTPUT, HDR_OUTPUT].contains(&target) {
        return None;
    }
    let restore = saved_output_names(&value["restore"], target)?;
    let target_settings = value.get("target_settings")?.clone();
    if !target_settings.is_object() {
        return None;
    }
    Some(SavedStreamState {
        target: target.to_string(),
        restore,
        target_settings: Some(target_settings),
    })
}

fn saved_output_names(value: &Value, target: &str) -> Option<Vec<String>> {
    let restore = value
        .as_array()?
        .iter()
        .map(Value::as_str)
        .collect::<Option<Vec<_>>>()?;
    if restore
        .iter()
        .any(|name| !valid_output_name(name) || *name == target)
    {
        return None;
    }
    Some(restore.into_iter().map(str::to_string).collect())
}

fn valid_output_name(name: &str) -> bool {
    !name.is_empty()
        && name
            .chars()
            .all(|character| character.is_ascii_alphanumeric() || "-_.".contains(character))
}

fn is_target_settings(value: &Value) -> bool {
    value.as_object().is_some_and(|settings| {
        settings
            .keys()
            .any(|key| ["enabled", "scale", "priority", "hdr", "wcg"].contains(&key.as_str()))
    })
}

fn configured_stream_output(files: &dyn Files, layout: &Layout) -> &'static str {
    if files
        .read(&layout.stream_output())
        .is_some_and(|output| output.trim() == HDR_OUTPUT)
    {
        HDR_OUTPUT
    } else {
        OUTPUT
    }
}

/// Confirms the stream target is connected before changing screens.
/// The virtual screen is started when missing; failure leaves outputs untouched.
struct StreamScreenSnapshot {
    restore: Vec<String>,
    target_settings: Value,
}

fn screen_for_stream(cmd: &dyn Commands, target: &str) -> Result<StreamScreenSnapshot, String> {
    let mut started = false;
    for _ in 0..VIRTUAL_TRIES {
        let text = cmd.capture("kscreen-doctor", &["--json"])?;
        let json: Value = serde_json::from_str(&text).map_err(|e| e.to_string())?;
        if let Some(outputs) = json["outputs"].as_array() {
            if outputs
                .iter()
                .any(|o| o["name"] == target && o["connected"] == true)
            {
                let target_output = outputs
                    .iter()
                    .find(|o| o["name"] == target && o["connected"] == true)
                    .ok_or_else(|| format!("configured stream output {target} disappeared"))?;
                let mut target_settings = serde_json::Map::new();
                for key in ["enabled", "scale", "priority", "hdr", "wcg"] {
                    if let Some(value) = target_output.get(key) {
                        target_settings.insert(key.to_string(), value.clone());
                    }
                }
                return Ok(StreamScreenSnapshot {
                    restore: outputs
                        .iter()
                        .filter(|o| o["name"] != target && o["enabled"] == true)
                        .filter_map(|o| o["name"].as_str().map(str::to_string))
                        .collect(),
                    target_settings: Value::Object(target_settings),
                });
            }
        }
        if target != OUTPUT {
            return Err(format!(
                "configured stream output {target} is not connected; no monitor was turned off"
            ));
        }
        if !started {
            cmd.run("systemctl", &["--user", "start", SCREEN_SERVICE])?;
            started = true;
        }
        cmd.pause(VIRTUAL_WAIT);
    }
    Err(format!(
        "the virtual screen did not appear after {SCREEN_SERVICE} started; no monitor was turned off"
    ))
}

fn kscreen_placement(cmd: &dyn Commands) -> Option<Vec<String>> {
    let text = cmd.capture("kscreen-doctor", &["--json"]).ok()?;
    let json: Value = serde_json::from_str(&text).ok()?;
    virtual_screen::placement_args(&json)
}

/// Runs programs with `std::process`.
pub struct SystemCommands;

impl Commands for SystemCommands {
    fn run(&self, program: &str, args: &[&str]) -> Result<(), String> {
        let status = std::process::Command::new(program)
            .args(args)
            .status()
            .map_err(|e| format!("{program}: {e}"))?;
        if status.success() {
            Ok(())
        } else {
            Err(format!(
                "{program} {} ended with {:?}",
                args.join(" "),
                status.code()
            ))
        }
    }

    fn capture(&self, program: &str, args: &[&str]) -> Result<String, String> {
        let output = std::process::Command::new(program)
            .args(args)
            .output()
            .map_err(|e| format!("{program}: {e}"))?;
        if output.status.success() {
            Ok(String::from_utf8_lossy(&output.stdout).into_owned())
        } else {
            Err(format!(
                "{program} {} ended with {:?}",
                args.join(" "),
                output.status.code()
            ))
        }
    }

    fn pause(&self, how_long: Duration) {
        std::thread::sleep(how_long);
    }
}

/// Reads and writes the real file system.
pub struct SystemFiles;

impl Files for SystemFiles {
    fn read(&self, path: &Path) -> Option<String> {
        std::fs::read_to_string(path).ok()
    }

    fn write(&self, path: &Path, text: &str) -> Result<(), String> {
        make_parent(path)?;
        std::fs::write(path, text).map_err(|e| format!("write {}: {e}", path.display()))
    }

    fn exists(&self, path: &Path) -> bool {
        path.is_file()
    }

    fn restrict(&self, path: &Path) {
        restrict_to_owner(path);
    }

    fn copy(&self, from: &Path, to: &Path) -> Result<(), String> {
        make_parent(to)?;
        // Replace, not overwrite: a running companion keeps its old file.
        let _ = std::fs::remove_file(to);
        std::fs::copy(from, to)
            .map(|_| ())
            .map_err(|e| format!("copy the companion: {e}"))
    }
}

fn make_parent(path: &Path) -> Result<(), String> {
    match path.parent() {
        Some(dir) => std::fs::create_dir_all(dir).map_err(|e| e.to_string()),
        None => Ok(()),
    }
}

#[cfg(unix)]
fn restrict_to_owner(path: &Path) {
    use std::os::unix::fs::PermissionsExt;
    let _ = std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o600));
}

#[cfg(not(unix))]
fn restrict_to_owner(_path: &Path) {}
