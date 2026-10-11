//! `install` on Linux: the steps are in `linux_install`. This wires in the
//! real PC: its environment, its files and its commands.

use crate::linux_install::{self, Layout, SystemCommands, SystemFiles};
use crate::virtual_screen::screen_size;
use std::path::Path;

/// Installs on this PC.
pub fn install(config_dir: &Path) -> Result<(), String> {
    let layout = layout(config_dir)?;
    linux_install::install(
        &SystemCommands,
        &SystemFiles,
        &layout,
        screen_size(None),
        &linux_install::random_secret,
    )
}

/// Why this PC gets no virtual screen, or None when it can have one.
pub fn screen_skip(config_dir: &Path) -> Option<String> {
    let layout = layout(config_dir).ok()?;
    linux_install::screen_skip(&SystemFiles, &layout)
}

/// Places the virtual screen beside the desk monitor. The screen's unit runs this.
pub fn place_virtual_screen() -> Result<(), String> {
    linux_install::place_virtual_screen(&SystemCommands)
}

/// Keeps the virtual screen on. The guard's unit runs this.
pub fn guard_virtual_screen() -> Result<(), String> {
    crate::display_guard::run(&SystemCommands)
}

/// The one-screen mode around a stream. Sunshine runs this as a stream starts and ends.
pub fn stream_screen(config_dir: &Path, on: bool) -> Result<(), String> {
    let layout = layout(config_dir)?;
    linux_install::stream_screen(&SystemCommands, &SystemFiles, &layout, on)
}

fn layout(config_dir: &Path) -> Result<Layout, String> {
    let exe = std::env::current_exe().map_err(|e| e.to_string())?;
    Ok(Layout::from_env(config_dir, exe))
}
