//! Host audio output device models and PulseAudio / PipeWire (`pactl`) parsing.
//!
//! Discovers available audio sinks on the host PC, brands the Sunshine / Event
//! Horizon virtual stream sink as "Event Horizon Audio", and filters noisy
//! monitor and dummy PipeWire entries.

use serde::{Deserialize, Serialize};

pub const VIRTUAL_SINK_ID: &str = "sink-sunshine-stereo";
pub const VIRTUAL_SINK_NAME: &str = "Event Horizon Audio";

/// An audio output sink available on the host PC.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct HostAudioDevice {
    pub id: String,
    pub name: String,
    pub is_virtual: bool,
    pub is_default: bool,
}

/// The list of discovered host audio output devices and the active default sink ID.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct AudioPayload {
    pub active_id: String,
    pub devices: Vec<HostAudioDevice>,
}

/// Request payload for selecting an audio output device on the host PC.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct SelectAudioRequest {
    pub id: String,
}

/// Returns an empty payload when audio discovery is unavailable on the current OS
/// or when `pactl` is missing.
pub fn empty_audio_payload() -> AudioPayload {
    AudioPayload {
        active_id: String::new(),
        devices: Vec::new(),
    }
}

/// Parses `pactl list sinks` and `pactl get-default-sink` output into an `AudioPayload`.
///
/// - Any sink whose name or description mentions `sunshine` or `event-horizon`
///   is branded as `"Event Horizon Audio"` with `is_virtual: true`.
/// - Monitor sources (`.monitor`, `Monitor of ...`) and dummy/null sinks
///   (`auto_null`, `Dummy Output`) are filtered out.
/// - Hardware sinks use their `Description` cleanly.
pub fn parse_pactl_sinks(sinks_output: &str, default_sink: &str) -> AudioPayload {
    let default_id = default_sink.trim();
    let mut virtual_devices = Vec::new();
    let mut hardware_devices = Vec::new();

    for block in split_sink_blocks(sinks_output) {
        let Some(device) = parse_sink_block(&block, default_id) else {
            continue;
        };
        if device.is_virtual {
            virtual_devices.push(device);
        } else {
            hardware_devices.push(device);
        }
    }

    let mut devices = virtual_devices;
    devices.extend(hardware_devices);

    let active_id = if !default_id.is_empty() && devices.iter().any(|d| d.id == default_id) {
        default_id.to_string()
    } else {
        devices
            .iter()
            .find(|d| d.is_default)
            .or_else(|| devices.first())
            .map(|d| d.id.clone())
            .unwrap_or_default()
    };

    AudioPayload { active_id, devices }
}

/// Parses `pactl list short sink-inputs` into a list of active sink-input IDs.
pub fn parse_sink_input_ids(short_output: &str) -> Vec<String> {
    short_output
        .lines()
        .filter_map(|line| {
            let id = line.split_whitespace().next()?;
            if !id.is_empty() && id.chars().all(|c| c.is_ascii_digit()) {
                Some(id.to_string())
            } else {
                None
            }
        })
        .collect()
}

fn split_sink_blocks(sinks_output: &str) -> Vec<Vec<&str>> {
    let mut blocks: Vec<Vec<&str>> = Vec::new();
    for line in sinks_output.lines() {
        let trimmed = line.trim_start();
        if trimmed.starts_with("Sink #") {
            blocks.push(vec![line]);
        } else if let Some(current) = blocks.last_mut() {
            current.push(line);
        }
    }
    blocks
}

fn parse_sink_block(lines: &[&str], default_id: &str) -> Option<HostAudioDevice> {
    let mut name: Option<String> = None;
    let mut description: Option<String> = None;
    let mut in_properties = false;

    for line in lines {
        let trimmed = line.trim();
        if trimmed == "Properties:" {
            in_properties = true;
            continue;
        }
        if in_properties {
            continue;
        }
        if let Some(rest) = trimmed.strip_prefix("Name:") {
            let val = rest.trim();
            if !val.is_empty() {
                name = Some(val.to_string());
            }
        } else if let Some(rest) = trimmed.strip_prefix("Description:") {
            let val = rest.trim();
            if !val.is_empty() {
                description = Some(val.to_string());
            }
        }
    }

    let id = name?;
    let raw_desc = description.unwrap_or_else(|| id.clone());
    let lower_id = id.to_ascii_lowercase();
    let lower_desc = raw_desc.to_ascii_lowercase();

    // Skip monitor sinks (loopback capture sources exposed as sinks).
    if lower_id.ends_with(".monitor")
        || lower_id.contains(".monitor.")
        || lower_desc.starts_with("monitor of ")
    {
        return None;
    }

    let is_virtual = lower_id.contains("sunshine")
        || lower_id.contains("event-horizon")
        || lower_id.contains("event_horizon")
        || lower_desc.contains("sunshine")
        || lower_desc.contains("event-horizon")
        || lower_desc.contains("event horizon");

    // Skip dummy/null/internal noise when it is not the Event Horizon / Sunshine virtual sink.
    if !is_virtual
        && (lower_id == "auto_null"
            || lower_id == "dummy"
            || lower_desc == "dummy output"
            || lower_desc.contains("dummy output")
            || lower_id.starts_with("speech-dispatcher"))
    {
        return None;
    }

    let display_name = if is_virtual {
        VIRTUAL_SINK_NAME.to_string()
    } else {
        raw_desc
    };

    Some(HostAudioDevice {
        is_default: id == default_id,
        id,
        name: display_name,
        is_virtual,
    })
}
