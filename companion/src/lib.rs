//! Event Horizon PC companion: turns a gaming PC into an Event Horizon host.
//! One deep core (`Host`) and small OS seams. See docs/companion/DESIGN.md.

pub mod discovery;
pub mod games;
mod host;
pub mod library;
pub mod link;
pub mod os;
pub mod play;
mod ports;
pub mod steam;
pub mod sunshine;
pub mod tls;

pub use host::{Host, LEASE_TTL, PAIR_TIMEOUT, PairOutcome, PairRequest, new_code};
pub use ports::{Awake, Decision, GameSources, Prompt, SunshineApi, SunshineError};
