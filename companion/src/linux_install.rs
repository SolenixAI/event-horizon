//! Linux install: one run turns this PC into an Event Horizon host. The steps
//! run through the `Commands` and `Files` ports, so tests drive them with fakes.

use crate::virtual_screen::{self, GUARD_SERVICE, OUTPUT, SCREEN_SERVICE, Size};
use serde_json::Value;
use std::path::{Path, PathBuf};
use std::time::Duration;

const SUNSHINE_APP: &str = "dev.lizardbyte.app.Sunshine";
const SUNSHINE_SERVICE: &str = "app-dev.lizardbyte.app.Sunshine.service";
const SUNSHINE_USER: &str = "eventhorizon";
const SERVICE: &str = "event-horizon-companion.service";
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
        Layout {
            config_dir: config_dir.to_path_buf(),
            home: PathBuf::from(std::env::var_os("HOME").unwrap_or_default()),
            companion,
            path_dirs: std::env::var_os("PATH")
                .map(|p| std::env::split_paths(&p).collect())
                .unwrap_or_default(),
            session_type: std::env::var("XDG_SESSION_TYPE").ok(),
            desktop: std::env::var("XDG_CURRENT_DESKTOP").ok(),
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

    fn units(&self) -> PathBuf {
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
    companion_service(cmd, files, layout)
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
    write_sunshine_conf(files, layout)?;

    if screen_changed || guard_changed {
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

/// Sunshine reads the output name and captures through KWin, since the output is
/// not a DRM connector. Other settings in the file stay as they are.
fn write_sunshine_conf(files: &dyn Files, layout: &Layout) -> Result<(), String> {
    let path = layout.sunshine_conf();
    let before = files.read(&path).unwrap_or_default();
    let after = virtual_screen::with_setting(
        &virtual_screen::with_setting(&before, "output_name", OUTPUT),
        "capture",
        "kwin",
    );
    if after != before {
        files.write(&path, &after)?;
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
