//! Reading what Steam has installed, across every Steam library folder.

use event_horizon_companion::steam;
use std::fs;
use std::path::Path;

fn manifest(library: &Path, appid: &str, name: &str) {
    let dir = library.join("steamapps");
    fs::create_dir_all(&dir).unwrap();
    fs::write(
        dir.join(format!("appmanifest_{appid}.acf")),
        format!("\"AppState\"\n{{\n\t\"appid\"\t\t\"{appid}\"\n\t\"name\"\t\t\"{name}\"\n\t\"StateFlags\"\t\t\"4\"\n}}\n"),
    )
    .unwrap();
}

fn library_folders(root: &Path, libraries: &[&Path]) {
    let mut vdf = String::from("\"libraryfolders\"\n{\n");
    for (i, path) in libraries.iter().enumerate() {
        // Steam escapes the backslashes of Windows paths in its VDF files.
        let escaped = path.display().to_string().replace('\\', "\\\\");
        vdf += &format!("\t\"{i}\"\n\t{{\n\t\t\"path\"\t\t\"{escaped}\"\n\t}}\n");
    }
    vdf += "}\n";
    fs::create_dir_all(root.join("steamapps")).unwrap();
    fs::write(root.join("steamapps/libraryfolders.vdf"), vdf).unwrap();
}

#[test]
fn lists_games_from_every_library_and_skips_steam_tools() {
    let root = tempfile::tempdir().unwrap();
    let second = tempfile::tempdir().unwrap();
    library_folders(root.path(), &[root.path(), second.path()]);
    manifest(root.path(), "1808500", "ARC Raiders");
    manifest(root.path(), "1493710", "Proton Experimental");
    manifest(second.path(), "2694490", "Path of Exile 2");

    let mut games = steam::installed(root.path());
    games.sort_by(|a, b| a.name.cmp(&b.name));

    let names: Vec<_> = games
        .iter()
        .map(|g| (g.appid.as_str(), g.name.as_str()))
        .collect();
    assert_eq!(
        names,
        vec![("1808500", "ARC Raiders"), ("2694490", "Path of Exile 2")]
    );
}

#[test]
fn a_missing_steam_folder_is_an_empty_library_not_an_error() {
    assert!(steam::installed(Path::new("/nonexistent/steam")).is_empty());
}
