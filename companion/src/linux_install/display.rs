//! Linux stream-display transaction and virtual-screen placement.

use super::{
    Commands, Files, Layout, PLACE_EVERY, PLACE_TRIES, SCREEN_SERVICE, VIRTUAL_TRIES, VIRTUAL_WAIT,
};
use crate::virtual_screen::{self, HDR_OUTPUT, OUTPUT};
use serde_json::Value;

/// Places the virtual screen right of the desk monitor once KScreen lists it.
/// The screen's unit runs this after krfb-virtualmonitor starts.
pub fn place_virtual_screen(cmd: &dyn Commands) -> Result<(), String> {
    for _ in 0..PLACE_TRIES {
        if let Some(args) = kscreen_placement(cmd) {
            let refs: Vec<&str> = args.iter().map(String::as_str).collect();
            return cmd.run("kscreen-doctor", &refs);
        }
        cmd.pause(PLACE_EVERY);
    }
    Err("the virtual screen did not appear within 10 seconds".into())
}

/// The one-screen mode. `on`, as a stream starts: the virtual screen becomes the
/// only screen, and the outputs it turned off are saved. Nothing changes while the
/// virtual screen is missing. `off`, as a stream ends or Sunshine starts: the saved
/// outputs come back, the first one primary, and the list is cleared.
pub fn stream_screen(
    cmd: &dyn Commands,
    files: &dyn Files,
    layout: &Layout,
    on: bool,
) -> Result<(), String> {
    let saved_path = layout.stream_screen_saved();
    if on {
        let recovery_required = files
            .read(&layout.stream_screen_recovery_required())
            .is_some_and(|state| !state.trim().is_empty());
        if recovery_required {
            recover_stream_screen(cmd, files, layout)?;
        }
        if let Some(saved) = files
            .read(&saved_path)
            .filter(|saved| !saved.trim().is_empty())
        {
            if saved_stream_state(&saved).is_some() {
                return Ok(());
            }
            recover_stream_screen(cmd, files, layout)?;
        }
        if files
            .read(&layout.stream_screen_target_state())
            .is_some_and(|state| !state.trim().is_empty())
        {
            recover_stream_screen(cmd, files, layout)?;
            if files
                .read(&layout.stream_screen_target_state())
                .is_some_and(|state| !state.trim().is_empty())
            {
                return Err(
                    "previous stream display settings are pending until the target reconnects"
                        .into(),
                );
            }
        }
        let target = configured_stream_output(files, layout);
        let snapshot = screen_for_stream(cmd, target)?;
        let recovery_state = serde_json::json!({
            "target": target,
            "restore": snapshot.restore.clone(),
            "target_settings": snapshot.target_settings.clone(),
        });
        let recovery_state = serde_json::to_string(&recovery_state).map_err(|e| e.to_string())?;
        files.write(&layout.stream_screen_target_state(), &recovery_state)?;
        let state = serde_json::json!({ "target": target, "restore": snapshot.restore.clone() });
        let state = serde_json::to_string(&state).map_err(|e| e.to_string())?;
        files.write(&saved_path, &state)?;
        let mut args = vec![
            format!("output.{target}.enable"),
            format!("output.{target}.priority.1"),
        ];
        if target == HDR_OUTPUT {
            args.push(format!("output.{target}.scale.1.75"));
        }
        args.extend(
            snapshot
                .restore
                .iter()
                .map(|o| format!("output.{o}.disable")),
        );
        let refs: Vec<&str> = args.iter().map(String::as_str).collect();
        if let Err(error) = cmd.run("kscreen-doctor", &refs) {
            if let Err(restore_error) = recover_stream_screen(cmd, files, layout) {
                return Err(format!(
                    "{error}; display restoration failed: {restore_error}"
                ));
            }
            return Err(error);
        }
        if target == HDR_OUTPUT
            && let Err(error) = cmd.run("kscreen-doctor", &["output.HDMI-A-1.hdr.enable"])
        {
            return match recover_stream_screen(cmd, files, layout) {
                Ok(()) => Err(error),
                Err(restore_error) => Err(format!(
                    "{error}; display restoration failed: {restore_error}"
                )),
            };
        }
        return Ok(());
    }
    recover_stream_screen(cmd, files, layout)
}

fn recover_stream_screen(
    cmd: &dyn Commands,
    files: &dyn Files,
    layout: &Layout,
) -> Result<(), String> {
    let recovery_path = layout.stream_screen_recovery_required();
    files.write(&recovery_path, "1")?;
    restore_stream_screen(cmd, files, layout)?;
    files.write(&recovery_path, "")
}

