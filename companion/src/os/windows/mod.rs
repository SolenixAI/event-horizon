//! Windows adapters.

mod awake;
mod install;
mod prompt;
pub use awake::{PowerRequest, REASON};
pub use install::install;
pub use prompt::{Dialog, notice};
