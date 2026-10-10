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
    /// Sunshine's apps document: `{"apps": [...], ...}`.
    fn apps(&self) -> impl Future<Output = Result<serde_json::Value, SunshineError>> + Send;

    /// Save one app at `index` in the current list, or add it with -1.
    /// Sunshine sorts the list by name afterwards, so indexes go stale.
    fn save_app(
        &self,
        index: i64,
        app: serde_json::Value,
    ) -> impl Future<Output = Result<(), SunshineError>> + Send;

    /// Completes the pairing the Mac started with Sunshine under its id, using
    /// the PIN the Mac chose, and lists the new client as `mac_name`. Sunshine
    /// holds a started pairing for 5 minutes. Returns Sunshine's id for the
    /// client it added, when it can tell which one that is.
    fn submit_pin(
        &self,
        mac_id: &str,
        mac_name: &str,
        pin: &str,
    ) -> impl Future<Output = Result<Option<String>, SunshineError>> + Send;

    /// Removes one paired client. A client Sunshine no longer knows is not an error.
    fn unpair(&self, client: &str) -> impl Future<Output = Result<(), SunshineError>> + Send;
}

/// Keeps the PC's display on and its screen unlocked. Dropping the guard
/// gives the PC back its own idle and lock timers.
pub trait Awake: Send + Sync {
    type Guard: Send + 'static;
    fn hold(&self) -> Self::Guard;
}

/// The games this PC has installed, ready to offer on the Mac's shelf
/// (launch command and a PNG cover included).
pub trait GameSources: Send + Sync {
    fn installed(&self) -> Vec<crate::library::LibraryGame>;
}