/// Restores the user's screens after a stream. Old newline-only state files remain
/// readable so a Sunshine restart during an upgrade cannot strand the display.
fn restore_stream_screen(
    cmd: &dyn Commands,
    files: &dyn Files,
    layout: &Layout,
) -> Result<(), String> {
    let saved_path = layout.stream_screen_saved();
    let saved = files.read(&saved_path).unwrap_or_default();
    let state_path = layout.stream_screen_target_state();
    let saved_target_state = files.read(&state_path).unwrap_or_default();
    let journal = recovery_stream_state(&saved_target_state);
    let legacy_target_settings = serde_json::from_str::<Value>(&saved_target_state)
        .ok()
        .filter(is_target_settings);
    let mut state = saved_stream_state(&saved);
    if let Some(saved_state) = state.as_mut() {
        if let Some(journal) = journal
            .as_ref()
            .filter(|journal| journal.target == saved_state.target)
        {
            saved_state.target_settings = journal.target_settings.clone();
        } else if let Some(settings) = legacy_target_settings.clone() {
            saved_state.target_settings = Some(settings);
        }
    } else if !saved.trim().is_empty() {
        // The display list may be damaged after a crash. The sidecar is written
        // first and contains the complete snapshot, so prefer it for recovery.
        state = journal;
        if state.is_none() {
            // Older sidecars stored only the selected output's settings. They
            // cannot recover other outputs, but can still restore this target.
            state = legacy_target_settings
                .clone()
                .map(|settings| SavedStreamState {
                    target: configured_stream_output(files, layout).to_string(),
                    restore: Vec::new(),
                    target_settings: Some(settings),
                });
        }
    } else if let Some(journal) = journal {
        // The main marker is cleared after the other screens return. Keep the
        // sidecar until a disconnected stream target can recover its settings.
        // Its restore list has already been applied, so do not replay it.
        state = Some(SavedStreamState {
            restore: Vec::new(),
            ..journal
        });
    } else if let Some(settings) = legacy_target_settings.clone() {
        state = Some(SavedStreamState {
            target: configured_stream_output(files, layout).to_string(),
            restore: Vec::new(),
            target_settings: Some(settings),
        });
    }

    let Some(SavedStreamState {
        target,
        restore,
        target_settings,
    }) = state
    else {
        if saved.trim().is_empty() && saved_target_state.trim().is_empty() {
            // No saved state: turn off the virtual screen if it's on and
            // other monitors exist, so the stream ends cleanly.
            let text = cmd.capture("kscreen-doctor", &["--json"])?;
            let json: Value = serde_json::from_str(&text).map_err(|e| e.to_string())?;
            if virtual_screen::virtual_on(&json) && !virtual_screen::others_on(&json).is_empty() {
                let disable = format!("output.{OUTPUT}.disable");
                cmd.run("kscreen-doctor", &[disable.as_str()])?;
            }
            return Ok(());
        }
        // No trustworthy snapshot remains. Leave the user's current layout as
        // it is, but clear the unusable marker so Sunshine recovery cannot be
        // blocked forever by corrupt state.
        eprintln!("stream-screen: saved display state is invalid; displays were left unchanged");
        files.write(&saved_path, "")?;
        return files.write(&state_path, "");
    };

    let text = cmd.capture("kscreen-doctor", &["--json"])?;
    let json: Value = serde_json::from_str(&text).map_err(|e| e.to_string())?;
    let outputs = json["outputs"]
        .as_array()
        .ok_or("KScreen returned no outputs")?;
    let connected = |name: &str| {
        outputs
            .iter()
            .any(|o| o["name"] == name && o["connected"] == true)
    };
    let enabled = |name: &str| {
        outputs
            .iter()
            .any(|o| o["name"] == name && o["enabled"] == true)
    };
    let restore: Vec<String> = restore.into_iter().filter(|name| connected(name)).collect();
    let screens_left = !restore.is_empty()
        || outputs
            .iter()
            .any(|o| o["name"] != target && o["enabled"] == true);
    let mut args: Vec<String> = restore
        .iter()
        .map(|o| format!("output.{o}.enable"))
        .collect();
    if let Some(first) = restore.first() {
        args.push(format!("output.{first}.priority.1"));
    }
    let target_connected = connected(&target);
    if target_connected {
        if let Some(was_enabled) = target_settings
            .as_ref()
            .and_then(|state| state.get("enabled"))
            .and_then(Value::as_bool)
        {
            // Keep the pre-stream layout, unless that would leave the host with
            // no active display after a disconnect during streaming.
            let should_be_enabled = was_enabled || !screens_left;
            if should_be_enabled && !enabled(&target) {
                args.push(format!("output.{target}.enable"));
            } else if !should_be_enabled && enabled(&target) {
                args.push(format!("output.{target}.disable"));
            }
        } else if target == OUTPUT && enabled(&target) && screens_left {
            // Legacy virtual-screen state did not capture whether the target
            // was enabled. An HDR marker cannot establish HDMI's prior state.
            args.push(format!("output.{target}.disable"));
        }
    }
    if !args.is_empty() {
        let refs: Vec<&str> = args.iter().map(String::as_str).collect();
        cmd.run("kscreen-doctor", &refs)?;
    }

    if let Some(target_settings) = target_settings.as_ref().filter(|_| target_connected) {
        let args = restore_target_settings(&target, target_settings);
        if !args.is_empty() {
            let refs: Vec<&str> = args.iter().map(String::as_str).collect();
            cmd.run("kscreen-doctor", &refs)?;
        }
    }

    let target_settings_pending =
        target_settings.as_ref().is_some_and(is_target_settings) && !target_connected;
    if target_settings_pending {
        // Record that the other screens are already restored before clearing
        // the active marker. Later retries only restore this disconnected target.
        let pending = serde_json::json!({
            "target": target,
            "restore": [],
            "target_settings": target_settings,
        });
        let pending = serde_json::to_string(&pending).map_err(|e| e.to_string())?;
        files.write(&state_path, &pending)?;
        files.write(&saved_path, "")?;
        Ok(())
    } else {
        files.write(&saved_path, "")?;
        files.write(&state_path, "")
    }
}

