//! The pairing window: for a short time after the companion is installed, the
//! first Mac pairs with the code on its own screen, so a PC with its monitor
//! off can be set up. Driven through the Prompt the Host sees.

mod common;

use common::FakePrompt;
use event_horizon_companion::pair_window::{self, PairWindow, WINDOW};
use event_horizon_companion::{Decision, Prompt};
use std::time::Duration;

const NOW: u64 = 1_800_000_000;

#[tokio::test]
async fn inside_the_window_the_first_mac_is_allowed_without_asking_the_pc() {
    let dir = tempfile::tempdir().unwrap();
    pair_window::open(dir.path(), NOW).unwrap();
    let pc = FakePrompt::after(None, Duration::ZERO);
    let window = PairWindow::new(pc.clone(), dir.path(), move || NOW + 60);

    assert_eq!(window.ask_allow("Raptor", "123456").await, Decision::Allow);
    assert!(pc.codes.lock().unwrap().is_empty());
}

#[tokio::test]
async fn the_window_lets_one_mac_in_then_the_pc_asks_again() {
    let dir = tempfile::tempdir().unwrap();
    pair_window::open(dir.path(), NOW).unwrap();
    let pc = FakePrompt::answers(Decision::Deny);
    let window = PairWindow::new(pc.clone(), dir.path(), move || NOW + 60);

    assert_eq!(window.ask_allow("Raptor", "111111").await, Decision::Allow);
    assert_eq!(window.ask_allow("Stranger", "222222").await, Decision::Deny);
    assert_eq!(*pc.codes.lock().unwrap(), vec!["222222".to_string()]);
}

#[tokio::test]
async fn after_the_window_closes_the_pc_asks() {
    let dir = tempfile::tempdir().unwrap();
    pair_window::open(dir.path(), NOW).unwrap();
    let pc = FakePrompt::answers(Decision::Deny);
    let late = NOW + WINDOW.as_secs() + 1;
    let window = PairWindow::new(pc.clone(), dir.path(), move || late);

    assert_eq!(window.ask_allow("Raptor", "123456").await, Decision::Deny);
    assert_eq!(*pc.codes.lock().unwrap(), vec!["123456".to_string()]);
}

#[tokio::test]
async fn a_pc_that_never_opened_a_window_asks() {
    let dir = tempfile::tempdir().unwrap();
    let pc = FakePrompt::answers(Decision::Allow);
    let window = PairWindow::new(pc.clone(), dir.path(), move || NOW);

    assert_eq!(window.ask_allow("Raptor", "123456").await, Decision::Allow);
    assert_eq!(*pc.codes.lock().unwrap(), vec!["123456".to_string()]);
}
