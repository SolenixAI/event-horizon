//! Tests for host output models, KScreen JSON parsing, mode sorting,
//! deduplication, EDID fallbacks, and Serde serialization.

use event_horizon_companion::linux_install::{Commands, Files, Layout};
use event_horizon_companion::outputs::{
    self, DisplayMode, HostOutput, OutputsPayload, SelectOutputRequest, VIRTUAL_ID, VIRTUAL_NAME,
    discover_outputs, parse_kscreen_outputs, sort_and_deduplicate_modes, virtual_modes,
};
use serde_json::json;
use std::collections::{HashMap, VecDeque};
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use std::time::Duration;

const VIRTUAL_CONNECTOR: &str = "Virtual-sunshine-vmon";

/// In-memory commands runner for testing `discover_outputs`.
#[derive(Default)]
struct FakeCommands {
    capture_answers: Mutex<VecDeque<String>>,
}

impl Commands for FakeCommands {
    fn run(&self, _program: &str, _args: &[&str]) -> Result<(), String> {
        Ok(())
    }

    fn capture(&self, _program: &str, _args: &[&str]) -> Result<String, String> {
        let mut answers = self.capture_answers.lock().unwrap();
        if let Some(ans) = answers.pop_front() {
            Ok(ans)
        } else {
            Err("no more captured answers".to_string())
        }
    }

    fn pause(&self, _how_long: Duration) {}
}

/// In-memory filesystem for testing `discover_outputs`.
#[derive(Default)]
struct FakeFiles {
    store: Mutex<HashMap<PathBuf, String>>,
}

impl Files for FakeFiles {
    fn read(&self, path: &Path) -> Option<String> {
        self.store.lock().unwrap().get(path).cloned()
    }

    fn write(&self, path: &Path, text: &str) -> Result<(), String> {
        self.store
            .lock()
            .unwrap()
            .insert(path.to_path_buf(), text.to_string());
        Ok(())
    }

    fn exists(&self, path: &Path) -> bool {
        self.store.lock().unwrap().contains_key(path)
    }

    fn restrict(&self, _path: &Path) {}

    fn copy(&self, from: &Path, to: &Path) -> Result<(), String> {
        let content = self.read(from).ok_or("file not found")?;
        self.write(to, &content)
    }
}

// ---------------------------------------------------------------------------
// 1. Single Monitor Parsing
// ---------------------------------------------------------------------------

#[test]
fn single_monitor_parsed_correctly() {
    let kscreen_json = json!({
        "outputs": [
            {
                "name": "DP-1",
                "connected": true,
                "enabled": true,
                "priority": 1,
                "vendor": "Dell Inc.",
                "model": "DELL U2720Q",
                "size": { "width": 3840, "height": 2160 },
                "currentModeId": "mode-1",
                "hdr": false,
                "modes": [
                    { "id": "mode-1", "size": { "width": 3840, "height": 2160 }, "refreshRate": 60.0 },
                    { "id": "mode-2", "size": { "width": 2560, "height": 1440 }, "refreshRate": 59.95 },
                    { "id": "mode-3", "size": { "width": 1920, "height": 1080 }, "refreshRate": 60.0 }
                ]
            }
        ]
    })
    .to_string();

    let payload = parse_kscreen_outputs(&kscreen_json, None).expect("parse succeeds");

    // Default active output is virtual
    assert_eq!(payload.active_id, "virtual");
    assert_eq!(payload.outputs.len(), 2);

    // Physical monitor
    let dp = &payload.outputs[0];
    assert_eq!(dp.id, "DP-1");
    assert_eq!(dp.connector, "DP-1");
    assert_eq!(dp.name, "Dell Inc. DELL U2720Q");
    assert!(dp.connected);
    assert!(dp.enabled);
    assert!(!dp.is_virtual);
    assert!(!dp.hdr_supported);
    assert_eq!(
        dp.current_mode,
        Some(DisplayMode {
            width: 3840,
            height: 2160,
            refresh: 60.0,
        })
    );
    assert_eq!(dp.modes.len(), 3);
    assert_eq!(dp.modes[0].width, 3840);
    assert_eq!(dp.modes[1].width, 2560);
    assert_eq!(dp.modes[2].width, 1920);

    // Virtual output automatically included
    let v = &payload.outputs[1];
    assert_eq!(v.id, VIRTUAL_ID);
    assert_eq!(v.name, VIRTUAL_NAME);
    assert_eq!(v.connector, VIRTUAL_CONNECTOR);
    assert!(v.connected);
    assert!(!v.enabled);
    assert!(v.is_virtual);
    assert!(!v.hdr_supported);
    assert_eq!(v.current_mode, None);
    assert_eq!(v.modes.len(), 10);
}