fn restore_target_settings(target: &str, settings: &Value) -> Vec<String> {
    let mut args = Vec::new();
    if let Some(scale) = settings.get("scale").and_then(Value::as_f64) {
        args.push(format!("output.{target}.scale.{scale}"));
    }
    if let Some(priority) = settings.get("priority").and_then(Value::as_i64) {
        args.push(format!("output.{target}.priority.{priority}"));
    }
    for key in ["hdr", "wcg"] {
        if let Some(enabled) = settings.get(key).and_then(Value::as_bool) {
            let mode = if enabled { "enable" } else { "disable" };
            args.push(format!("output.{target}.{key}.{mode}"));
        }
    }
    args
}

#[derive(Clone)]
struct SavedStreamState {
    target: String,
    restore: Vec<String>,
    target_settings: Option<Value>,
}

fn saved_stream_state(saved: &str) -> Option<SavedStreamState> {
    if saved.trim().is_empty() {
        return None;
    }
    if let Ok(value) = serde_json::from_str::<Value>(saved) {
        let target = value["target"].as_str()?;
        if ![OUTPUT, HDR_OUTPUT].contains(&target) {
            return None;
        }
        let restore = saved_output_names(&value["restore"], target)?;
        return Some(SavedStreamState {
            target: target.to_string(),
            restore,
            target_settings: None,
        });
    }
    if saved.trim_start().starts_with(['{', '[']) {
        return None;
    }
    // Before the JSON format, the file contained one previously enabled output
    // name per line, and streams always used the virtual screen.
    let restore = saved
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .map(|line| line.to_string())
        .collect::<Vec<_>>();
    if restore.is_empty()
        || restore
            .iter()
            .any(|name| !valid_output_name(name) || name == OUTPUT)
    {
        return None;
    }
    Some(SavedStreamState {
        target: OUTPUT.to_string(),
        restore,
        target_settings: None,
    })
}

pub(crate) fn stream_screen_marker_valid(saved: &str) -> bool {
    saved_stream_state(saved).is_some()
}

pub(crate) fn stream_screen_active(files: &dyn Files, layout: &Layout) -> bool {
    if files
        .read(&layout.stream_screen_recovery_required())
        .is_some_and(|state| !state.trim().is_empty())
    {
        return false;
    }
    let saved = files
        .read(&layout.stream_screen_saved())
        .unwrap_or_default();
    if saved.trim().is_empty() {
        return false;
    }
    if stream_screen_marker_valid(&saved) {
        return true;
    }
    let target_state = files
        .read(&layout.stream_screen_target_state())
        .unwrap_or_default();
    recovery_stream_state(&target_state).is_some()
        || serde_json::from_str::<Value>(&target_state)
            .ok()
            .is_some_and(|state| is_target_settings(&state))
}

#[cfg(target_os = "linux")]
pub(crate) fn virtual_screen_stream_active(files: &dyn Files, layout: &Layout) -> bool {
    stream_screen_active(files, layout) && stream_screen_target(files, layout) == Some(OUTPUT)
}

