//! The Linux virtual screen: a Mac-sized output that krfb-virtualmonitor
//! makes on KDE Wayland, which Sunshine streams beside the desk monitor.
//! These are its rules. `linux_install` runs them on the PC.

use serde_json::Value;
use std::fmt;
use std::path::Path;

/// The name krfb-virtualmonitor gives the output; KWin shows `Virtual-<name>`.
pub const NAME: &str = "sunshine-vmon";
/// The connector name, which Sunshine's `output_name` must match.
pub const OUTPUT: &str = "Virtual-sunshine-vmon";
/// The VNC port krfb-virtualmonitor listens on (its default is 5900).
pub const VNC_PORT: u16 = 5905;
/// The Mac's usual display scale, 175 per cent.
pub const SCALE: &str = "1.75";

/// A screen's size in pixels.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Size {
    pub width: u32,
    pub height: u32,
}

impl fmt::Display for Size {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}x{}", self.width, self.height)
    }
}

/// The size used until the Mac reports its own.
pub const DEFAULT_SIZE: Size = Size {
    width: 2560,
    height: 1600,
};

/// The seam for the Mac's display size. `PairRequest` has no display field
/// yet, so callers pass `None`. Pass the reported size here once it exists.
pub fn screen_size(mac_reported: Option<Size>) -> Size {
    mac_reported.unwrap_or(DEFAULT_SIZE)
}

/// True on KDE Plasma running on Wayland, the only session the screen supports.
pub fn is_kde_wayland(session_type: Option<&str>, desktop: Option<&str>) -> bool {
    session_type == Some("wayland")
        && desktop.is_some_and(|d| d.split(':').any(|part| part.eq_ignore_ascii_case("kde")))
}

/// The arguments that place the screen right of the first enabled physical
/// output, at its scale. None until KScreen lists the screen.
pub fn placement_args(kscreen: &Value) -> Option<Vec<String>> {
    let outputs = kscreen["outputs"].as_array()?;
    if !outputs.iter().any(|o| o["name"] == OUTPUT) {
        return None;
    }
    let desk = outputs
        .iter()
        .find(|o| o["name"] != OUTPUT && o["enabled"] == true);
    let x = desk.map_or(0, logical_width);
    Some(vec![
        format!("output.{OUTPUT}.scale.{SCALE}"),
        format!("output.{OUTPUT}.position.{x},0"),
        format!("output.{OUTPUT}.priority.1"),
    ])
}

/// The width in KScreen's logical pixels: the physical width over the scale.
fn logical_width(output: &Value) -> i64 {
    let width = output["size"]["width"].as_f64().unwrap_or(0.0);
    let scale = output["scale"].as_f64().filter(|s| *s > 0.0).unwrap_or(1.0);
    (width / scale).round() as i64
}

/// The user unit that runs krfb-virtualmonitor with the session, then places
/// the screen. The password is in the unit, so the unit file is kept private.
pub fn unit_text(krfb: &Path, placer: &Path, size: Size, password: &str) -> String {
    format!(
        "[Unit]\n\
         Description=Event Horizon virtual screen: a Mac-sized display for Sunshine\n\
         PartOf=graphical-session.target\n\
         After=graphical-session.target\n\
         \n\
         [Service]\n\
         Environment=QT_QPA_PLATFORM=wayland\n\
         ExecStart={krfb} --resolution {size} --name {NAME} --port {VNC_PORT} --password {password}\n\
         ExecStartPost=-{placer} place-virtual-screen\n\
         Restart=on-failure\n\
         RestartSec=5s\n\
         \n\
         [Install]\n\
         WantedBy=graphical-session.target\n",
        krfb = systemd_arg(krfb),
        placer = systemd_arg(placer),
    )
}

/// A path as systemd reads it: quoted when it has a space, with `%` escaped.
fn systemd_arg(path: &Path) -> String {
    let text = path.display().to_string().replace('%', "%%");
    if text.contains(char::is_whitespace) {
        format!("\"{text}\"")
    } else {
        text
    }
}

/// `text` with `key = value` set. Lines for `key` are replaced, and the key
/// is added at the end when it is absent. Every other line stays as it was.
pub fn with_setting(text: &str, key: &str, value: &str) -> String {
    let line = format!("{key} = {value}");
    let mut found = false;
    let mut lines: Vec<String> = text
        .lines()
        .map(|existing| {
            if is_key(existing, key) {
                found = true;
                line.clone()
            } else {
                existing.to_string()
            }
        })
        .collect();
    if !found {
        lines.push(line);
    }
    lines.join("\n") + "\n"
}

fn is_key(line: &str, key: &str) -> bool {
    line.split_once('=')
        .is_some_and(|(name, _)| name.trim() == key)
}
