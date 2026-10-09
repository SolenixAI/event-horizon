//! Linux adapters (KDE Plasma on Wayland first; any freedesktop session).

mod awake;
mod prompt;
pub use awake::SessionInhibit;
pub use prompt::Notification;
