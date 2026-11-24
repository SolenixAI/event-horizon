//! Output device domain models and Linux KScreen discovery.
//!
//! Exposes physical and virtual display outputs connected to the host PC,
//! along with supported display modes, HDR capability, and current mode.

use crate::virtual_screen::OUTPUT as VIRTUAL_CONNECTOR;
use serde::{Deserialize, Serialize};
use serde_json::Value;

pub const VIRTUAL_ID: &str = "virtual";
pub const VIRTUAL_NAME: &str = "Virtual Screen (Mac Only)";

/// A display resolution and refresh rate supported by an output.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct DisplayMode {
    pub width: u32,
    pub height: u32,
    pub refresh: f64,
}

/// A physical or virtual display connected to the host.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct HostOutput {
    pub id: String,
    pub name: String,
    pub connector: String,
    pub connected: bool,
    pub enabled: bool,
    pub is_virtual: bool,
    pub hdr_supported: bool,
    pub current_mode: Option<DisplayMode>,
    pub modes: Vec<DisplayMode>,
}

/// The list of discovered host outputs and the currently active output ID.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct OutputsPayload {
    pub active_id: String,
    pub outputs: Vec<HostOutput>,
}

/// Request payload for selecting an output device.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct SelectOutputRequest {
    pub id: String,
    #[serde(default)]
    pub mode: Option<DisplayMode>,
}

/// Curated resolution and refresh presets for the virtual screen, merged with
/// its current mode and any discovered modes, sorted and deduplicated.
pub fn virtual_modes(
    current_mode: Option<&DisplayMode>,
    discovered: Vec<DisplayMode>,
) -> Vec<DisplayMode> {
    let mut modes = vec![
        DisplayMode {
            width: 2560,
            height: 1600,
            refresh: 120.0,
        },
        DisplayMode {
            width: 2560,
            height: 1600,
            refresh: 90.0,
        },
        DisplayMode {
            width: 2560,
            height: 1600,
            refresh: 60.0,
        },
        DisplayMode {
            width: 2560,
            height: 1440,
            refresh: 120.0,
        },
        DisplayMode {
            width: 2560,
            height: 1440,
            refresh: 90.0,
        },
        DisplayMode {
            width: 2560,
            height: 1440,
            refresh: 60.0,
        },
        DisplayMode {
            width: 1920,
            height: 1200,
            refresh: 120.0,
        },
        DisplayMode {
            width: 1920,
            height: 1200,
            refresh: 60.0,
        },
        DisplayMode {
            width: 1920,
            height: 1080,
            refresh: 120.0,
        },
        DisplayMode {
            width: 1920,
            height: 1080,
            refresh: 60.0,
        },
    ];
    modes.extend(discovered);
    if let Some(current) = current_mode {
        modes.push(current.clone());
    }
    sort_and_deduplicate_modes(modes)
}

/// Creates the default virtual screen output when missing from KScreen.
pub fn default_virtual_output() -> HostOutput {
    HostOutput {
        id: VIRTUAL_ID.to_string(),
        name: VIRTUAL_NAME.to_string(),
        connector: VIRTUAL_CONNECTOR.to_string(),
        connected: true,
        enabled: false,
        is_virtual: true,
        hdr_supported: false,
        current_mode: None,
        modes: virtual_modes(None, Vec::new()),
    }
}

/// Resolves the active output ID based on the contents of `stream-output` file.
/// If empty, missing, "virtual", or "Virtual-sunshine-vmon", defaults to "virtual".
/// If it matches an output's ID or connector, returns that output's ID.
pub fn resolve_active_id(active_connector: Option<&str>, outputs: &[HostOutput]) -> String {
    if let Some(target) = active_connector.map(str::trim).filter(|s| !s.is_empty()) {
        if target == VIRTUAL_ID || target == VIRTUAL_CONNECTOR {
            return VIRTUAL_ID.to_string();
        }
        if let Some(found) = outputs
            .iter()
            .find(|o| o.id == target || o.connector == target)
        {
            return found.id.clone();
        }
    }
    VIRTUAL_ID.to_string()
}