#[cfg(target_os = "linux")]
fn stream_screen_target(files: &dyn Files, layout: &Layout) -> Option<&'static str> {
    let saved = files
        .read(&layout.stream_screen_saved())
        .unwrap_or_default();
    let state = saved_stream_state(&saved).or_else(|| {
        let recovery = files.read(&layout.stream_screen_target_state())?;
        recovery_stream_state(&recovery)
    })?;
    match state.target.as_str() {
        OUTPUT => Some(OUTPUT),
        HDR_OUTPUT => Some(HDR_OUTPUT),
        _ => None,
    }
}

fn recovery_stream_state(saved: &str) -> Option<SavedStreamState> {
    let value = serde_json::from_str::<Value>(saved).ok()?;
    let target = value["target"].as_str()?;
    if ![OUTPUT, HDR_OUTPUT].contains(&target) {
        return None;
    }
    let restore = saved_output_names(&value["restore"], target)?;
    let target_settings = value.get("target_settings")?.clone();
    if !target_settings.is_object() {
        return None;
    }
    Some(SavedStreamState {
        target: target.to_string(),
        restore,
        target_settings: Some(target_settings),
    })
}

fn saved_output_names(value: &Value, target: &str) -> Option<Vec<String>> {
    let restore = value
        .as_array()?
        .iter()
        .map(Value::as_str)
        .collect::<Option<Vec<_>>>()?;
    if restore
        .iter()
        .any(|name| !valid_output_name(name) || *name == target)
    {
        return None;
    }
    Some(restore.into_iter().map(str::to_string).collect())
}

fn valid_output_name(name: &str) -> bool {
    !name.is_empty()
        && name
            .chars()
            .all(|character| character.is_ascii_alphanumeric() || "-_.".contains(character))
}

fn is_target_settings(value: &Value) -> bool {
    value.as_object().is_some_and(|settings| {
        settings
            .keys()
            .any(|key| ["enabled", "scale", "priority", "hdr", "wcg"].contains(&key.as_str()))
    })
}

pub(super) fn configured_stream_output(files: &dyn Files, layout: &Layout) -> &'static str {
    if files
        .read(&layout.stream_output())
        .is_some_and(|output| output.trim() == HDR_OUTPUT)
    {
        HDR_OUTPUT
    } else {
        OUTPUT
    }
}

/// Confirms the stream target is connected before changing screens.
/// The virtual screen is started when missing; failure leaves outputs untouched.
struct StreamScreenSnapshot {
    restore: Vec<String>,
    target_settings: Value,
}

fn screen_for_stream(cmd: &dyn Commands, target: &str) -> Result<StreamScreenSnapshot, String> {
    let mut started = false;
    for _ in 0..VIRTUAL_TRIES {
        let text = cmd.capture("kscreen-doctor", &["--json"])?;
        let json: Value = serde_json::from_str(&text).map_err(|e| e.to_string())?;
        if let Some(outputs) = json["outputs"].as_array()
            && outputs
                .iter()
                .any(|o| o["name"] == target && o["connected"] == true)
        {
            let target_output = outputs
                .iter()
                .find(|o| o["name"] == target && o["connected"] == true)
                .ok_or_else(|| format!("configured stream output {target} disappeared"))?;
            let mut target_settings = serde_json::Map::new();
            for key in ["enabled", "scale", "priority", "hdr", "wcg"] {
                if let Some(value) = target_output.get(key) {
                    target_settings.insert(key.to_string(), value.clone());
                }
            }
            return Ok(StreamScreenSnapshot {
                restore: outputs
                    .iter()
                    .filter(|o| o["name"] != target && o["enabled"] == true)
                    .filter_map(|o| o["name"].as_str().map(str::to_string))
                    .collect(),
                target_settings: Value::Object(target_settings),
            });
        }
        if target != OUTPUT {
            return Err(format!(
                "configured stream output {target} is not connected; no monitor was turned off"
            ));
        }
        if !started {
            cmd.run("systemctl", &["--user", "start", SCREEN_SERVICE])?;
            started = true;
        }
        cmd.pause(VIRTUAL_WAIT);
    }
    Err(format!(
        "the virtual screen did not appear after {SCREEN_SERVICE} started; no monitor was turned off"
    ))
}

fn kscreen_placement(cmd: &dyn Commands) -> Option<Vec<String>> {
    let text = cmd.capture("kscreen-doctor", &["--json"]).ok()?;
    let json: Value = serde_json::from_str(&text).ok()?;
    virtual_screen::placement_args(&json)
}
