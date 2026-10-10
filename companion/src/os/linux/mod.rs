//! Linux adapters (KDE Plasma on Wayland first; any freedesktop session).

mod awake;
mod install;
mod prompt;
pub use awake::SessionInhibit;
pub use install::{guard_virtual_screen, install, place_virtual_screen, screen_skip};
pub use prompt::Notification;
