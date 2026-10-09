//! Windows adapters.

mod awake;
mod prompt;
pub use awake::{PowerRequest, REASON};
pub use prompt::Dialog;
