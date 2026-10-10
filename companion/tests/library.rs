//! Syncing the PC's games into Sunshine's apps: add what is missing, fix
//! what drifted, never touch apps the companion did not make.

use event_horizon_companion::library::{Change, LibraryGame, merge};
use serde_json::json;

fn game(id: &str, name: &str) -> LibraryGame {
    LibraryGame {
        id: id.into(),
        name: name.into(),
        launch: format!("steam-play {id}"),
        cover: Some(format!("/covers/{id}.png")),
    }
}

#[test]
fn adds_a_missing_game_as_a_tracked_command_with_its_cover() {
    let mut apps = json!({ "apps": [ { "name": "Desktop", "image-path": "desktop.png" } ] });

    let changes = merge(&mut apps, &[game("1808500", "ARC Raiders")]);

    assert_eq!(changes, vec![Change::Added("ARC Raiders".into())]);
    let added = &apps["apps"][1];
    assert_eq!(added["name"], "ARC Raiders");
    assert_eq!(added["cmd"], "steam-play 1808500");
    assert_eq!(added["auto-detach"], false);
    assert_eq!(added["wait-all"], true);
    assert!(added.get("detached").is_none());
    assert_eq!(added["image-path"], "/covers/1808500.png");
    assert_eq!(
        apps["apps"][0],
        json!({ "name": "Desktop", "image-path": "desktop.png" })
    );
}

#[test]
fn a_second_sync_changes_nothing() {
    let mut apps = json!({ "apps": [] });
    merge(&mut apps, &[game("1808500", "ARC Raiders")]);
    let once = apps.clone();

    let changes = merge(&mut apps, &[game("1808500", "ARC Raiders")]);

    assert!(changes.is_empty());
    assert_eq!(apps, once);
}

#[test]
fn an_app_from_before_the_fix_becomes_a_tracked_command() {
    // The old entry ran its launcher as a detached command with no `cmd`,
    // which Sunshine treats as a placebo app that never ends by itself.
    let mut apps = json!({ "apps": [ {
        "name": "ARC Raiders", "detached": ["steam-play 1808500"],
        "auto-detach": true, "wait-all": true, "image-path": "/covers/1808500.png"
    } ] });

    let changes = merge(&mut apps, &[game("1808500", "ARC Raiders")]);

    assert_eq!(changes, vec![Change::Updated("ARC Raiders".into())]);
    let app = &apps["apps"][0];
    assert_eq!(app["cmd"], "steam-play 1808500");
    assert_eq!(app["auto-detach"], false);
    assert_eq!(app["wait-all"], true);
    assert!(app.get("detached").is_none(), "the old launcher is gone");
}

#[test]
fn the_migration_settles_after_one_sync() {
    let mut apps = json!({ "apps": [ {
        "name": "ARC Raiders", "detached": ["steam-play 1808500"], "auto-detach": true
    } ] });
    merge(&mut apps, &[game("1808500", "ARC Raiders")]);
    let settled = apps.clone();

    assert!(merge(&mut apps, &[game("1808500", "ARC Raiders")]).is_empty());
    assert_eq!(apps, settled);
}

#[test]
fn the_flatpak_launcher_from_before_the_fix_is_retired_too() {
    // Its launcher lacked `--wait`, so it never equals the new `cmd`.
    let mut apps = json!({ "apps": [ {
        "name": "ARC Raiders",
        "detached": ["flatpak-spawn --host setsid /var/home/zephyr/.local/bin/event-horizon-companion play 1808500"]
    } ] });

    merge(&mut apps, &[game("1808500", "ARC Raiders")]);

    assert!(apps["apps"][0].get("detached").is_none());
    assert_eq!(apps["apps"][0]["cmd"], "steam-play 1808500");
}

#[test]
fn a_detached_command_the_user_added_survives_the_migration() {
    let mut apps = json!({ "apps": [ {
        "name": "ARC Raiders", "detached": ["my-overlay", "steam-play 1808500"]
    } ] });

    merge(&mut apps, &[game("1808500", "ARC Raiders")]);

    assert_eq!(apps["apps"][0]["detached"], json!(["my-overlay"]));
    assert_eq!(apps["apps"][0]["cmd"], "steam-play 1808500");
}

#[test]
fn fixes_a_drifted_launcher_and_keeps_the_users_own_settings() {
    let mut apps = json!({ "apps": [ {
        "name": "ARC Raiders", "cmd": "old-launcher", "auto-detach": false, "wait-all": true,
        "image-path": "/covers/1808500.png", "prep-cmd": [ { "do": "my-script" } ]
    } ] });

    let changes = merge(&mut apps, &[game("1808500", "ARC Raiders")]);

    assert_eq!(changes, vec![Change::Updated("ARC Raiders".into())]);
    assert_eq!(apps["apps"][0]["cmd"], "steam-play 1808500");
    assert_eq!(
        apps["apps"][0]["prep-cmd"],
        json!([ { "do": "my-script" } ])
    );
}

#[test]
fn a_game_without_cover_art_keeps_the_cover_it_had() {
    let mut apps = json!({ "apps": [ {
        "name": "Palworld", "cmd": "steam-play 1623730", "auto-detach": false,
        "wait-all": true, "image-path": "/mine.png"
    } ] });
    let no_cover = LibraryGame {
        cover: None,
        ..game("1623730", "Palworld")
    };

    assert!(merge(&mut apps, &[no_cover]).is_empty());
    assert_eq!(apps["apps"][0]["image-path"], "/mine.png");
}
