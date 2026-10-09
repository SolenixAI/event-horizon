//! The PC's games as Sunshine apps. Matches by name; adds what is missing,
//! fixes a drifted launcher or cover, and leaves every other field (and
//! every app it does not know) as the user set it. The cross-platform form
//! of the tower's `sunshine-steam-sync` script.

use crate::ports::{GameSources, SunshineApi, SunshineError};
use serde_json::{Value, json};

/// A game to offer on the Mac's shelf.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct LibraryGame {
    pub id: String,
    pub name: String,
    /// The command Sunshine runs, detached, to open it.
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
        let wanted_launch = json!([game.launch]);
        match apps.iter_mut().find(|app| app["name"] == game.name) {
            None => {
                let mut app = json!({
                    "name": game.name,
                    "detached": wanted_launch,
                    "auto-detach": true,
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
                let mut drifted = false;
                if app["detached"] != wanted_launch {
                    app["detached"] = wanted_launch;
                    drifted = true;
                }
                if let Some(cover) = &game.cover
                    && app["image-path"] != json!(cover)
                {
                    app["image-path"] = json!(cover);
                    drifted = true;
                }
                if drifted {
                    changes.push(Change::Updated(game.name.clone()));
                }
            }
        }
    }
    changes
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
