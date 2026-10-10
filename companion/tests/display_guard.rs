//! The display guard turns the virtual screen back on after a monitor wake, and
//! never disables an output. Driven through fakes: KScreen's answers and the
//! DRM events are scripted.

use event_horizon_companion::display_guard::guard;
use event_horizon_companion::linux_install::Commands;
use serde_json::json;
use std::collections::VecDeque;
use std::sync::Mutex;
use std::time::Duration;

const OUTPUT: &str = "Virtual-sunshine-vmon";
const CHANGE: &str = "KERNEL[1204.5] change   /devices/pci0000:00/card1 (drm)";
const ADD: &str = "KERNEL[1205.1] add      /devices/pci0000:00/card1-HDMI-A-1 (drm)";
const REMOVE: &str = "KERNEL[1206.0] remove   /devices/pci0000:00/card1-HDMI-A-1 (drm)";

/// Answers `kscreen-doctor --json` in order (the last answer repeats), and
/// records every command run and every pause.
#[derive(Default)]
struct FakeKscreen {
    answers: Mutex<VecDeque<String>>,
    checks: Mutex<usize>,
    runs: Mutex<Vec<String>>,
    paused: Mutex<Duration>,
}

impl Commands for FakeKscreen {
    fn run(&self, program: &str, args: &[&str]) -> Result<(), String> {
        self.runs
            .lock()
            .unwrap()
            .push(format!("{program} {}", args.join(" ")));
        Ok(())
    }

    fn capture(&self, _program: &str, _args: &[&str]) -> Result<String, String> {
        *self.checks.lock().unwrap() += 1;
        let mut answers = self.answers.lock().unwrap();
        Ok(if answers.len() > 1 {
            answers.pop_front().unwrap_or_default()
        } else {
            answers.front().cloned().unwrap_or_default()
        })
    }

    fn pause(&self, how_long: Duration) {
        *self.paused.lock().unwrap() += how_long;
    }
}

/// KScreen with the desk monitor, and the virtual output as `virtual_state`:
/// on, off, or absent (None).
fn kscreen(virtual_state: Option<bool>) -> String {
    let mut outputs = vec![json!({ "name": "DP-1", "enabled": true })];
    if let Some(enabled) = virtual_state {
        outputs.push(json!({ "name": OUTPUT, "enabled": enabled }));
    }
    json!({ "outputs": outputs }).to_string()
}

fn fake(answers: &[Option<bool>]) -> FakeKscreen {
    let fake = FakeKscreen::default();
    fake.answers
        .lock()
        .unwrap()
        .extend(answers.iter().map(|a| kscreen(*a)));
    fake
}

fn enable_command() -> String {
    format!("kscreen-doctor output.{OUTPUT}.enable")
}

#[test]
fn a_virtual_screen_that_is_on_is_left_alone() {
    let cmd = fake(&[Some(true)]);

    guard(&cmd, Vec::<String>::new());

    assert!(cmd.runs.lock().unwrap().is_empty());
    assert_eq!(*cmd.checks.lock().unwrap(), 1, "checked once at start");
}

#[test]
fn a_virtual_screen_that_is_off_is_turned_on_at_start() {
    let cmd = fake(&[Some(false)]);

    guard(&cmd, Vec::<String>::new());

    assert_eq!(*cmd.runs.lock().unwrap(), vec![enable_command()]);
}

#[test]
fn a_drm_change_turns_the_screen_back_on() {
    let cmd = fake(&[Some(true), Some(false)]);

    guard(&cmd, [CHANGE.to_string()]);

    assert_eq!(*cmd.runs.lock().unwrap(), vec![enable_command()]);
}

#[test]
fn an_add_event_is_checked_too() {
    let cmd = fake(&[Some(true), Some(false)]);

    guard(&cmd, [ADD.to_string()]);

    assert_eq!(*cmd.runs.lock().unwrap(), vec![enable_command()]);
}

#[test]
fn a_remove_event_is_not_checked() {
    let cmd = fake(&[Some(true)]);

    guard(&cmd, [REMOVE.to_string()]);

    assert_eq!(*cmd.checks.lock().unwrap(), 1, "only the start check ran");
}

#[test]
fn a_wake_that_leaves_the_screen_on_runs_nothing() {
    let cmd = fake(&[Some(true)]);

    guard(&cmd, [CHANGE.to_string(), CHANGE.to_string()]);

    assert!(cmd.runs.lock().unwrap().is_empty());
    assert_eq!(*cmd.checks.lock().unwrap(), 3);
}

#[test]
fn turning_the_screen_on_twice_is_not_repeated() {
    let cmd = fake(&[Some(false), Some(true)]);

    guard(&cmd, [CHANGE.to_string(), CHANGE.to_string()]);

    assert_eq!(
        cmd.runs.lock().unwrap().len(),
        1,
        "the second check sees the screen on"
    );
}

#[test]
fn the_guard_never_disables_an_output() {
    let cmd = fake(&[Some(false), Some(true), Some(false)]);

    guard(&cmd, [CHANGE.to_string(), CHANGE.to_string()]);

    assert!(
        cmd.runs
            .lock()
            .unwrap()
            .iter()
            .all(|r| !r.contains("disable"))
    );
}

#[test]
fn a_virtual_screen_that_is_not_listed_is_left_to_its_own_unit() {
    let cmd = fake(&[None]);

    guard(&cmd, [CHANGE.to_string()]);

    assert!(cmd.runs.lock().unwrap().is_empty());
}

#[test]
fn every_check_waits_two_seconds_for_kwin_to_settle_first() {
    let cmd = fake(&[Some(true)]);

    guard(&cmd, [CHANGE.to_string(), CHANGE.to_string()]);

    assert_eq!(*cmd.paused.lock().unwrap(), Duration::from_secs(6));
}

#[test]
fn a_failed_check_does_not_stop_the_guard() {
    let cmd = fake(&[]);

    guard(&cmd, [CHANGE.to_string()]);

    assert_eq!(
        *cmd.checks.lock().unwrap(),
        2,
        "it kept going after the failure"
    );
    assert!(cmd.runs.lock().unwrap().is_empty());
}