// ---------------------------------------------------------------------------
// 2. Dual Monitor with TV + Desk Monitor
// ---------------------------------------------------------------------------

#[test]
fn dual_monitor_with_tv_and_monitor() {
    let kscreen_json = json!({
        "outputs": [
            {
                "name": "DP-1",
                "connected": true,
                "enabled": true,
                "priority": 1,
                "vendor": "ASUSTek",
                "model": "VG279",
                "size": { "width": 1920, "height": 1080 },
                "currentModeId": "m-1",
                "hdr": { "supported": false },
                "modes": [
                    { "id": "m-1", "size": { "width": 1920, "height": 1080 }, "refreshRate": 144.0 },
                    { "id": "m-2", "size": { "width": 1920, "height": 1080 }, "refreshRate": 60.0 }
                ]
            },
            {
                "name": "HDMI-A-1",
                "connected": true,
                "enabled": false,
                "priority": 2,
                "vendor": "LG Electronics",
                "model": "LG TV OLED C2",
                "size": { "width": 3840, "height": 2160 },
                "hdr": { "supported": true, "enabled": false },
                "modes": [
                    { "id": "tv-1", "size": { "width": 3840, "height": 2160 }, "refreshRate": 120.0 },
                    { "id": "tv-2", "size": { "width": 3840, "height": 2160 }, "refreshRate": 60.0 }
                ]
            }
        ]
    })
    .to_string();

    // With active connector set to HDMI-A-1 in stream-output
    let payload = parse_kscreen_outputs(&kscreen_json, Some("HDMI-A-1")).expect("parse succeeds");

    assert_eq!(payload.active_id, "HDMI-A-1");
    assert_eq!(payload.outputs.len(), 3);

    // DP-1
    let dp = &payload.outputs[0];
    assert_eq!(dp.id, "DP-1");
    assert_eq!(dp.name, "ASUSTek VG279");
    assert!(dp.connected);
    assert!(dp.enabled);
    assert!(!dp.hdr_supported);

    // HDMI-A-1 (TV with HDR)
    let tv = &payload.outputs[1];
    assert_eq!(tv.id, "HDMI-A-1");
    assert_eq!(tv.connector, "HDMI-A-1");
    assert_eq!(tv.name, "LG Electronics LG TV OLED C2");
    assert!(tv.connected);
    assert!(!tv.enabled);
    assert!(!tv.is_virtual);
    assert!(tv.hdr_supported);
    assert_eq!(tv.modes.len(), 2);
    assert_eq!(tv.modes[0].refresh, 120.0);
    assert_eq!(tv.modes[1].refresh, 60.0);

    // Virtual output
    let v = &payload.outputs[2];
    assert_eq!(v.id, "virtual");
    assert!(v.is_virtual);
}

// ---------------------------------------------------------------------------
// 3. Headless Setup
// ---------------------------------------------------------------------------

#[test]
fn headless_setup_returns_virtual_screen() {
    let kscreen_json = json!({
        "outputs": []
    })
    .to_string();

    let payload = parse_kscreen_outputs(&kscreen_json, None).expect("parse succeeds");

    assert_eq!(payload.active_id, "virtual");
    assert_eq!(payload.outputs.len(), 1);

    let v = &payload.outputs[0];
    assert_eq!(v.id, "virtual");
    assert_eq!(v.name, "Virtual Screen (Mac Only)");
    assert_eq!(v.connector, "Virtual-sunshine-vmon");
    assert!(v.connected);
    assert!(!v.enabled);
    assert!(v.is_virtual);
    assert!(!v.hdr_supported);
    assert_eq!(v.current_mode, None);
    assert_eq!(v.modes.len(), 10);
}

#[test]
fn empty_json_object_returns_virtual_screen() {
    let kscreen_json = json!({}).to_string();
    let payload = parse_kscreen_outputs(&kscreen_json, None).expect("parse succeeds");
    assert_eq!(payload.outputs.len(), 1);
    assert_eq!(payload.outputs[0].id, "virtual");
}

