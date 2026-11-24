//! Event Horizon PC companion: turns a gaming PC into an Event Horizon host.
//! One deep core (`Host`) and small OS seams. See docs/companion/DESIGN.md.

pub mod audio;
pub mod crash;
pub mod discovery;
pub mod display_guard;
pub mod games;
mod host;
pub mod library;
pub mod link;
pub mod linux_install;
pub mod os;
pub mod outputs;
pub mod pair_window;
pub mod play;
mod ports;
pub mod setup;
pub mod steam;
pub mod sunshine;
pub mod sunshine_tls;
pub mod sunshine_watchdog;
pub mod tls;
pub mod virtual_screen;

pub use audio::{AudioPayload, HostAudioDevice, SelectAudioRequest};
pub use host::{Host, LEASE_TTL, PAIR_TIMEOUT, PairOutcome, PairRequest, new_code};
pub use outputs::{DisplayMode, HostOutput, OutputsPayload, SelectOutputRequest};
pub use ports::{Awake, Decision, GameSources, Prompt, SunshineApi, SunshineError};
