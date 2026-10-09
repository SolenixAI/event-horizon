//! Event Horizon PC companion: turns a gaming PC into an Event Horizon host.
//! One deep core (`Host`) and small OS seams. See docs/companion/DESIGN.md.

mod host;
mod ports;

pub use host::{Host, PAIR_TIMEOUT, PairOutcome, PairRequest};
pub use ports::{Decision, Prompt, SunshineApi, SunshineError};
