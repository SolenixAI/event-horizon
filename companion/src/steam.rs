//! What Steam has installed on this PC. Shared by the Windows and Linux game
//! sources: only the Steam folder differs between them.

use std::fs;
use std::path::{Path, PathBuf};

/// One installed Steam game.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SteamGame {
    pub appid: String,
    pub name: String,
}

/// Steam's own runtimes and tools are installed like games; they are not.
const TOOLS: [&str; 3] = ["Proton", "Steam Linux Runtime", "Steamworks Common"];

/// Every installed game in every library folder `steam_root` knows about.
/// A missing or unreadable Steam folder is an empty library.
pub fn installed(steam_root: &Path) -> Vec<SteamGame> {
    libraries(steam_root)
        .iter()
        .flat_map(|library| {
            fs::read_dir(library.join("steamapps"))
                .into_iter()
                .flatten()
        })
        .flatten()
        .map(|entry| entry.path())
        .filter(|path| {
            path.file_name()
                .and_then(|n| n.to_str())
                .is_some_and(|n| n.starts_with("appmanifest_") && n.ends_with(".acf"))
        })
        .filter_map(|path| fs::read_to_string(path).ok())
        .filter_map(|text| {
            let fields = pairs(&text);
            let get = |key: &str| {
                fields
                    .iter()
                    .find(|(k, _)| k == key)
                    .map(|(_, v)| v.clone())
            };
            Some(SteamGame {
                appid: get("appid")?,
                name: get("name")?,
            })
        })
        .filter(|game| !TOOLS.iter().any(|tool| game.name.starts_with(tool)))
        .collect()
}

/// The root plus every `path` in libraryfolders.vdf, without repeats.
fn libraries(steam_root: &Path) -> Vec<PathBuf> {
    let mut found = vec![steam_root.to_path_buf()];
    if let Ok(text) = fs::read_to_string(steam_root.join("steamapps/libraryfolders.vdf")) {
        for (key, value) in pairs(&text) {
            let path = PathBuf::from(value);
            if key == "path" && !found.contains(&path) {
                found.push(path);
            }
        }
    }
    found
}

/// The `"key" "value"` pairs of a Valve KeyValues text, in order, nesting
/// ignored. Values are unescaped (`\\` → `\`, `\"` → `"`).
fn pairs(text: &str) -> Vec<(String, String)> {
    let mut tokens = Vec::new();
    let mut chars = text.chars();
    while let Some(c) = chars.next() {
        if c == '{' || c == '}' {
            tokens.push(None);
        } else if c == '"' {
            let mut token = String::new();
            while let Some(c) = chars.next() {
                match c {
                    '\\' => token.extend(chars.next()),
                    '"' => break,
                    c => token.push(c),
                }
            }
            tokens.push(Some(token));
        }
    }
    tokens
        .windows(2)
        .filter_map(|w| match w {
            [Some(k), Some(v)] => Some((k.clone(), v.clone())),
            _ => None,
        })
        .collect()
}

/// The game's tall 2:3 cover from Steam's library cache. Steam names it
/// `library_600x900*.jpg` (older clients) or `library_capsule*.jpg`, and
/// newer clients keep it one hashed folder down.
pub fn cover(steam_root: &Path, appid: &str) -> Option<PathBuf> {
    let dir = steam_root.join("appcache/librarycache").join(appid);
    let mut files = Vec::new();
    collect_files(&dir, 2, &mut files);
    ["library_600x900", "library_capsule"]
        .iter()
        .find_map(|stem| {
            files
                .iter()
                .find(|path| {
                    path.file_name()
                        .and_then(|n| n.to_str())
                        .is_some_and(|n| n.starts_with(stem) && n.ends_with(".jpg"))
                })
                .cloned()
        })
}

fn collect_files(dir: &Path, depth: u8, out: &mut Vec<PathBuf>) {
    let Ok(entries) = fs::read_dir(dir) else {
        return;
    };
    for path in entries.flatten().map(|e| e.path()) {
        if path.is_dir() {
            if depth > 1 {
                collect_files(&path, depth - 1, out);
            }
        } else {
            out.push(path);
        }
    }
}