/// Parses a single display mode from a JSON mode object.
fn parse_mode(mode: &Value) -> Option<DisplayMode> {
    let width = mode
        .get("size")
        .and_then(|s| s.get("width"))
        .and_then(Value::as_u64)
        .or_else(|| mode.get("width").and_then(Value::as_u64))
        .or_else(|| {
            mode.get("size")
                .and_then(|s| s.get("width"))
                .and_then(Value::as_str)
                .and_then(|s| s.parse::<u64>().ok())
        })
        .or_else(|| {
            mode.get("width")
                .and_then(Value::as_str)
                .and_then(|s| s.parse::<u64>().ok())
        })
        .unwrap_or(0) as u32;

    let height = mode
        .get("size")
        .and_then(|s| s.get("height"))
        .and_then(Value::as_u64)
        .or_else(|| mode.get("height").and_then(Value::as_u64))
        .or_else(|| {
            mode.get("size")
                .and_then(|s| s.get("height"))
                .and_then(Value::as_str)
                .and_then(|s| s.parse::<u64>().ok())
        })
        .or_else(|| {
            mode.get("height")
                .and_then(Value::as_str)
                .and_then(|s| s.parse::<u64>().ok())
        })
        .unwrap_or(0) as u32;

    if width == 0 || height == 0 {
        return None;
    }

    let refresh = mode
        .get("refreshRate")
        .and_then(Value::as_f64)
        .or_else(|| mode.get("refresh_rate").and_then(Value::as_f64))
        .or_else(|| mode.get("refresh").and_then(Value::as_f64))
        .or_else(|| {
            mode.get("refreshRate")
                .and_then(Value::as_str)
                .and_then(|s| s.parse::<f64>().ok())
        })
        .or_else(|| {
            mode.get("refresh_rate")
                .and_then(Value::as_str)
                .and_then(|s| s.parse::<f64>().ok())
        })
        .or_else(|| {
            mode.get("refresh")
                .and_then(Value::as_str)
                .and_then(|s| s.parse::<f64>().ok())
        })
        .unwrap_or(60.0);

    Some(DisplayMode {
        width,
        height,
        refresh,
    })
}

/// Sorts modes by resolution descending (width * height, then width, then height),
/// then refresh rate descending, and removes duplicates with matching (width, height, refresh).
pub fn sort_and_deduplicate_modes(mut modes: Vec<DisplayMode>) -> Vec<DisplayMode> {
    modes.sort_by(|a, b| {
        let res_a = a.width as u64 * a.height as u64;
        let res_b = b.width as u64 * b.height as u64;
        res_b
            .cmp(&res_a)
            .then_with(|| b.width.cmp(&a.width))
            .then_with(|| b.height.cmp(&a.height))
            .then_with(|| {
                b.refresh
                    .partial_cmp(&a.refresh)
                    .unwrap_or(std::cmp::Ordering::Equal)
            })
    });

    let mut deduped = Vec::with_capacity(modes.len());
    for mode in modes {
        let exists = deduped.iter().any(|m: &DisplayMode| {
            m.width == mode.width
                && m.height == mode.height
                && (m.refresh - mode.refresh).abs() < 0.01
        });
        if !exists {
            deduped.push(mode);
        }
    }
    deduped
}