// ---------------------------------------------------------------------------
// 4. Mode Sorting and Deduplication
// ---------------------------------------------------------------------------

#[test]
fn mode_sorting_and_deduplication() {
    let modes = vec![
        DisplayMode {
            width: 1920,
            height: 1080,
            refresh: 60.0,
        },
        DisplayMode {
            width: 1920,
            height: 1080,
            refresh: 59.94,
        },
        // Duplicate 1920x1080 @ 60.0
        DisplayMode {
            width: 1920,
            height: 1080,
            refresh: 60.0,
        },
        DisplayMode {
            width: 3840,
            height: 2160,
            refresh: 60.0,
        },
        DisplayMode {
            width: 3840,
            height: 2160,
            refresh: 120.0,
        },
        DisplayMode {
            width: 2560,
            height: 1440,
            refresh: 144.0,
        },
        // Duplicate 3840x2160 @ 120.0
        DisplayMode {
            width: 3840,
            height: 2160,
            refresh: 120.0,
        },
    ];

    let sorted = sort_and_deduplicate_modes(modes);

    assert_eq!(sorted.len(), 5);

    // 1. 3840x2160 @ 120.0
    assert_eq!(sorted[0].width, 3840);
    assert_eq!(sorted[0].height, 2160);
    assert_eq!(sorted[0].refresh, 120.0);

    // 2. 3840x2160 @ 60.0
    assert_eq!(sorted[1].width, 3840);
    assert_eq!(sorted[1].height, 2160);
    assert_eq!(sorted[1].refresh, 60.0);

    // 3. 2560x1440 @ 144.0
    assert_eq!(sorted[2].width, 2560);
    assert_eq!(sorted[2].height, 1440);
    assert_eq!(sorted[2].refresh, 144.0);

    // 4. 1920x1080 @ 60.0
    assert_eq!(sorted[3].width, 1920);
    assert_eq!(sorted[3].height, 1080);
    assert_eq!(sorted[3].refresh, 60.0);

    // 5. 1920x1080 @ 59.94
    assert_eq!(sorted[4].width, 1920);
    assert_eq!(sorted[4].height, 1080);
    assert_eq!(sorted[4].refresh, 59.94);
}

// ---------------------------------------------------------------------------
// 5. Fallback When EDID is Absent or Partial
// ---------------------------------------------------------------------------

#[test]
fn fallback_when_edid_is_absent() {
    let kscreen_json = json!({
        "outputs": [
            {
                "name": "HDMI-A-1",
                "connected": true,
                "enabled": true
            },
            {
                "name": "DP-1",
                "vendor": "Samsung",
                "connected": true,
                "enabled": true
            },
            {
                "name": "DP-2",
                "model": "Generic 4K",
                "connected": true,
                "enabled": true
            }
        ]
    })
    .to_string();

    let payload = parse_kscreen_outputs(&kscreen_json, None).expect("parse succeeds");

    // HDMI-A-1 has no vendor or model: falls back to connector name
    let hdmi = payload
        .outputs
        .iter()
        .find(|o| o.connector == "HDMI-A-1")
        .unwrap();
    assert_eq!(hdmi.name, "HDMI-A-1");

    // DP-1 has vendor only: uses vendor
    let dp1 = payload
        .outputs
        .iter()
        .find(|o| o.connector == "DP-1")
        .unwrap();
    assert_eq!(dp1.name, "Samsung");

    // DP-2 has model only: uses model
    let dp2 = payload
        .outputs
        .iter()
        .find(|o| o.connector == "DP-2")
        .unwrap();
    assert_eq!(dp2.name, "Generic 4K");
}

// ---------------------------------------------------------------------------
// 6. Virtual Output Already Present in KScreen
// ---------------------------------------------------------------------------

