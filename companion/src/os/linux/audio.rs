//! Linux PipeWire / PulseAudio (`pactl`) audio output discovery and switching.

use super::system::SystemCommands;
use crate::audio::{self, AudioPayload};
use crate::linux_install::Commands;

/// Discovers available audio output sinks using `pactl list sinks` and
/// `pactl get-default-sink`.
pub fn discover_audio() -> Result<AudioPayload, String> {
    let sinks = SystemCommands.capture("pactl", &["list", "sinks"])?;
    let default_sink = SystemCommands
        .capture("pactl", &["get-default-sink"])
        .unwrap_or_default();
    Ok(audio::parse_pactl_sinks(&sinks, &default_sink))
}

/// Switches the default PulseAudio/PipeWire sink to `sink_id` and moves all
/// currently active sink-inputs to it.
pub fn select_audio_sink(sink_id: &str) -> Result<(), String> {
    SystemCommands.run("pactl", &["set-default-sink", sink_id])?;
    if let Ok(short_inputs) = SystemCommands.capture("pactl", &["list", "short", "sink-inputs"]) {
        for input_id in audio::parse_sink_input_ids(&short_inputs) {
            let _ = SystemCommands.run("pactl", &["move-sink-input", &input_id, sink_id]);
        }
    }
    Ok(())
}
