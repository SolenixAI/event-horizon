//! Linux KScreen output discovery using real PC system commands and files.

use super::system::{SystemCommands, SystemFiles};
use crate::linux_install::Layout;
use crate::outputs::{self, OutputsPayload};
use std::path::{Path, PathBuf};

/// Reads raw EDID bytes for `connector` from `/sys/class/drm/card*-<connector>/edid`.
fn read_sysfs_edid(drm_root: &Path, connector: &str) -> Option<Vec<u8>> {
    let entries = std::fs::read_dir(drm_root).ok()?;
    let suffix = format!("-{connector}");
    for entry in entries.flatten() {
        let name = entry.file_name();
        let Some(name_str) = name.to_str() else {
            continue;
        };
        if let Some(prefix) = name_str.strip_suffix(&suffix)
            && let Some(card_num) = prefix.strip_prefix("card")
            && !card_num.is_empty()
            && card_num.bytes().all(|b| b.is_ascii_digit())
        {
            let edid_path: PathBuf = entry.path().join("edid");
            if let Ok(bytes) = std::fs::read(&edid_path)
                && !bytes.is_empty()
            {
                return Some(bytes);
            }
        }
    }
    None
}

/// Discovers connected displays using `kscreen-doctor --json`, sysfs EDIDs,
/// and the companion's configured `stream-output`.
pub fn discover_outputs(config_dir: &Path) -> Result<OutputsPayload, String> {
    let layout = Layout::from_env(config_dir, std::env::current_exe().unwrap_or_default());
    outputs::discover_outputs_with_edid(&SystemCommands, &SystemFiles, &layout, &|connector| {
        read_sysfs_edid(Path::new("/sys/class/drm"), connector)
    })
}
