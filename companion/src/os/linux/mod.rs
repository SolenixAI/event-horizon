//! Linux adapters (KDE Plasma on Wayland first; any freedesktop session).

pub mod audio;
mod awake;
mod install;
pub mod outputs;
mod prompt;
mod system;
pub use audio::{discover_audio, select_audio_sink};
pub use awake::SessionInhibit;
pub use install::{
    guard_virtual_screen, install, place_virtual_screen, screen_skip, stream_screen,
    sunshine_watchdog,
};
pub use outputs::discover_outputs;
pub use prompt::Notification;
pub(crate) use system::{SystemCommands, SystemFiles};
