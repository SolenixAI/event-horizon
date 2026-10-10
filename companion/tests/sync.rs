//! The library sync: the PC's games reach Sunshine's apps through its API.

mod common;

use common::{FakeGames, FakeSunshine};
use event_horizon_companion::library::{Change, LibraryGame, keep_in_step, sync};
use serde_json::json;
use std::time::Duration;
use tokio::time::Instant;

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

#[tokio::test(start_paused = true)]
async fn the_first_sync_retries_with_backoff_until_sunshine_answers() {
    let sunshine = FakeSunshine::default();
    sunshine.go_down();
    let games = FakeGames(vec![game("1", "ARC Raiders")]);
    let up = sunshine.clone();
    tokio::spawn(async move {
        tokio::time::sleep(Duration::from_secs(12)).await;
        up.come_up();
    });
    let start = Instant::now();
    let mut attempts = Vec::new();

    let _ = tokio::time::timeout(
        Duration::from_secs(700),
        keep_in_step(&sunshine, &games, |outcome| {
            attempts.push((start.elapsed().as_secs(), outcome.is_ok()));
        }),
    )
    .await;

    assert_eq!(
        attempts,
        vec![(0, false), (2, false), (6, false), (14, true), (614, true)]
    );
    assert_eq!(
        sunshine.apps.lock().unwrap()["apps"][0]["name"],
        "ARC Raiders"
    );
}

#[tokio::test(start_paused = true)]
async fn after_sunshine_answers_a_later_outage_waits_ten_minutes() {
    let sunshine = FakeSunshine::default();
    let games = FakeGames(vec![game("1", "ARC Raiders")]);
    let down = sunshine.clone();
    tokio::spawn(async move {
        tokio::time::sleep(Duration::from_secs(601)).await;
        down.go_down();
    });
    let start = Instant::now();
    let mut attempts = Vec::new();

    let _ = tokio::time::timeout(
        Duration::from_secs(1300),
        keep_in_step(&sunshine, &games, |outcome| {
            attempts.push((start.elapsed().as_secs(), outcome.is_ok()));
        }),
    )
    .await;

    assert_eq!(attempts, vec![(0, true), (600, true), (1200, false)]);
}
