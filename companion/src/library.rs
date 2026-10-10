//! The PC's games as Sunshine apps. Matches by name; adds what is missing,
//! fixes a drifted launcher or cover, and leaves every other field (and
//! every app it does not know) as the user set it. The cross-platform form
//! of the tower's `sunshine-steam-sync` script.

use crate::ports::{GameSources, SunshineApi, SunshineError};
use serde_json::{Value, json};
use std::time::Duration;

/// The wait between syncs once Sunshine has answered.
pub const SYNC_EVERY: Duration = Duration::from_secs(600);
/// Before Sunshine first answers, each retry doubles the wait, up to this cap.
const FIRST_RETRY: Duration = Duration::from_secs(2);
const MAX_RETRY: Duration = Duration::from_secs(30);

/// A game to offer on the Mac's shelf.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct LibraryGame {
    pub id: String,
    pub name: String,
    /// The command Sunshine runs to open it. Sunshine keeps the game current
    /// until this exits, so it must stay running while the game does.
    pub launch: String,
    /// A PNG Sunshine can serve as the cover.
    pub cover: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Change {
    Added(String),
    Updated(String),
}

/// Merge `games` into Sunshine's apps document (`{"apps": [...]}`).
/// Returns what changed; empty means the document is untouched.
pub fn merge(document: &mut Value, games: &[LibraryGame]) -> Vec<Change> {
    if !document["apps"].is_array() {
        document["apps"] = json!([]);
    }
    let apps = document["apps"].as_array_mut().expect("apps is an array");
    let mut changes = Vec::new();
    for game in games {
        match apps.iter_mut().find(|app| app["name"] == game.name) {
            None => {
                let mut app = json!({
                    "name": game.name,
                    "cmd": game.launch,
                    "auto-detach": false,
                    "wait-all": true,
                    "exit-timeout": 5,
                });
                if let Some(cover) = &game.cover {
                    app["image-path"] = json!(cover);
                }
                apps.push(app);
                changes.push(Change::Added(game.name.clone()));
            }
            Some(app) => {
                if settle(app, game) {
                    changes.push(Change::Updated(game.name.clone()));
                }
            }
        }
    }
    changes
}

/// Sets the fields that keep the game current in Sunshine, and its cover.
/// Returns whether anything changed.
fn settle(app: &mut Value, game: &LibraryGame) -> bool {
    let mut drifted = retire_old_launcher(app, &game.launch);
    for (field, wanted) in [
        ("cmd", json!(game.launch)),
        ("auto-detach", json!(false)),
        ("wait-all", json!(true)),
    ] {
        if app[field] != wanted {
            app[field] = wanted;
            drifted = true;
        }
    }
    if let Some(cover) = &game.cover
        && app["image-path"] != json!(cover)
    {
        app["image-path"] = json!(cover);
        drifted = true;
    }
    drifted
}

/// Older companions ran the launcher as a detached command. Removes it,
/// and keeps any other detached command the user added.
fn retire_old_launcher(app: &mut Value, launch: &str) -> bool {
    let Some(commands) = app["detached"].as_array() else {
        return false;
    };
    if !commands.iter().any(|c| c.as_str() == Some(launch)) {
        return false;
    }
    let kept: Vec<Value> = commands
        .iter()
        .filter(|c| c.as_str() != Some(launch))
        .cloned()
        .collect();
    if kept.is_empty() {
        if let Some(object) = app.as_object_mut() {
            object.remove("detached");
        }
    } else {
        app["detached"] = json!(kept);
    }
    true
}

/// Bring Sunshine's apps in line with the PC's games, one save per change.
/// Sunshine re-sorts its list after every save, so each save re-reads it.
pub async fn sync<S: SunshineApi, G: GameSources>(
    sunshine: &S,
    games: &G,
) -> Result<Vec<Change>, SunshineError> {
    let mut changes = Vec::new();
    for game in games.installed() {
        let mut document = sunshine.apps().await?;
        let existing = document["apps"]
            .as_array()
            .and_then(|apps| apps.iter().position(|app| app["name"] == game.name));
        let Some(change) = merge(&mut document, std::slice::from_ref(&game)).pop() else {
            continue;
        };
        let apps = document["apps"]
            .as_array()
            .expect("merge leaves an apps array");
        let app = apps
            .iter()
            .find(|app| app["name"] == game.name)
            .expect("merge keeps the game it changed")
            .clone();
        let index = existing.map_or(-1, |i| i as i64);
        sunshine.save_app(index, app).await?;
        changes.push(change);
    }
    Ok(changes)
}

/// Keeps the PC's games in Sunshine's apps for as long as it runs. Until
/// Sunshine first answers, it retries with backoff, since Sunshine starts
/// a few seconds after the companion. After that it syncs every
/// `SYNC_EVERY`, even through later outages. `report` hears each attempt.
pub async fn keep_in_step<S: SunshineApi, G: GameSources>(
    sunshine: &S,
    games: &G,
    mut report: impl FnMut(&Result<Vec<Change>, SunshineError>),
) {
    let mut answered = false;
    let mut retry = FIRST_RETRY;
    loop {
        let outcome = sync(sunshine, games).await;
        report(&outcome);
        if !matches!(outcome, Err(SunshineError::Unreachable(_))) {
            answered = true;
        }
        let wait = if answered {
            SYNC_EVERY
        } else {
            let wait = retry;
            retry = (retry * 2).min(MAX_RETRY);
            wait
        };
        tokio::time::sleep(wait).await;
    }
}