/// Extracts current display mode from the active mode or current size/refresh.
fn extract_current_mode(o: &Value, modes: &[DisplayMode]) -> Option<DisplayMode> {
    // 1. Check direct object in current_mode or currentMode
    if let Some(direct) = o
        .get("current_mode")
        .or_else(|| o.get("currentMode"))
        .filter(|d| d.is_object())
        && let Some(mode) = parse_mode(direct)
    {
        return Some(mode);
    }

    // 2. Check currentModeId in raw modes array
    let current_mode_id = o
        .get("currentModeId")
        .or_else(|| o.get("current_mode_id"))
        .or_else(|| o.get("mode_id"));
    if let Some(target) = current_mode_id
        .and_then(|id_val| {
            id_val
                .as_str()
                .map(str::to_string)
                .or_else(|| id_val.as_u64().map(|n| n.to_string()))
                .or_else(|| id_val.as_i64().map(|n| n.to_string()))
        })
        .filter(|t| !t.is_empty())
        && let Some(raw_modes) = o.get("modes").and_then(Value::as_array)
    {
        for m in raw_modes {
            let m_id = m
                .get("id")
                .and_then(Value::as_str)
                .map(str::to_string)
                .or_else(|| m.get("id").and_then(Value::as_u64).map(|n| n.to_string()))
                .or_else(|| m.get("id").and_then(Value::as_i64).map(|n| n.to_string()));
            if m_id.as_deref() == Some(&target) {
                let parsed = parse_mode(m);
                if parsed.is_some() {
                    return parsed;
                }
            }
        }
    }

    // 3. From current size / refresh
    let size = o.get("size");
    let width = size
        .and_then(|s| s.get("width"))
        .and_then(Value::as_u64)
        .or_else(|| o.get("width").and_then(Value::as_u64))
        .unwrap_or(0) as u32;
    let height = size
        .and_then(|s| s.get("height"))
        .and_then(Value::as_u64)
        .or_else(|| o.get("height").and_then(Value::as_u64))
        .unwrap_or(0) as u32;

    if width > 0 && height > 0 {
        let refresh_rate = o
            .get("refreshRate")
            .and_then(Value::as_f64)
            .or_else(|| o.get("refresh_rate").and_then(Value::as_f64))
            .or_else(|| o.get("refresh").and_then(Value::as_f64));

        if let Some(r) = refresh_rate {
            return Some(DisplayMode {
                width,
                height,
                refresh: r,
            });
        }

        // Try to match mode in parsed modes
        if let Some(matched) = modes
            .iter()
            .find(|m| m.width == width && m.height == height)
        {
            return Some(matched.clone());
        }

        return Some(DisplayMode {
            width,
            height,
            refresh: 60.0,
        });
    }

    None
}

/// Extracts EDID friendly name from vendor and model, falling back to connector name.
fn parse_friendly_name(o: &Value, connector: &str) -> String {
    let vendor = o
        .get("vendor")
        .and_then(Value::as_str)
        .or_else(|| {
            o.get("edid")
                .and_then(|e| e.get("vendor"))
                .and_then(Value::as_str)
        })
        .unwrap_or("")
        .trim();

    let model = o
        .get("model")
        .and_then(Value::as_str)
        .or_else(|| {
            o.get("edid")
                .and_then(|e| e.get("model"))
                .and_then(Value::as_str)
        })
        .or_else(|| {
            o.get("edid")
                .and_then(|e| e.get("name"))
                .and_then(Value::as_str)
        })
        .or_else(|| o.get("edidName").and_then(Value::as_str))
        .or_else(|| o.get("edid_name").and_then(Value::as_str))
        .unwrap_or("")
        .trim();

    let candidate = match (vendor.is_empty(), model.is_empty()) {
        (false, false) => format!("{vendor} {model}"),
        (false, true) => vendor.to_string(),
        (true, false) => model.to_string(),
        (true, true) => connector.to_string(),
    };

    let candidate = candidate.trim();
    if candidate.is_empty() {
        connector.to_string()
    } else {
        candidate.to_string()
    }
}

/// Extracts HDR capability (bool or object with supported bool).
fn parse_hdr(o: &Value) -> bool {
    o.get("hdr")
        .and_then(Value::as_bool)
        .or_else(|| {
            o.get("hdr")
                .and_then(|h| h.get("supported"))
                .and_then(Value::as_bool)
        })
        .or_else(|| o.get("hdrSupported").and_then(Value::as_bool))
        .or_else(|| o.get("hdr_supported").and_then(Value::as_bool))
        .unwrap_or(false)
}

