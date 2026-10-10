//! The Linux install and the virtual screen's placement, driven through their
//! interface. The command runner and the file system are fakes that share one
//! log, so a test can check what ran, what was written, and in what order.

use event_horizon_companion::linux_install::{self, Commands, Files, Layout, VirtualScreen};
use event_horizon_companion::virtual_screen::{DEFAULT_SIZE, Size};
use serde_json::json;
use std::collections::{HashMap, HashSet, VecDeque};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

type Log = Arc<Mutex<Vec<String>>>;

const SUNSHINE_UNIT: &str = "app-dev.lizardbyte.app.Sunshine.service";
const SCREEN_UNIT: &str = "event-horizon-virtual-screen.service";
const KRFB: &str = "/usr/bin/krfb-virtualmonitor";
const KSCREEN: &str = "/usr/bin/kscreen-doctor";
const UDEV_RULES: &str = "/etc/udev/rules.d/60-sunshine.rules";
const OUTPUT: &str = "Virtual-sunshine-vmon";

/// A command runner that succeeds unless `failing` names the program.
#[derive(Default)]
struct FakeCommands {
    log: Log,
    sunshine_installed: bool,
    failing: HashSet<String>,
    /// Units that are running: `restart` starts one, `is-active` asks.
    active: Mutex<HashSet<String>>,
    /// Answers to `kscreen-doctor --json`, in order; the last one repeats.
    kscreen: Mutex<VecDeque<String>>,
    paused: Mutex<Duration>,
}

impl Commands for FakeCommands {
    fn run(&self, program: &str, args: &[&str]) -> Result<(), String> {
        self.log
            .lock()
            .unwrap()
            .push(format!("run {program} {}", args.join(" ")));
        if self.failing.contains(program) {
            // As the real runner words it: the arguments are in the error.
            return Err(format!("{program} {} ended with 1", args.join(" ")));
        }
        if program == "systemctl" {
            return self.systemctl(args);
        }
        Ok(())
    }

    fn capture(&self, program: &str, args: &[&str]) -> Result<String, String> {
        self.log
            .lock()
            .unwrap()
            .push(format!("capture {program} {}", args.join(" ")));
        match (program, args) {
            ("flatpak", ["info", _]) if self.sunshine_installed => Ok(String::new()),
            ("flatpak", ["info", _]) => Err("flatpak: not installed".into()),
            ("kscreen-doctor", ["--json"]) => Ok(self.next_kscreen()),
            _ => Err(format!("{program}: no answer")),
        }
    }

    fn pause(&self, how_long: Duration) {
        *self.paused.lock().unwrap() += how_long;
    }
}

impl FakeCommands {
    fn systemctl(&self, args: &[&str]) -> Result<(), String> {
        let mut active = self.active.lock().unwrap();
        match args {
            ["--user", "restart", unit] => {
                active.insert(unit.to_string());
                Ok(())
            }
            ["--user", "is-active", _, unit] if active.contains(*unit) => Ok(()),
            ["--user", "is-active", _, unit] => Err(format!("{unit} is not active")),
            _ => Ok(()),
        }
    }

    fn next_kscreen(&self) -> String {
        let mut answers = self.kscreen.lock().unwrap();
        if answers.len() > 1 {
            answers.pop_front().unwrap_or_default()
        } else {
            answers.front().cloned().unwrap_or_default()
        }
    }
}

/// A file system held in memory. Writes, copies and permission changes are logged.
#[derive(Default)]
struct FakeFiles {
    log: Log,
    files: Mutex<HashMap<PathBuf, String>>,
}

impl Files for FakeFiles {
    fn read(&self, path: &Path) -> Option<String> {
        self.files.lock().unwrap().get(path).cloned()
    }

    fn write(&self, path: &Path, text: &str) -> Result<(), String> {
        self.log
            .lock()
            .unwrap()
            .push(format!("write {}", path.display()));
        self.files
            .lock()
            .unwrap()
            .insert(path.to_path_buf(), text.to_string());
        Ok(())
    }

    fn exists(&self, path: &Path) -> bool {
        self.files.lock().unwrap().contains_key(path)
    }

    fn restrict(&self, path: &Path) {
        self.log
            .lock()
            .unwrap()
            .push(format!("restrict {}", path.display()));
    }

