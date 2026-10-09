//! Which of Sunshine's waiting pairings belongs to the Mac that asked.

use event_horizon_companion::sunshine::pairing_for;
use serde_json::json;

#[test]
fn picks_the_pairing_started_by_that_mac() {
    let pending = json!({ "pairings": [
        { "id": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "name": "Living room TV", "address": "10.0.0.9" },
        { "id": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", "name": "Jager's MacBook Air", "address": "10.0.0.4" },
    ]});

    assert_eq!(
        pairing_for(&pending, "Jager's MacBook Air").as_deref(),
        Some("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")
    );
}

#[test]
fn the_newest_wins_when_the_same_mac_asked_twice() {
    let pending = json!({ "pairings": [
        { "id": "11111111111111111111111111111111", "name": "Mac", "address": "10.0.0.4" },
        { "id": "22222222222222222222222222222222", "name": "Mac", "address": "10.0.0.4" },
    ]});

    assert_eq!(
        pairing_for(&pending, "Mac").as_deref(),
        Some("22222222222222222222222222222222")
    );
}

#[test]
fn no_waiting_pairing_from_that_mac_is_none() {
    assert_eq!(pairing_for(&json!({ "pairings": [] }), "Mac"), None);
    assert_eq!(pairing_for(&json!({}), "Mac"), None);
}
