//! Steam games as shelf games: launch command, override, PNG cover.

use event_horizon_companion::GameSources;
use event_horizon_companion::games::SteamGames;
use std::collections::HashMap;
use std::fs;
use std::path::Path;

fn manifest(root: &Path, appid: &str, name: &str) {
    let dir = root.join("steamapps");
    fs::create_dir_all(&dir).unwrap();
    fs::write(
        dir.join(format!("appmanifest_{appid}.acf")),
        format!("\"AppState\"\n{{\n\t\"appid\"\t\t\"{appid}\"\n\t\"name\"\t\t\"{name}\"\n}}\n"),
    )
    .unwrap();
}

fn jpeg(path: &Path) {
    fs::create_dir_all(path.parent().unwrap()).unwrap();
    image::RgbImage::from_pixel(6, 9, image::Rgb([200, 120, 20]))
        .save(path)
        .unwrap();
}

#[test]
fn each_game_opens_through_play_unless_it_has_its_own_launcher() {
    let steam = tempfile::tempdir().unwrap();
    let covers = tempfile::tempdir().unwrap();
    manifest(steam.path(), "1808500", "ARC Raiders");
    manifest(steam.path(), "1343370", "Old School RuneScape");
    let source = SteamGames {
        steam_root: steam.path().into(),
        covers: covers.path().into(),
        play: "companion play".into(),
        overrides: HashMap::from([("1343370".into(), "jagex-launcher".into())]),
    };

    let mut games = source.installed();
    games.sort_by(|a, b| a.name.cmp(&b.name));

    assert_eq!(games[0].launch, "companion play 1808500");
    assert_eq!(games[1].launch, "jagex-launcher");
}

#[test]
fn the_steam_cover_becomes_a_png_sunshine_can_serve() {
    let steam = tempfile::tempdir().unwrap();
    let covers = tempfile::tempdir().unwrap();
    manifest(steam.path(), "1808500", "ARC Raiders");
    jpeg(
        &steam
            .path()
            .join("appcache/librarycache/1808500/ab12/library_600x900.jpg"),
    );
    let source = SteamGames {
        steam_root: steam.path().into(),
        covers: covers.path().into(),
        play: "play".into(),
        overrides: HashMap::new(),
    };

    let games = source.installed();

    let cover = games[0].cover.as_deref().expect("a cover");
    assert!(cover.ends_with("1808500.png"));
    assert_eq!(image::open(cover).unwrap().into_rgb8().dimensions(), (6, 9));
}