#[test]
fn virtual_output_in_kscreen_is_mapped_and_not_duplicated() {
    let kscreen_json = json!({
        "outputs": [
            {
                "name": "DP-1",
                "connected": true,
                "enabled": true,
                "size": { "width": 1920, "height": 1080 }
            },
            {
                "name": "Virtual-sunshine-vmon",
                "connected": true,
                "enabled": true,
                "size": { "width": 2560, "height": 1600 },
                "modes": [
                    { "size": { "width": 2560, "height": 1600 }, "refreshRate": 60.0 }
                ]
            }
        ]
    })
    .to_string();

    let payload = parse_kscreen_outputs(&kscreen_json, None).expect("parse succeeds");

    assert_eq!(payload.outputs.len(), 2);

    let v = payload
        .outputs
        .iter()
        .find(|o| o.id == "virtual")
        .expect("virtual exists");
    assert_eq!(v.name, "Virtual Screen (Mac Only)");
    assert_eq!(v.connector, "Virtual-sunshine-vmon");
    assert!(v.is_virtual);
    assert!(v.connected);
    assert!(v.enabled);
    assert_eq!(
        v.current_mode,
        Some(DisplayMode {
            width: 2560,
            height: 1600,
            refresh: 60.0,
        })
    );
    assert_eq!(v.modes.len(), 10);
}

// ---------------------------------------------------------------------------
// 7. Active ID Resolution
// ---------------------------------------------------------------------------

#[test]
fn active_id_resolution_rules() {
    let outputs = vec![
        HostOutput {
            id: "DP-1".to_string(),
            name: "Desk Monitor".to_string(),
            connector: "DP-1".to_string(),
            connected: true,
            enabled: true,
            is_virtual: false,
            hdr_supported: false,
            current_mode: None,
            modes: vec![],
        },
        HostOutput {
            id: "HDMI-A-1".to_string(),
            name: "LG TV".to_string(),
            connector: "HDMI-A-1".to_string(),
            connected: true,
            enabled: false,
            is_virtual: false,
            hdr_supported: true,
            current_mode: None,
            modes: vec![],
        },
        HostOutput {
            id: "virtual".to_string(),
            name: "Virtual Screen (Mac Only)".to_string(),
            connector: "Virtual-sunshine-vmon".to_string(),
            connected: true,
            enabled: false,
            is_virtual: true,
            hdr_supported: false,
            current_mode: None,
            modes: vec![],
        },
    ];

    // None or empty defaults to virtual
    assert_eq!(outputs::resolve_active_id(None, &outputs), "virtual");
    assert_eq!(outputs::resolve_active_id(Some(""), &outputs), "virtual");
    assert_eq!(
        outputs::resolve_active_id(Some("   \n"), &outputs),
        "virtual"
    );

    // "virtual" or "Virtual-sunshine-vmon" resolves to "virtual"
    assert_eq!(
        outputs::resolve_active_id(Some("virtual"), &outputs),
        "virtual"
    );
    assert_eq!(
        outputs::resolve_active_id(Some("Virtual-sunshine-vmon"), &outputs),
        "virtual"
    );

    // Matching physical connector
    assert_eq!(
        outputs::resolve_active_id(Some("HDMI-A-1"), &outputs),
        "HDMI-A-1"
    );
    assert_eq!(
        outputs::resolve_active_id(Some("HDMI-A-1\n"), &outputs),
        "HDMI-A-1"
    );
    assert_eq!(outputs::resolve_active_id(Some("DP-1"), &outputs), "DP-1");

    // Non-existent connector falls back to virtual
    assert_eq!(
        outputs::resolve_active_id(Some("nonexistent"), &outputs),
        "virtual"
    );
}

// ---------------------------------------------------------------------------
// 8. Serde JSON Serialization Matches Spec
// ---------------------------------------------------------------------------

#[test]
fn serde_json_serialization_matches_spec() {
    let payload = OutputsPayload {
        active_id: "HDMI-A-1".to_string(),
        outputs: vec![
            HostOutput {
                id: "HDMI-A-1".to_string(),
                name: "LG OLED TV".to_string(),
                connector: "HDMI-A-1".to_string(),
                connected: true,
                enabled: true,
                is_virtual: false,
                hdr_supported: true,
                current_mode: Some(DisplayMode {
                    width: 3840,
                    height: 2160,
                    refresh: 120.0,
                }),
                modes: vec![
                    DisplayMode {
                        width: 3840,
                        height: 2160,
                        refresh: 120.0,
                    },
                    DisplayMode {
                        width: 1920,
                        height: 1080,
                        refresh: 60.0,
                    },
                ],
            },
            HostOutput {
                id: "virtual".to_string(),
                name: "Virtual Screen (Mac Only)".to_string(),
                connector: "Virtual-sunshine-vmon".to_string(),
                connected: true,
                enabled: false,
                is_virtual: true,
                hdr_supported: false,
                current_mode: None,
                modes: vec![],
            },
        ],
    };

    let serialized = serde_json::to_string_pretty(&payload).expect("serialization succeeds");

    // Verify snake_case field names in JSON string
    assert!(serialized.contains("\"active_id\": \"HDMI-A-1\""));
    assert!(serialized.contains("\"is_virtual\": false"));
    assert!(serialized.contains("\"hdr_supported\": true"));
    assert!(serialized.contains("\"current_mode\": {"));
    assert!(serialized.contains("\"refresh\": 120.0"));
    assert!(serialized.contains("\"width\": 3840"));
    assert!(serialized.contains("\"height\": 2160"));

    // Verify round-trip deserialization
    let deserialized: OutputsPayload =
        serde_json::from_str(&serialized).expect("deserialization succeeds");
    assert_eq!(payload, deserialized);
}

