//! Contract: on Windows, a hold shows up in `powercfg /requests` with our
//! reason, and dropping it removes it.
#![cfg(windows)]

use event_horizon_companion::Awake;
use event_horizon_companion::os::windows::{PowerRequest, REASON};

fn listed() -> bool {
    let out = std::process::Command::new("powercfg")
        .arg("/requests")
        .output()
        .expect("powercfg runs");
    String::from_utf8_lossy(&out.stdout).contains(REASON)
}

#[test]
fn a_hold_is_a_display_request_windows_can_see() {
    let guard = PowerRequest.hold();
    assert!(listed(), "powercfg lists the request while held");
    drop(guard);
    assert!(!listed(), "and forgets it once released");
}
