//! `play`: open a Steam game for Sunshine, waiting out a pending update.

use event_horizon_companion::play::refused_since;

const LOG: &str = "\
[2026-10-09 19:00:01] Game process added : AppID 1808500 \"...\"
[2026-10-09 20:10:05] LaunchApp failed: AppID 1808500, update required
[2026-10-09 20:10:06] LaunchApp failed: AppID 2694490, update required
";

#[test]
fn a_refusal_after_we_started_counts() {
    assert!(refused_since(LOG, "1808500", "2026-10-09 20:10:00"));
}

#[test]
fn a_refusal_before_we_started_does_not() {
    assert!(!refused_since(LOG, "1808500", "2026-10-09 20:11:00"));
}

#[test]
fn another_games_refusal_does_not() {
    assert!(!refused_since(LOG, "1623730", "2026-10-09 20:00:00"));
    assert!(
        !refused_since(LOG, "180850", "2026-10-09 20:00:00"),
        "a prefix of another id"
    );
}
