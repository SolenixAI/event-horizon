use event_horizon_companion::sunshine_watchdog::{DOWN_FOR, RESTART_GAP, Step, Watch};
use std::time::Duration;

fn secs(s: u64) -> Duration {
    Duration::from_secs(s)
}

#[test]
fn a_sunshine_that_answers_is_left_alone() {
    let mut watch = Watch::default();

    assert_eq!(watch.step(secs(0), true, false), Step::Fine);
}

#[test]
fn a_sunshine_down_for_less_than_a_minute_is_given_time() {
    let mut watch = Watch::default();

    assert_eq!(watch.step(secs(0), false, false), Step::Wait);
    assert_eq!(watch.step(secs(45), false, false), Step::Wait);
}

#[test]
fn a_sunshine_down_for_a_minute_is_restarted() {
    let mut watch = Watch::default();
    watch.step(secs(0), false, false);

    assert_eq!(watch.step(DOWN_FOR, false, false), Step::Restart);
}

#[test]
fn a_live_stream_is_never_restarted_and_the_minute_starts_again_after_it() {
    let mut watch = Watch::default();
    watch.step(secs(0), false, false);

    assert_eq!(watch.step(secs(50), false, true), Step::Fine);
    assert_eq!(watch.step(secs(70), false, false), Step::Wait);
    assert_eq!(watch.step(secs(70) + DOWN_FOR, false, false), Step::Restart);
}

#[test]
fn a_restart_is_not_repeated_within_the_restart_gap() {
    let mut watch = Watch::default();
    watch.step(secs(0), false, false);
    assert_eq!(watch.step(DOWN_FOR, false, false), Step::Restart);

    assert_eq!(watch.step(secs(120), false, false), Step::Wait);
    assert_eq!(watch.step(secs(180), false, false), Step::Wait);
    assert_eq!(
        watch.step(DOWN_FOR + RESTART_GAP, false, false),
        Step::Restart
    );
}
