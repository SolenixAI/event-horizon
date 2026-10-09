//! The PC's Steam games as shelf games. Same on Windows and Linux; only the
//! Steam folder and the play command differ, and `main` picks those.

use crate::library::LibraryGame;
use crate::ports::GameSources;
use crate::steam;
use std::collections::HashMap;
use std::path::{Path, PathBuf};

pub struct SteamGames {
    pub steam_root: PathBuf,
    /// Where PNG covers go: a folder Sunshine can read.
    pub covers: PathBuf,
    /// The command that opens a game, followed by its app id.
    pub play: String,
    /// Games opened their own way instead (app id → command).
    pub overrides: HashMap<String, String>,
}

impl GameSources for SteamGames {
    fn installed(&self) -> Vec<LibraryGame> {
        steam::installed(&self.steam_root)
            .into_iter()
            .map(|game| LibraryGame {
                launch: self
                    .overrides
                    .get(&game.appid)
                    .cloned()
                    .unwrap_or_else(|| format!("{} {}", self.play, game.appid)),
                cover: self.cover(&game.appid),
                id: game.appid,
                name: game.name,
            })
            .collect()
    }
}

impl SteamGames {
    /// Steam's JPEG cover as a PNG (Sunshine serves PNG only), redone only
    /// when Steam's copy is newer.
    fn cover(&self, appid: &str) -> Option<String> {
        let source = steam::cover(&self.steam_root, appid)?;
        let target = self.covers.join(format!("{appid}.png"));
        if is_stale(&target, &source) {
            std::fs::create_dir_all(&self.covers).ok()?;
            image::open(&source).ok()?.save(&target).ok()?;
        }
        Some(target.to_string_lossy().into_owned())
    }
}

fn is_stale(target: &Path, source: &Path) -> bool {
    let modified = |p: &Path| std::fs::metadata(p).and_then(|m| m.modified()).ok();
    match (modified(target), modified(source)) {
        (Some(t), Some(s)) => t < s,
        _ => true,
    }
}

/// Where Steam lives on this PC, if it is installed.
pub fn steam_root() -> Option<PathBuf> {
    #[cfg(windows)]
    let candidates = vec![
        PathBuf::from(r"C:\Program Files (x86)\Steam"),
        PathBuf::from(r"C:\Program Files\Steam"),
    ];
    #[cfg(not(windows))]
    let candidates = {
        let home = PathBuf::from(std::env::var_os("HOME").unwrap_or_default());
        vec![
            home.join(".steam/root"),
            home.join(".local/share/Steam"),
            home.join(".var/app/com.valvesoftware.Steam/.local/share/Steam"),
        ]
    };
    candidates
        .into_iter()
        .filter_map(|path| path.canonicalize().ok())
        .find(|path| path.join("steamapps").is_dir())
}
