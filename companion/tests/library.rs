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
fn adds_a_missing_game_with_its_launcher_and_cover() {
    let mut apps = json!({ "apps": [ { "name": "Desktop", "image-path": "desktop.png" } ] });

    let changes = merge(&mut apps, &[game("1808500", "ARC Raiders")]);

    assert_eq!(changes, vec![Change::Added("ARC Raiders".into())]);
    assert_eq!(apps["apps"][1]["name"], "ARC Raiders");
    assert_eq!(apps["apps"][1]["detached"], json!(["steam-play 1808500"]));
    assert_eq!(apps["apps"][1]["image-path"], "/covers/1808500.png");
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
fn fixes_a_drifted_launcher_and_keeps_the_users_own_settings() {
    let mut apps = json!({ "apps": [ {
        "name": "ARC Raiders", "detached": ["old-launcher"], "image-path": "/covers/1808500.png",
        "prep-cmd": [ { "do": "my-script" } ]
    } ] });

    let changes = merge(&mut apps, &[game("1808500", "ARC Raiders")]);

    assert_eq!(changes, vec![Change::Updated("ARC Raiders".into())]);
    assert_eq!(apps["apps"][0]["detached"], json!(["steam-play 1808500"]));
    assert_eq!(
        apps["apps"][0]["prep-cmd"],
        json!([ { "do": "my-script" } ])
    );
}

#[test]
fn a_game_without_cover_art_keeps_the_cover_it_had() {
    let mut apps = json!({ "apps": [ { "name": "Palworld", "detached": ["steam-play 1623730"], "image-path": "/mine.png" } ] });
    let no_cover = LibraryGame {
        cover: None,
        ..game("1623730", "Palworld")
    };

    assert!(merge(&mut apps, &[no_cover]).is_empty());
    assert_eq!(apps["apps"][0]["image-path"], "/mine.png");
}