/// Parses outputs from KScreen JSON `Value` and combines with active connector info.
pub fn parse_kscreen_json(
    value: &Value,
    active_connector: Option<&str>,
) -> Result<OutputsPayload, String> {
    let outputs_arr = match value.get("outputs") {
        Some(Value::Array(arr)) => arr.as_slice(),
        Some(Value::Null) | None => &[],
        _ => return Err("KScreen JSON 'outputs' is not an array".to_string()),
    };

    let mut outputs_with_priority: Vec<(Option<u32>, HostOutput)> = Vec::new();
    let mut virtual_found = false;

    for o in outputs_arr {
        let connector = match o.get("name").and_then(Value::as_str) {
            Some(n) if !n.is_empty() => n,
            _ => continue,
        };

        let priority = o.get("priority").and_then(Value::as_u64).map(|p| p as u32);
        let connected = o.get("connected").and_then(Value::as_bool).unwrap_or(true);
        let enabled = o.get("enabled").and_then(Value::as_bool).unwrap_or(false);

        let raw_modes: Vec<DisplayMode> = o
            .get("modes")
            .and_then(Value::as_array)
            .map(|arr| arr.iter().filter_map(parse_mode).collect())
            .unwrap_or_default();
        let sorted_raw = sort_and_deduplicate_modes(raw_modes);
        let current_mode = extract_current_mode(o, &sorted_raw);

        let is_virtual = connector == VIRTUAL_CONNECTOR || connector == VIRTUAL_ID;
        if is_virtual {
            virtual_found = true;
            let modes = virtual_modes(current_mode.as_ref(), sorted_raw);
            outputs_with_priority.push((
                priority,
                HostOutput {
                    id: VIRTUAL_ID.to_string(),
                    name: VIRTUAL_NAME.to_string(),
                    connector: VIRTUAL_CONNECTOR.to_string(),
                    connected,
                    enabled,
                    is_virtual: true,
                    hdr_supported: false,
                    current_mode,
                    modes,
                },
            ));
        } else {
            let modes = sorted_raw;
            let name = parse_friendly_name(o, connector);
            let hdr_supported = parse_hdr(o);
            outputs_with_priority.push((
                priority,
                HostOutput {
                    id: connector.to_string(),
                    name,
                    connector: connector.to_string(),
                    connected,
                    enabled,
                    is_virtual: false,
                    hdr_supported,
                    current_mode,
                    modes,
                },
            ));
        }
    }

    // Sort by priority if present, preserving relative order otherwise
    outputs_with_priority.sort_by_key(|(p, _)| p.unwrap_or(u32::MAX));
    let mut outputs: Vec<HostOutput> = outputs_with_priority.into_iter().map(|(_, o)| o).collect();

    // If virtual screen was not listed in KScreen outputs, include it
    if !virtual_found {
        outputs.push(default_virtual_output());
    }

    let active_id = resolve_active_id(active_connector, &outputs);

    Ok(OutputsPayload { active_id, outputs })
}

/// Parses outputs from KScreen JSON string.
pub fn parse_kscreen_outputs(
    json_str: &str,
    active_connector: Option<&str>,
) -> Result<OutputsPayload, String> {
    let value: Value =
        serde_json::from_str(json_str).map_err(|e| format!("Failed to parse KScreen JSON: {e}"))?;
    parse_kscreen_json(&value, active_connector)
}

/// Discovers connected displays using the `Commands` and `Files` ports.
pub fn discover_outputs(
    cmd: &dyn crate::linux_install::Commands,
    files: &dyn crate::linux_install::Files,
    layout: &crate::linux_install::Layout,
) -> Result<OutputsPayload, String> {
    let json_str = cmd.capture("kscreen-doctor", &["--json"])?;
    let active_connector = files.read(&layout.stream_output());
    parse_kscreen_outputs(&json_str, active_connector.as_deref())
}
