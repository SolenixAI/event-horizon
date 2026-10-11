//! Crash reports. A panic leaves a note beside `macs.json`; the next start sends
//! it to PostHog as one exception, but only when a paired Mac has turned on
//! usage stats. The note holds the code location and version, nothing else.

use serde_json::{Value, json};
use std::path::{Path, PathBuf};

const NOTE: &str = "last-panic.json";
/// The project's public ingestion key: it can only write events.
const POSTHOG_KEY: &str = "phc_yiiguNiBP8LGF8vrcWnDVMs3CkaEBLPk3gwGNrpqLs5G";
const CAPTURE_URL: &str = "https://us.i.posthog.com/i/v0/e/";

/// Leave a note on panic, then let the default hook print as before.
pub fn install_panic_hook(dir: PathBuf) {
    let default = std::panic::take_hook();
    std::panic::set_hook(Box::new(move |info| {
        if let Some(location) = info.location() {
            let note = json!({
                "file": location.file(),
                "line": location.line(),
                "version": env!("CARGO_PKG_VERSION"),
            });
            let _ = std::fs::create_dir_all(&dir);
            let _ = std::fs::write(dir.join(NOTE), note.to_string());
        }
        default(info);
    }));
}

/// The exception event for a panic note. Each report gets a fresh random ID,
/// so reports from one PC can't be linked to each other.
pub fn exception_event(note: &str, report_id: &str) -> Option<Value> {
    let note: Value = serde_json::from_str(note).ok()?;
    let file = note["file"].as_str()?;
    let line = note["line"].as_u64()?;
    let mut properties = json!({
        "app": "event-horizon-companion",
        "app_version": note["version"],
        "os": std::env::consts::OS,
        "$process_person_profile": false,
        "$exception_level": "fatal",
        "$exception_list": [{
            "type": "panic",
            "value": format!("panic at {file}:{line}"),
            "mechanism": { "handled": false, "synthetic": false, "type": "rust-panic" },
            "stacktrace": { "type": "raw", "frames": [{
                "platform": "custom", "lang": "rust", "resolved": true, "in_app": true,
                "function": "panic", "filename": file, "lineno": line,
            }] },
        }],
    });
    if cfg!(debug_assertions) {
        properties["internal"] = json!(true);
    }
    Some(json!({
        "api_key": POSTHOG_KEY,
        "event": "$exception",
        "distinct_id": report_id,
        "properties": properties,
    }))
}

/// The note waiting from the last panic, removed as it is read, and whether
/// a paired Mac lets it be sent. A note nobody may send is dropped, not kept.
pub fn take_pending(dir: &Path, macs: &Path) -> Option<String> {
    let path = dir.join(NOTE);
    let note = std::fs::read_to_string(&path).ok()?;
    let _ = std::fs::remove_file(&path);
    crate::link::any_mac_shares_stats(macs).then_some(note)
}

/// At start: send the last panic's note, if a paired Mac shares usage stats.
pub async fn send_pending(dir: PathBuf, macs: PathBuf) {
    let Some(note) = take_pending(&dir, &macs) else {
        return;
    };
    let mut id = [0u8; 16];
    if getrandom::fill(&mut id).is_err() {
        return;
    }
    let report_id: String = id.iter().map(|b| format!("{b:02x}")).collect();
    let Some(event) = exception_event(&note, &report_id) else {
        return;
    };
    let _ = reqwest::Client::new()
        .post(CAPTURE_URL)
        .json(&event)
        .send()
        .await;
}