#[test]
fn select_output_request_deserialization() {
    let json_str =
        r#"{"id": "HDMI-A-1", "mode": {"width": 3840, "height": 2160, "refresh": 60.0}}"#;
    let req: SelectOutputRequest = serde_json::from_str(json_str).unwrap();
    assert_eq!(req.id, "HDMI-A-1");
    assert_eq!(
        req.mode,
        Some(DisplayMode {
            width: 3840,
            height: 2160,
            refresh: 60.0
        })
    );

    // Without mode
    let json_no_mode = r#"{"id": "virtual"}"#;
    let req_no_mode: SelectOutputRequest = serde_json::from_str(json_no_mode).unwrap();
    assert_eq!(req_no_mode.id, "virtual");
    assert_eq!(req_no_mode.mode, None);
}

// ---------------------------------------------------------------------------
// 9. Discover Outputs via Commands and Files
// ---------------------------------------------------------------------------

#[test]
fn discover_outputs_with_stream_output_file() {
    let cmd = FakeCommands::default();
    let files = FakeFiles::default();

    let layout = Layout {
        config_dir: PathBuf::from("/etc/event-horizon"),
        home: PathBuf::from("/home/user"),
        companion: PathBuf::from("/usr/bin/event-horizon-companion"),
        path_dirs: vec![],
        session_type: Some("wayland".to_string()),
        desktop: Some("KDE".to_string()),
    };

    // Populate stream-output with "HDMI-A-1"
    files.write(&layout.stream_output(), "HDMI-A-1\n").unwrap();

    let kscreen_json = json!({
        "outputs": [
            {
                "name": "DP-1",
                "connected": true,
                "enabled": true,
                "size": { "width": 1920, "height": 1080 }
            },
            {
                "name": "HDMI-A-1",
                "connected": true,
                "enabled": true,
                "size": { "width": 3840, "height": 2160 }
            }
        ]
    })
    .to_string();

    cmd.capture_answers.lock().unwrap().push_back(kscreen_json);

    let payload = discover_outputs(&cmd, &files, &layout).expect("discovery succeeds");
    assert_eq!(payload.active_id, "HDMI-A-1");
    assert_eq!(payload.outputs.len(), 3); // DP-1, HDMI-A-1, virtual
}

#[test]
fn virtual_modes_exposes_curated_presets_and_deduplicates_current_mode() {
    let current = DisplayMode {
        width: 2560,
        height: 1600,
        refresh: 60.0,
    };
    let modes = virtual_modes(Some(&current), vec![current.clone()]);
    assert_eq!(modes.len(), 10);

    let expected = vec![
        (2560, 1600, 120.0),
        (2560, 1600, 90.0),
        (2560, 1600, 60.0),
        (2560, 1440, 120.0),
        (2560, 1440, 90.0),
        (2560, 1440, 60.0),
        (1920, 1200, 120.0),
        (1920, 1200, 60.0),
        (1920, 1080, 120.0),
        (1920, 1080, 60.0),
    ];
    for (idx, (w, h, r)) in expected.into_iter().enumerate() {
        assert_eq!(modes[idx].width, w);
        assert_eq!(modes[idx].height, h);
        assert_eq!(modes[idx].refresh, r);
    }

    let custom = DisplayMode {
        width: 1470,
        height: 956,
        refresh: 60.0,
    };
    let with_custom = virtual_modes(Some(&custom), vec![]);
    assert_eq!(with_custom.len(), 11);
    assert!(with_custom.contains(&custom));
}