    fn copy(&self, from: &Path, to: &Path) -> Result<(), String> {
        self.log
            .lock()
            .unwrap()
            .push(format!("copy {} {}", from.display(), to.display()));
        self.files
            .lock()
            .unwrap()
            .insert(to.to_path_buf(), String::new());
        Ok(())
    }
}

impl FakeFiles {
    fn put(&self, path: impl AsRef<Path>, text: &str) {
        self.files
            .lock()
            .unwrap()
            .insert(path.as_ref().to_path_buf(), text.to_string());
    }

    fn remove(&self, path: impl AsRef<Path>) {
        self.files.lock().unwrap().remove(path.as_ref());
    }
}

/// A PC with Sunshine's flatpak installed, KDE's tools on the path, and the
/// udev rules Sunshine's own setup writes, so no step asks for a password.
fn pc() -> (FakeCommands, FakeFiles) {
    let log = Log::default();
    let cmd = FakeCommands {
        log: log.clone(),
        sunshine_installed: true,
        ..Default::default()
    };
    let files = FakeFiles {
        log,
        ..Default::default()
    };
    files.put(KRFB, "");
    files.put(KSCREEN, "");
    files.put(UDEV_RULES, "");
    (cmd, files)
}

fn kde_layout() -> Layout {
    Layout {
        config_dir: PathBuf::from("/home/friend/.config/event-horizon"),
        home: PathBuf::from("/home/friend"),
        companion: PathBuf::from("/home/friend/Downloads/event-horizon-companion"),
        path_dirs: vec![PathBuf::from("/usr/bin")],
        session_type: Some("wayland".into()),
        desktop: Some("KDE".into()),
    }
}

fn secret() -> String {
    "deadbeef".to_string()
}

fn install(
    cmd: &FakeCommands,
    files: &FakeFiles,
    layout: &Layout,
) -> Result<VirtualScreen, String> {
    linux_install::install(cmd, files, layout, DEFAULT_SIZE, &secret)
}

fn log_of(log: &Log) -> Vec<String> {
    log.lock().unwrap().clone()
}

fn ran(log: &Log, line: &str) -> bool {
    log_of(log).iter().any(|l| l == line)
}

fn count(log: &Log, line: &str) -> usize {
    log_of(log).iter().filter(|l| *l == line).count()
}

fn at(log: &Log, line: &str) -> usize {
    log_of(log)
        .iter()
        .position(|l| l == line)
        .unwrap_or_else(|| panic!("never happened: {line}"))
}

fn kscreen_answer(desk_width: i64, desk_scale: f64, virtual_on: bool) -> String {
    let mut outputs = vec![json!({
        "name": "DP-1", "enabled": true, "connected": true,
        "size": { "width": desk_width, "height": 1080 },
        "scale": desk_scale, "pos": { "x": 0, "y": 0 }, "priority": 1
    })];
    if virtual_on {
        outputs.push(json!({
            "name": OUTPUT, "enabled": true, "connected": true,
            "size": { "width": 2560, "height": 1600 },
            "scale": 1.75, "pos": { "x": desk_width, "y": 0 }, "priority": 2
        }));
    }
    json!({ "outputs": outputs }).to_string()
}

#[test]
fn on_kde_wayland_the_screen_unit_runs_krfb_at_the_default_size() {
    let (cmd, files) = pc();
    let layout = kde_layout();

    assert_eq!(install(&cmd, &files, &layout), Ok(VirtualScreen::Ready));

    let unit = files
        .read(&layout.screen_unit())
        .expect("the unit is written");
    let krfb = Path::new("/usr/bin").join("krfb-virtualmonitor");
    let placer = layout.installed_companion();
    assert!(unit.contains(&format!(
        "ExecStart={} --resolution 2560x1600 --name sunshine-vmon --port 5905 --password deadbeef",
        krfb.display()
    )));
    assert!(unit.contains("Environment=QT_QPA_PLATFORM=wayland"));
    assert!(unit.contains(&format!(
        "ExecStartPost=-{} place-virtual-screen",
        placer.display()
    )));
}

#[test]
fn the_screen_is_started_now_so_it_exists_before_sunshine_is_configured() {
    let (cmd, files) = pc();
    install(&cmd, &files, &kde_layout()).unwrap();

    assert!(ran(
        &cmd.log,
        &format!("run systemctl --user restart {SCREEN_UNIT}")
    ));
}

