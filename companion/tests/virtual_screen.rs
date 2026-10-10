//! The rules of the Linux virtual screen: its size, its unit, its placement,
//! Sunshine's settings, and when it applies at all.

use event_horizon_companion::linux_install;
use event_horizon_companion::virtual_screen::{
    DEFAULT_SIZE, Size, is_kde_wayland, placement_args, screen_size, unit_text, with_setting,
};
use serde_json::json;
use std::path::Path;

#[test]
fn a_size_reads_as_width_by_height() {
    assert_eq!(DEFAULT_SIZE.to_string(), "2560x1600");
}

#[test]
fn the_screen_is_2560_by_1600_until_the_mac_reports_its_size() {
    let mac = Size {
        width: 1470,
        height: 956,
    };

    assert_eq!(screen_size(None), DEFAULT_SIZE);
    assert_eq!(screen_size(Some(mac)), mac);
}

#[test]
fn a_setting_is_replaced_in_place_and_the_other_lines_stay() {
    let text = "a = 1\noutput_name = 0\nb = 2\n";

    assert_eq!(
        with_setting(text, "output_name", "Virtual-x"),
        "a = 1\noutput_name = Virtual-x\nb = 2\n"
    );
}

#[test]
fn a_missing_setting_is_added_at_the_end() {
    assert_eq!(with_setting("a = 1\n", "k", "v"), "a = 1\nk = v\n");
    assert_eq!(with_setting("", "k", "v"), "k = v\n");
}

#[test]
fn a_setting_is_not_mistaken_for_a_longer_key() {
    let text = "output_name_extra = 9\n";

    assert_eq!(
        with_setting(text, "output_name", "Virtual-x"),
        "output_name_extra = 9\noutput_name = Virtual-x\n"
    );
}

#[test]
fn the_screen_runs_only_on_kde_on_wayland() {
    assert!(is_kde_wayland(Some("wayland"), Some("KDE")));
    assert!(!is_kde_wayland(Some("x11"), Some("KDE")));
    assert!(!is_kde_wayland(Some("wayland"), Some("GNOME")));
    assert!(!is_kde_wayland(Some("wayland"), None));
    assert!(!is_kde_wayland(None, Some("KDE")));
}

#[test]
fn the_placement_is_none_until_kscreen_lists_the_screen() {
    let before = json!({ "outputs": [
        { "name": "DP-1", "enabled": true, "size": { "width": 1920, "height": 1080 }, "scale": 1.0 }
    ]});

    assert_eq!(placement_args(&before), None);
}

#[test]
fn the_unit_quotes_a_path_that_has_a_space() {
    let password = linux_install::random_secret();
    let text = unit_text(
        Path::new("/opt/Krfb Tools/krfb-virtualmonitor"),
        Path::new("/home/friend/.local/bin/event-horizon-companion"),
        DEFAULT_SIZE,
        &password,
    );

    assert!(text.contains(&format!(
        "ExecStart=\"/opt/Krfb Tools/krfb-virtualmonitor\" --resolution 2560x1600 --name sunshine-vmon --port 5905 --password {password}"
    )));
}
