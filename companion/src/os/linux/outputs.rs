//! Linux KScreen output discovery using real PC system commands and files.

use super::system::{SystemCommands, SystemFiles};
use crate::linux_install::Layout;
use crate::outputs::{self, OutputsPayload};
use std::path::Path;

/// Discovers connected displays using `kscreen-doctor --json` and the companion's
/// configured `stream-output`.
pub fn discover_outputs(config_dir: &Path) -> Result<OutputsPayload, String> {
    let layout = Layout::from_env(config_dir, std::env::current_exe().unwrap_or_default());
    outputs::discover_outputs(&SystemCommands, &SystemFiles, &layout)
}
