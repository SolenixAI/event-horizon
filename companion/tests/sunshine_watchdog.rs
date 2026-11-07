use event_horizon_companion::sunshine_watchdog::{
    DOWN_FOR, RESTART_GAP, Step, Watch, flatpak_installation_option, flatpak_runtime_path,
    has_stale_nvidia_extension, nvidia_extension_commits, nvidia_extension_id,
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

const FLATPAK_INSTANCE: &str = "[Runtime]\nruntime-extensions=org.freedesktop.Platform.GL.nvidia-999=wrong-section\n\n[Instance]\napp-path=/var/home/zephyr/.local/share/flatpak/app/dev.lizardbyte.app.Sunshine/files\nruntime-path=/var/lib/flatpak/runtime/org.kde.Platform/x86_64/6.11/commit/files\nruntime-extensions=org.kde.Platform.Locale=locale;org.freedesktop.Platform.GL.nvidia-615-71-09=running-commit;org.freedesktop.Platform.GL.default=mesa\n";
const CURRENT_NVIDIA_ID: &str = "org.freedesktop.Platform.GL.nvidia-615-71-09";

#[test]
fn nvidia_extension_commits_are_read_from_the_instance_section() {
    assert_eq!(
        nvidia_extension_commits(FLATPAK_INSTANCE),
        vec![(CURRENT_NVIDIA_ID.to_string(), "running-commit".to_string())]
    );
}

#[test]
fn running_flatpak_runtime_path_is_read_from_the_instance_section() {
    assert_eq!(
        flatpak_runtime_path(FLATPAK_INSTANCE),
        Some("/var/lib/flatpak/runtime/org.kde.Platform/x86_64/6.11/commit/files")
    );
    assert_eq!(
        flatpak_runtime_path("[Runtime]\nruntime-path=/wrong-section\n"),
        None
    );
}

#[test]
fn flatpak_commands_use_the_installation_of_the_running_runtime() {
    assert_eq!(
        flatpak_installation_option(
            "/var/home/zephyr/.local/share/flatpak/runtime/org.kde.Platform"
        ),
        Some("--user")
    );
    assert_eq!(
        flatpak_installation_option("/var/lib/flatpak/runtime/org.kde.Platform"),
        Some("--system")
    );
    assert_eq!(
        flatpak_installation_option("/opt/flatpak/app/sunshine"),
        None
    );
}

#[test]
fn flatpak_extension_scope_comes_from_the_running_runtime_not_the_app() {
    let runtime_path = flatpak_runtime_path(FLATPAK_INSTANCE).unwrap();

    assert_eq!(
        flatpak_installation_option(runtime_path),
        Some("--system"),
        "this instance has a user app path and a system runtime path"
    );
}

#[test]
fn host_driver_version_maps_to_the_versioned_nvidia_extension_id() {
    assert_eq!(
        nvidia_extension_id(" 615.71.09\n").as_deref(),
        Some(CURRENT_NVIDIA_ID)
    );
    assert_eq!(nvidia_extension_id("unknown"), None);
}

#[test]
fn an_instance_with_the_active_nvidia_commit_is_not_stale() {
    let active = HashMap::from([(CURRENT_NVIDIA_ID.to_string(), "running-commit".to_string())]);

    assert!(!has_stale_nvidia_extension(
        FLATPAK_INSTANCE,
        &active,
        Some(CURRENT_NVIDIA_ID)
    ));
}

#[test]
fn an_instance_with_an_old_nvidia_commit_is_stale() {
    let active = HashMap::from([(CURRENT_NVIDIA_ID.to_string(), "updated-commit".to_string())]);

    assert!(has_stale_nvidia_extension(
        FLATPAK_INSTANCE,
        &active,
        Some(CURRENT_NVIDIA_ID)
    ));
}

#[test]
fn a_driver_version_change_restarts_when_the_new_extension_is_installed() {
    let updated_id = "org.freedesktop.Platform.GL.nvidia-615-71-10";
    let active = HashMap::from([(updated_id.to_string(), "new-commit".to_string())]);

    assert!(has_stale_nvidia_extension(
        FLATPAK_INSTANCE,
        &active,
        Some(updated_id)
    ));
}

#[test]
fn a_driver_version_change_waits_until_its_extension_is_installed() {
    let active = HashMap::from([(CURRENT_NVIDIA_ID.to_string(), "running-commit".to_string())]);

    assert!(!has_stale_nvidia_extension(
        FLATPAK_INSTANCE,
        &active,
        Some("org.freedesktop.Platform.GL.nvidia-615-71-10")
    ));
}

#[test]
fn a_removed_running_extension_is_stale_when_another_nvidia_ref_is_installed() {
    let updated_id = "org.freedesktop.Platform.GL.nvidia-615-71-10";
    let active = HashMap::from([(updated_id.to_string(), "new-commit".to_string())]);

    assert!(has_stale_nvidia_extension(FLATPAK_INSTANCE, &active, None));
}

#[test]
fn an_empty_or_unavailable_nvidia_installation_is_not_treated_as_stale() {
    assert!(!has_stale_nvidia_extension(
        FLATPAK_INSTANCE,
        &HashMap::new(),
        None
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
