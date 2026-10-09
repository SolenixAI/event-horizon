//! The seams the Host reaches the PC through. Each OS supplies adapters.

use std::future::Future;

/// The person at the PC's answer to "Allow this Mac?".
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Decision {
    Allow,
    Deny,
}

/// Asks the person at the PC. The future resolves when they answer; the Host
/// owns the timeout, so an adapter may wait forever.
pub trait Prompt: Send + Sync {
    fn ask_allow(&self, mac_name: &str, code: &str) -> impl Future<Output = Decision> + Send;
}

#[derive(Debug, PartialEq, Eq)]
pub enum SunshineError {
    Unreachable(String),
    Rejected(String),
}

/// Sunshine's local config API on this PC.
pub trait SunshineApi: Send + Sync {
    /// Completes the pairing `mac_name` started with Sunshine, using the PIN
    /// the Mac chose. Sunshine holds a started pairing for 5 minutes.
    fn submit_pin(
        &self,
        mac_name: &str,
        pin: &str,
    ) -> impl Future<Output = Result<(), SunshineError>> + Send;
}

/// Keeps the PC's display on and its screen unlocked. Dropping the guard
/// gives the PC back its own idle and lock timers.
pub trait Awake: Send + Sync {
    type Guard: Send + 'static;
    fn hold(&self) -> Self::Guard;
}