#[test]
fn sunshine_is_pointed_at_the_virtual_screen_and_captured_with_kwin() {
    let (cmd, files) = pc();
    let layout = kde_layout();
    install(&cmd, &files, &layout).unwrap();

    let conf = files
        .read(&layout.sunshine_conf())
        .expect("sunshine.conf is written");
    assert!(conf.lines().any(|l| l == format!("output_name = {OUTPUT}")));
    assert!(conf.lines().any(|l| l == "capture = kwin"));
}

#[test]
fn sunshine_reads_the_virtual_screen_config_before_it_restarts() {
    let (cmd, files) = pc();
    let layout = kde_layout();
    install(&cmd, &files, &layout).unwrap();

    let written = at(
        &cmd.log,
        &format!("write {}", layout.sunshine_conf().display()),
    );
    let restarted = at(
        &cmd.log,
        &format!("run systemctl --user restart {SUNSHINE_UNIT}"),
    );
    assert!(written < restarted);
}

#[test]
fn the_companion_is_copied_before_the_screen_unit_points_at_it() {
    let (cmd, files) = pc();
    let layout = kde_layout();
    install(&cmd, &files, &layout).unwrap();

    let copied = at(
        &cmd.log,
        &format!(
            "copy {} {}",
            layout.companion.display(),
            layout.installed_companion().display()
        ),
    );
    let unit = at(
        &cmd.log,
        &format!("write {}", layout.screen_unit().display()),
    );
    assert!(
        copied < unit,
        "the first start can already place the screen"
    );
}

#[test]
fn a_second_run_rewrites_nothing_and_restarts_nothing_for_the_screen() {
    let (cmd, files) = pc();
    let layout = kde_layout();
    let counter = AtomicUsize::new(0);
    let fresh = || format!("secret{}", counter.fetch_add(1, Ordering::SeqCst));

    linux_install::install(&cmd, &files, &layout, DEFAULT_SIZE, &fresh).unwrap();
    let unit_first = files.read(&layout.screen_unit()).unwrap();
    let conf_first = files.read(&layout.sunshine_conf()).unwrap();
    let password_first = files
        .read(&layout.config_dir.join("virtual-screen-vnc"))
        .unwrap();

    linux_install::install(&cmd, &files, &layout, DEFAULT_SIZE, &fresh).unwrap();

    assert_eq!(files.read(&layout.screen_unit()).unwrap(), unit_first);
    assert_eq!(files.read(&layout.sunshine_conf()).unwrap(), conf_first);
    assert_eq!(
        files
            .read(&layout.config_dir.join("virtual-screen-vnc"))
            .unwrap(),
        password_first,
        "the VNC password is made once and kept"
    );
    assert_eq!(
        count(
            &cmd.log,
            &format!("write {}", layout.screen_unit().display())
        ),
        1
    );
    assert_eq!(
        count(
            &cmd.log,
            &format!("write {}", layout.sunshine_conf().display())
        ),
        1
    );
    assert_eq!(
        count(
            &cmd.log,
            &format!("run systemctl --user restart {SCREEN_UNIT}")
        ),
        1,
        "a running screen is not restarted, so a stream is not cut"
    );
}

#[test]
fn sunshine_settings_that_are_not_ours_survive() {
    let (cmd, files) = pc();
    let layout = kde_layout();
    files.put(
        layout.sunshine_conf(),
        "global_prep_cmd = [{\"do\":\"hook\"}]\noutput_name = 0\nencoder = nvenc\n",
    );

    install(&cmd, &files, &layout).unwrap();

    let conf = files.read(&layout.sunshine_conf()).unwrap();
    assert!(
        conf.lines()
            .any(|l| l == "global_prep_cmd = [{\"do\":\"hook\"}]")
    );
    assert!(conf.lines().any(|l| l == "encoder = nvenc"));
    assert_eq!(
        conf.lines()
            .filter(|l| l.starts_with("output_name"))
            .count(),
        1
    );
    assert!(conf.lines().any(|l| l == format!("output_name = {OUTPUT}")));
}

#[test]
fn the_size_given_is_the_size_the_screen_runs_at() {
    let (cmd, files) = pc();
    let layout = kde_layout();
    let full_hd = Size {
        width: 1920,
        height: 1080,
    };

    linux_install::install(&cmd, &files, &layout, full_hd, &secret).unwrap();

    let unit = files.read(&layout.screen_unit()).unwrap();
    assert!(unit.contains("--resolution 1920x1080"));
}

