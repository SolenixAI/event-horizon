//! The display guard: keeps the virtual screen on. KWin can switch the virtual
//! output off when a monitor wakes or is plugged in. The guard turns it back
//! on, and never disables an output.

use crate::linux_install::Commands;
use crate::virtual_screen::OUTPUT;
use serde_json::Value;
use std::io::{BufRead, BufReader};
use std::process::{Command, Stdio};
use std::time::Duration;

/// Waits this long after a DRM event before checking, so KWin settles first.
const SETTLE: Duration = Duration::from_secs(2);

/// Checks once at start, then after every DRM change or add event, until the
/// events end. A failed check is reported and the guard keeps going.
pub fn guard(cmd: &dyn Commands, events: impl IntoIterator<Item = String>) {
    enforce(cmd);
    for line in events {
        if matches!(action(&line), Some("change" | "add")) {
            enforce(cmd);
        }
    }
}

/// Runs the guard on `udevadm`'s DRM events. Returns an error when `udevadm`
/// stops, so the unit restarts it.
pub fn run(cmd: &dyn Commands) -> Result<(), String> {
    let mut child = Command::new("udevadm")
        .args(["monitor", "--udev", "--subsystem-match=drm"])
        .stdout(Stdio::piped())
        .spawn()
        .map_err(|e| format!("udevadm: {e}"))?;
    let stdout = child.stdout.take().ok_or("udevadm gave no output")?;
    guard(cmd, BufReader::new(stdout).lines().map_while(Result::ok));
    let status = child.wait().map_err(|e| e.to_string())?;
    Err(format!("udevadm stopped ({status})"))
}

/// The action in a `udevadm monitor` line: `KERNEL[1.2] change /devices/...`.
fn action(line: &str) -> Option<&str> {
    line.split_whitespace().nth(1)
}

fn enforce(cmd: &dyn Commands) {
    cmd.pause(SETTLE);
    if let Err(e) = enforce_once(cmd) {
        eprintln!("display guard: {e}");
    }
}

/// Turns the virtual output on when KScreen lists it as off. An output that is
/// missing is left alone: the screen's own unit brings it back.
fn enforce_once(cmd: &dyn Commands) -> Result<(), String> {
    let text = cmd.capture("kscreen-doctor", &["--json"])?;
    let json: Value = serde_json::from_str(&text).map_err(|e| e.to_string())?;
    if virtual_enabled(&json) == Some(false) {
        let arg = format!("output.{OUTPUT}.enable");
        cmd.run("kscreen-doctor", &[arg.as_str()])?;
    }
    Ok(())
}

/// Whether the virtual output is on. None when KScreen does not list it.
fn virtual_enabled(kscreen: &Value) -> Option<bool> {
    kscreen["outputs"]
        .as_array()?
        .iter()
        .find(|o| o["name"] == OUTPUT)?["enabled"]
        .as_bool()
}
