//! Event Horizon PC companion: turns a gaming PC into an Event Horizon host.
//! One deep core (`Host`) and small OS seams. See docs/companion/DESIGN.md.

mod host;
pub mod library;
pub mod os;
mod ports;
pub mod steam;

pub use host::{Host, LEASE_TTL, PAIR_TIMEOUT, PairOutcome, PairRequest};
pub use ports::{Awake, Decision, Prompt, SunshineApi, SunshineError};
