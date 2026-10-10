//! `play`: open a Steam game for Sunshine, waiting out a pending update, and
//! stay open for as long as the game runs.

use event_horizon_companion::play::{self, GameSession, refused_since};
use std::cell::Cell;
use std::path::Path;
use std::time::Duration;

const LOG: &str = "\
[2026-10-09 19:00:01] Game process added : AppID 1808500 \"...\"
[2026-10-09 20:10:05] LaunchApp failed: AppID 1808500, update required
[2026-10-09 20:10:06] LaunchApp failed: AppID 2694490, update required
";

#[test]
fn a_refusal_after_we_started_counts() {
    assert!(refused_since(LOG, "1808500", "2026-10-09 20:10:00"));
}

#[test]
fn a_refusal_before_we_started_does_not() {
    assert!(!refused_since(LOG, "1808500", "2026-10-09 20:11:00"));
}

#[test]
fn another_games_refusal_does_not() {
    assert!(!refused_since(LOG, "1623730", "2026-10-09 20:00:00"));
    assert!(
        !refused_since(LOG, "180850", "2026-10-09 20:00:00"),
        "a prefix of another id"
    );
}

#[test]
fn a_flatpak_steam_is_opened_through_flatpak() {
    let root = Path::new("/home/deck/.var/app/com.valvesoftware.Steam/.local/share/Steam");
    assert_eq!(
        play::launch_command(root, "1808500"),
        [
            "flatpak",
            "run",
            "com.valvesoftware.Steam",
            "steam://rungameid/1808500"
        ]
    );
}

#[test]
fn a_native_steam_is_opened_directly() {
    let root = Path::new("/home/deck/.local/share/Steam");
    assert_eq!(
        play::launch_command(root, "1808500"),
        ["steam", "steam://rungameid/1808500"]
    );
}

/// A PC with one game. Time is simulated: `pause` moves the clock on, and
/// the game runs while `starts_at <= clock < closes_at`.
struct FakeGame {
    clock: Cell<u64>,
    starts_at: u64,
    closes_at: u64,
    refuses: bool,
    installed: bool,
    opens: Cell<u32>,
    /// The clock at each check, so a test can see when `play` returned.
    returned_at: Cell<u64>,
}

impl FakeGame {
    fn new(starts_at: u64, closes_at: u64) -> Self {
        Self {
            clock: Cell::new(0),
            starts_at,
            closes_at,
            refuses: false,
            installed: true,
            opens: Cell::new(0),
            returned_at: Cell::new(0),
        }
    }

    fn never_starts() -> Self {
        Self::new(u64::MAX, u64::MAX)
    }

    fn refusing(self) -> Self {
        Self {
            refuses: true,
            ..self
        }
    }

    fn still_updating(self) -> Self {
        Self {
            installed: false,
            ..self
        }
    }

    /// Run `play` against this PC and record the clock when it returns.
    fn play(&self) {
        play::play_game(self);
        self.returned_at.set(self.clock.get());
    }
}

impl GameSession for FakeGame {
    fn open(&self) {
        self.opens.set(self.opens.get() + 1);
    }

    fn running(&self) -> bool {
        let now = self.clock.get();
        self.starts_at <= now && now < self.closes_at
    }

    fn refused_since(&self, _since: &str) -> bool {
        self.refuses
    }

    fn up_to_date(&self) -> bool {
        self.installed
    }

    fn now(&self) -> String {
        "2026-10-10 12:00:00".into()
    }

    fn pause(&self, every: Duration) {
        self.clock.set(self.clock.get() + every.as_secs());
    }
}

#[test]
fn stays_open_while_the_game_runs_and_returns_once_it_closes() {
    let game = FakeGame::new(12, 600);

    game.play();

    let returned = game.returned_at.get();
    assert!(
        (600..=603).contains(&returned),
        "returned at {returned}s; the game ran until 600s"
    );
    assert_eq!(game.opens.get(), 1);
}

#[test]
fn a_game_already_running_at_launch_is_waited_for_too() {
    let game = FakeGame::new(0, 300);

    game.play();

    let returned = game.returned_at.get();
    assert!(
        (300..=303).contains(&returned),
        "returned at {returned}s; the game ran until 300s"
    );
}

#[test]
fn gives_up_after_fifteen_minutes_when_the_game_never_starts() {
    let game = FakeGame::never_starts();

    game.play();

    assert_eq!(game.returned_at.get(), 900);
    assert_eq!(game.opens.get(), 1);
}

#[test]
fn relaunches_once_when_steam_refuses_an_update_then_stays_open() {
    let game = FakeGame::new(20, 100).refusing();

    game.play();

    assert_eq!(game.opens.get(), 2, "opened again after the refusal");
    let returned = game.returned_at.get();
    assert!(
        (100..=103).contains(&returned),
        "returned at {returned}s; the game ran until 100s"
    );
}

#[test]
fn a_refusal_while_the_game_is_still_updating_does_not_relaunch() {
    let game = FakeGame::never_starts().refusing().still_updating();

    game.play();

    assert_eq!(game.opens.get(), 1);
    assert_eq!(game.returned_at.get(), 900);
}

#[test]
fn relaunches_at_most_once() {
    let game = FakeGame::never_starts().refusing();

    game.play();

    assert_eq!(game.opens.get(), 2);
    let returned = game.returned_at.get();
    assert!(
        (900..=905).contains(&returned),
        "gave up at {returned}s; the cap is 15 minutes plus the relaunch pause"
    );
}
