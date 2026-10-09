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
    Unreachable,
    Rejected(String),
}

/// Sunshine's local config API on this PC.
pub trait SunshineApi: Send + Sync {
    /// Completes a pairing a Mac started with Sunshine, using the Mac's PIN.
    fn submit_pin(&self, pin: &str) -> impl Future<Output = Result<(), SunshineError>> + Send;
}
