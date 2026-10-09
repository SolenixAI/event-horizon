//! The library sync: the PC's games reach Sunshine's apps through its API.

mod common;

use common::{FakeGames, FakeSunshine};
use event_horizon_companion::library::{Change, LibraryGame, sync};
use serde_json::json;

fn game(id: &str, name: &str) -> LibraryGame {
    LibraryGame {
        id: id.into(),
        name: name.into(),
        launch: format!("play {id}"),
        cover: None,
    }
}

#[tokio::test]
async fn adds_every_missing_game_and_keeps_the_users_apps() {
    let sunshine = FakeSunshine::default();
    *sunshine.apps.lock().unwrap() =
        json!({ "apps": [ { "name": "Desktop" }, { "name": "Steam Big Picture" } ], "env": {} });
    let games = FakeGames(vec![game("2", "Palworld"), game("1", "ARC Raiders")]);

    let changes = sync(&sunshine, &games).await.unwrap();

    assert_eq!(
        changes,
        vec![
            Change::Added("Palworld".into()),
            Change::Added("ARC Raiders".into())
        ]
    );
    let names: Vec<_> = sunshine.apps.lock().unwrap()["apps"]
        .as_array()
        .unwrap()
        .iter()
        .map(|a| a["name"].as_str().unwrap().to_string())
        .collect();
    assert_eq!(
        names,
        vec!["ARC Raiders", "Desktop", "Palworld", "Steam Big Picture"]
    );
}

#[tokio::test]
async fn fixes_a_drifted_game_in_place_even_after_sunshine_reorders() {
    let sunshine = FakeSunshine::default();
    *sunshine.apps.lock().unwrap() = json!({ "apps": [
        { "name": "ARC Raiders", "detached": ["old"] },
        { "name": "Desktop" },
        { "name": "Palworld", "detached": ["old"] },
    ], "env": {} });
    let games = FakeGames(vec![game("2", "Palworld"), game("1", "ARC Raiders")]);

    sync(&sunshine, &games).await.unwrap();

    let apps = sunshine.apps.lock().unwrap().clone();
    assert_eq!(apps["apps"].as_array().unwrap().len(), 3, "no duplicates");
    assert_eq!(apps["apps"][0]["detached"], json!(["play 1"]));
    assert_eq!(apps["apps"][2]["detached"], json!(["play 2"]));
}

#[tokio::test]
async fn a_synced_pc_takes_no_saves() {
    let sunshine = FakeSunshine::default();
    let games = FakeGames(vec![game("1", "ARC Raiders")]);
    sync(&sunshine, &games).await.unwrap();
    let saves = *sunshine.saves.lock().unwrap();

    assert!(sync(&sunshine, &games).await.unwrap().is_empty());
    assert_eq!(*sunshine.saves.lock().unwrap(), saves);
}