#[test]
fn outside_kde_on_wayland_it_skips_the_screen_and_says_why() {
    let (cmd, files) = pc();
    let mut layout = kde_layout();
    layout.session_type = Some("x11".into());

    let outcome = install(&cmd, &files, &layout).unwrap();

    let VirtualScreen::Skipped(reason) = outcome else {
        panic!("no virtual screen outside KDE on Wayland");
    };
    assert!(reason.contains("KDE"));
    assert!(reason.contains("Wayland"));
    assert!(files.read(&layout.screen_unit()).is_none());
    assert!(files.read(&layout.sunshine_conf()).is_none());
}

#[test]
fn without_krfb_it_skips_the_screen_and_names_the_package() {
    let (cmd, files) = pc();
    files.remove(KRFB);

    let outcome = install(&cmd, &files, &kde_layout()).unwrap();

    let VirtualScreen::Skipped(reason) = outcome else {
        panic!("no virtual screen without krfb-virtualmonitor");
    };
    assert!(reason.contains("krfb"));
}

#[test]
fn skipping_the_screen_still_gives_sunshine_its_login() {
    let (cmd, files) = pc();
    let mut layout = kde_layout();
    layout.session_type = Some("x11".into());

    install(&cmd, &files, &layout).unwrap();

    assert!(ran(
        &cmd.log,
        "run flatpak run dev.lizardbyte.app.Sunshine --creds eventhorizon deadbeef"
    ));
    let env = files
        .read(&layout.config_dir.join("companion.env"))
        .expect("companion.env is written");
    assert!(env.contains("SUNSHINE_PASSWORD=deadbeef"));
}

#[test]
fn a_failed_sunshine_login_does_not_put_the_password_in_the_error() {
    let (mut cmd, files) = pc();
    cmd.failing.insert("flatpak".into());

    let error = install(&cmd, &files, &kde_layout()).unwrap_err();

    assert!(!error.contains("deadbeef"), "the password leaked: {error}");
    assert!(error.contains("Sunshine"), "{error}");
}

#[test]
fn a_command_that_fails_stops_the_install_and_names_it() {
    let (mut cmd, files) = pc();
    cmd.sunshine_installed = false;
    cmd.failing.insert("flatpak".into());

    let error = install(&cmd, &files, &kde_layout()).unwrap_err();

    assert!(error.contains("flatpak"), "{error}");
}

#[test]
fn the_placement_puts_the_screen_right_of_the_desk_monitor() {
    let (cmd, _files) = pc();
    cmd.kscreen.lock().unwrap().extend([
        kscreen_answer(1920, 1.0, false),
        kscreen_answer(1920, 1.0, true),
    ]);

    linux_install::place_virtual_screen(&cmd).unwrap();

    assert!(ran(
        &cmd.log,
        &format!(
            "run kscreen-doctor output.{OUTPUT}.scale.1.75 output.{OUTPUT}.position.1920,0 output.{OUTPUT}.priority.1"
        )
    ));
}

#[test]
fn the_placement_never_disables_an_output() {
    let (cmd, _files) = pc();
    cmd.kscreen
        .lock()
        .unwrap()
        .push_back(kscreen_answer(1920, 1.0, true));

    linux_install::place_virtual_screen(&cmd).unwrap();

    assert!(log_of(&cmd.log).iter().all(|l| !l.contains("disable")));
}

#[test]
fn the_placement_uses_the_logical_width_of_a_scaled_desk_monitor() {
    let (cmd, _files) = pc();
    cmd.kscreen
        .lock()
        .unwrap()
        .push_back(kscreen_answer(2560, 1.25, true));

    linux_install::place_virtual_screen(&cmd).unwrap();

    assert!(ran(
        &cmd.log,
        &format!(
            "run kscreen-doctor output.{OUTPUT}.scale.1.75 output.{OUTPUT}.position.2048,0 output.{OUTPUT}.priority.1"
        )
    ));
}

#[test]
fn the_placement_waits_for_the_screen_then_gives_up_after_ten_seconds() {
    let (cmd, _files) = pc();
    cmd.kscreen
        .lock()
        .unwrap()
        .push_back(kscreen_answer(1920, 1.0, false));

    let error = linux_install::place_virtual_screen(&cmd).unwrap_err();

    assert!(error.contains("virtual screen"), "{error}");
    assert_eq!(*cmd.paused.lock().unwrap(), Duration::from_secs(10));
    assert!(
        log_of(&cmd.log)
            .iter()
            .all(|l| !l.starts_with("run kscreen-doctor output."))
    );
}
