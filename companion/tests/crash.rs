//! Crash reports: a panic note becomes one exception that holds only the code
//! location and version, and it leaves the PC only when a paired Mac opted in.

use event_horizon_companion::crash;
use serde_json::json;

const NOTE: &str = r#"{"file":"src/link.rs","line":42,"version":"0.1.0"}"#;

#[test]
fn a_note_becomes_one_exception_with_its_location() {
    let event = crash::exception_event(NOTE, "abc").unwrap();
    assert_eq!(event["event"], "$exception");
    assert_eq!(event["distinct_id"], "abc");
    let properties = &event["properties"];
    assert_eq!(properties["app"], "event-horizon-companion");
    assert_eq!(properties["$process_person_profile"], false);
    let exception = &properties["$exception_list"][0];
    assert_eq!(exception["value"], "panic at src/link.rs:42");
    assert_eq!(exception["stacktrace"]["frames"][0]["lineno"], 42);
    // Tests build with debug assertions, which the project's filter drops.
    assert_eq!(properties["internal"], true);
}

#[test]
fn an_unreadable_note_sends_nothing() {
    assert!(crash::exception_event("not json", "abc").is_none());
    assert!(crash::exception_event(r#"{"line":1}"#, "abc").is_none());
}

#[test]
fn a_note_leaves_only_when_a_mac_shares_stats_and_is_removed_either_way() {
    let dir = tempfile::tempdir().unwrap();
    let macs = dir.path().join("macs.json");
    let note = dir.path().join("last-panic.json");
    let record = |share: bool| json!({ "macs": [{ "mac_id": "m", "share_usage_stats": share }] });

    std::fs::write(&macs, record(false).to_string()).unwrap();
    std::fs::write(&note, NOTE).unwrap();
    assert!(crash::take_pending(dir.path(), &macs).is_none());
    assert!(!note.exists());

    std::fs::write(&macs, record(true).to_string()).unwrap();
    std::fs::write(&note, NOTE).unwrap();
    assert_eq!(
        crash::take_pending(dir.path(), &macs).as_deref(),
        Some(NOTE)
    );
    assert!(!note.exists());
}
