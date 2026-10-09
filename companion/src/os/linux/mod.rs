//! Linux adapters (KDE Plasma on Wayland first; any freedesktop session).

mod awake;
mod install;
mod prompt;
pub use awake::SessionInhibit;
pub use install::install;
pub use prompt::Notification;
