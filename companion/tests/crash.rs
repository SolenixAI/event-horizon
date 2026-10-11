//! Crash reports: a panic note becomes one exception that holds only the file
//! name, line and version, and it is due only to a Mac that shared usage stats
//! from before the panic.

use event_horizon_companion::crash;
use serde_json::json;

const NOTE: &str = r#"{"file":"link.rs","line":42,"version":"0.1.0","at":100}"#;

#[test]
fn a_note_becomes_one_exception_with_its_location() {
    let event = crash::exception_event(NOTE, "abc").unwrap();
    assert_eq!(event["event"], "$exception");
    assert_eq!(event["distinct_id"], "abc");
    let properties = &event["properties"];
    assert_eq!(properties["app"], "event-horizon-companion");
    assert_eq!(properties["$process_person_profile"], false);
    let exception = &properties["$exception_list"][0];
    assert_eq!(exception["value"], "panic at link.rs:42");
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
fn a_note_is_due_only_to_a_choice_made_before_the_panic() {
    let dir = tempfile::tempdir().unwrap();
    let macs = dir.path().join("macs.json");
    std::fs::write(dir.path().join("last-panic.json"), NOTE).unwrap();
    let record = |share: bool, since: u64| json!({ "macs": [{ "mac_id": "m", "share_usage_stats": share, "share_since": since }] });

    std::fs::write(&macs, record(true, 50).to_string()).unwrap();
    assert_eq!(crash::due_note(&macs).as_deref(), Some(NOTE));

    // Opted in after the panic: the panic happened without consent.
    std::fs::write(&macs, record(true, 150).to_string()).unwrap();
    assert!(crash::due_note(&macs).is_none());

    std::fs::write(&macs, record(false, 50).to_string()).unwrap();
    assert!(crash::due_note(&macs).is_none());
}

#[test]
fn a_note_nobody_may_send_is_dropped() {
    let dir = tempfile::tempdir().unwrap();
    let macs = dir.path().join("macs.json");
    let note = dir.path().join("last-panic.json");
    std::fs::write(&note, NOTE).unwrap();
    std::fs::write(
        &macs,
        json!({ "macs": [{ "mac_id": "m", "share_usage_stats": true }] }).to_string(),
    )
    .unwrap();
    crash::drop_unless_shared(&macs);
    assert!(note.exists());
    std::fs::write(
        &macs,
        json!({ "macs": [{ "mac_id": "m", "share_usage_stats": false }] }).to_string(),
    )
    .unwrap();
    crash::drop_unless_shared(&macs);
    assert!(!note.exists());
}
