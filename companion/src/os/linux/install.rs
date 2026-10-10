//! `install` on Linux: the steps are in `linux_install`. This wires in the
//! real PC: its environment, its files and its commands.

use crate::linux_install::{self, Layout, SystemCommands, SystemFiles, VirtualScreen};
use crate::virtual_screen::screen_size;
use std::path::Path;

/// Installs on this PC. The virtual screen is skipped, with the reason, where it cannot run.
pub fn install(config_dir: &Path) -> Result<VirtualScreen, String> {
    let exe = std::env::current_exe().map_err(|e| e.to_string())?;
    let layout = Layout::from_env(config_dir, exe);
    linux_install::install(
        &SystemCommands,
        &SystemFiles,
        &layout,
        screen_size(None),
        &linux_install::random_secret,
    )
}

/// Places the virtual screen beside the desk monitor. The screen's unit runs this.
pub fn place_virtual_screen() -> Result<(), String> {
    linux_install::place_virtual_screen(&SystemCommands)
}
