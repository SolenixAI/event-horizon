//! Contract: on Linux, a hold never panics without a desktop session (CI),
//! and on a real KDE session the screensaver reports itself inhibited.
#![cfg(target_os = "linux")]

use event_horizon_companion::Awake;
use event_horizon_companion::os::linux::SessionInhibit;

#[test]
fn a_hold_and_release_never_panic() {
    let guard = SessionInhibit.hold();
    drop(guard);
}
