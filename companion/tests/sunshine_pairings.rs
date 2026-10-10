//! Which of Sunshine's waiting pairings belongs to the Mac that asked. The Mac
//! names its Sunshine pairing by its id, so two Macs with one display name
//! never match each other's pairing.

use event_horizon_companion::sunshine::pairing_for;
use serde_json::json;

#[test]
fn picks_the_pairing_started_by_that_mac() {
    let pending = json!({ "pairings": [
        { "id": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "name": "mac-a", "address": "10.0.0.9" },
        { "id": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", "name": "mac-b", "address": "10.0.0.4" },
    ]});

    assert_eq!(
        pairing_for(&pending, "mac-b").as_deref(),
        Some("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")
    );
}

#[test]
fn two_macs_with_one_display_name_do_not_match_each_others_pairing() {
    let pending = json!({ "pairings": [
        { "id": "11111111111111111111111111111111", "name": "mac-1", "address": "10.0.0.4" },
        { "id": "22222222222222222222222222222222", "name": "mac-2", "address": "10.0.0.5" },
    ]});

    assert_eq!(
        pairing_for(&pending, "mac-1").as_deref(),
        Some("11111111111111111111111111111111")
    );
    assert_eq!(
        pairing_for(&pending, "mac-2").as_deref(),
        Some("22222222222222222222222222222222")
    );
}

#[test]
fn the_newest_wins_when_the_same_mac_asked_twice() {
    let pending = json!({ "pairings": [
        { "id": "11111111111111111111111111111111", "name": "mac-1", "address": "10.0.0.4" },
        { "id": "22222222222222222222222222222222", "name": "mac-1", "address": "10.0.0.4" },
    ]});

    assert_eq!(
        pairing_for(&pending, "mac-1").as_deref(),
        Some("22222222222222222222222222222222")
    );
}

#[test]
fn no_waiting_pairing_from_that_mac_is_none() {
    assert_eq!(pairing_for(&json!({ "pairings": [] }), "mac-1"), None);
    assert_eq!(pairing_for(&json!({}), "mac-1"), None);
}
