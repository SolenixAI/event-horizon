//! The PC's games as Sunshine apps. Matches by name; adds what is missing,
//! fixes a drifted launcher or cover, and leaves every other field (and
//! every app it does not know) as the user set it. The cross-platform form
//! of the tower's `sunshine-steam-sync` script.

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
