//! Linux adapters (KDE Plasma on Wayland first; any freedesktop session).

mod awake;
mod install;
mod prompt;
mod system;
pub use awake::SessionInhibit;
pub use install::{
    guard_virtual_screen, install, place_virtual_screen, screen_skip, stream_screen,
    sunshine_watchdog,
};
pub use prompt::Notification;
pub(crate) use system::{SystemCommands, SystemFiles};
