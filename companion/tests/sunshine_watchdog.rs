use event_horizon_companion::sunshine_watchdog::{
    DOWN_FOR, RESTART_GAP, Step, Watch, has_stale_nvidia_extension, nvidia_extension_commits,
};
use std::collections::HashMap;
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

const FLATPAK_INSTANCE: &str = "[Runtime]\nruntime-extensions=org.freedesktop.Platform.GL.nvidia-999=wrong-section\n\n[Instance]\nruntime-extensions=org.kde.Platform.Locale=locale;org.freedesktop.Platform.GL.nvidia-615-71-09=running-commit;org.freedesktop.Platform.GL.default=mesa\n";

#[test]
fn nvidia_extension_commits_are_read_from_the_instance_section() {
    assert_eq!(
        nvidia_extension_commits(FLATPAK_INSTANCE),
        vec![(
            "org.freedesktop.Platform.GL.nvidia-615-71-09".to_string(),
            "running-commit".to_string()
        )]
    );
}

#[test]
fn an_instance_with_the_active_nvidia_commit_is_not_stale() {
    let active = HashMap::from([(
        "org.freedesktop.Platform.GL.nvidia-615-71-09".to_string(),
        "running-commit".to_string(),
    )]);

    assert!(!has_stale_nvidia_extension(FLATPAK_INSTANCE, &active));
}

#[test]
fn an_instance_with_an_old_nvidia_commit_is_stale() {
    let active = HashMap::from([(
        "org.freedesktop.Platform.GL.nvidia-615-71-09".to_string(),
        "updated-commit".to_string(),
    )]);

    assert!(has_stale_nvidia_extension(FLATPAK_INSTANCE, &active));
}

#[test]
fn a_missing_active_commit_does_not_trigger_a_restart() {
    assert!(!has_stale_nvidia_extension(
        FLATPAK_INSTANCE,
        &HashMap::new()
    ));
}

#[test]
fn a_stale_nvidia_instance_is_restarted_immediately_but_never_during_a_stream() {
    let mut watch = Watch::default();

    assert_eq!(
        watch.step_with_stale_nvidia_extension(secs(0), true, false, true),
        Step::Restart
    );
    assert_eq!(
        watch.step_with_stale_nvidia_extension(secs(15), true, true, true),
        Step::Fine
    );
    assert_eq!(
        watch.step_with_stale_nvidia_extension(secs(30), true, false, true),
        Step::Wait
    );
}
