//! Crash reports. A panic leaves a note beside `macs.json` with the file name,
//! line, version and time. It is sent to PostHog only when a Mac's lease says it
//! shares usage stats and chose to before the panic; otherwise it is dropped.

use serde_json::{Value, json};
use std::path::{Path, PathBuf};

const NOTE: &str = "last-panic.json";
/// The project's public ingestion key: it can only write events.
const POSTHOG_KEY: &str = "phc_yiiguNiBP8LGF8vrcWnDVMs3CkaEBLPk3gwGNrpqLs5G";
const CAPTURE_URL: &str = "https://us.i.posthog.com/i/v0/e/";

/// Now, in Unix seconds.
pub fn now() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0, |elapsed| elapsed.as_secs())
}

/// Leave a note on panic, then let the default hook print as before. Only the
/// file's name is kept: a dependency's path holds the build machine's folders.
pub fn install_panic_hook(dir: PathBuf) {
    let default = std::panic::take_hook();
    std::panic::set_hook(Box::new(move |info| {
        if let Some(location) = info.location() {
            let file = Path::new(location.file())
                .file_name()
                .map_or_else(String::new, |name| name.to_string_lossy().into_owned());
            let note = json!({
                "file": file,
                "line": location.line(),
                "version": env!("CARGO_PKG_VERSION"),
                "at": now(),
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

fn note_path(macs: &Path) -> PathBuf {
    macs.parent().unwrap_or(Path::new(".")).join(NOTE)
}

/// The waiting note, if a paired Mac shared usage stats from before its panic.
pub fn due_note(macs: &Path) -> Option<String> {
    let note = std::fs::read_to_string(note_path(macs)).ok()?;
    let at = serde_json::from_str::<Value>(&note).ok()?["at"].as_u64()?;
    crate::link::shared_before(macs, at).then_some(note)
}

/// A Mac said it doesn't share: if no paired Mac does, the note goes unsent.
pub fn drop_unless_shared(macs: &Path) {
    if !crate::link::any_mac_shares_stats(macs) {
        let _ = std::fs::remove_file(note_path(macs));
    }
}

/// Send the waiting note if it is due. It is removed only once PostHog has it,
/// so a send that fails is tried again at the next lease.
pub async fn send_due(macs: PathBuf) {
    let Some(note) = due_note(&macs) else {
        return;
    };
    let mut id = [0u8; 16];
    if getrandom::fill(&mut id).is_err() {
        return;
    }
    let report_id: String = id.iter().map(|b| format!("{b:02x}")).collect();
    let Some(event) = exception_event(&note, &report_id) else {
        let _ = std::fs::remove_file(note_path(&macs));
        return;
    };
    match reqwest::Client::new()
        .post(CAPTURE_URL)
        .json(&event)
        .send()
        .await
    {
        Ok(reply) if reply.status().is_success() => {
            let _ = std::fs::remove_file(note_path(&macs));
        }
        Ok(reply) => eprintln!("crash report: PostHog answered {}", reply.status()),
        Err(e) => eprintln!("crash report: {e}"),
    }
}
