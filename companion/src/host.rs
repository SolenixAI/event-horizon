//! The Host: everything the companion does, behind one small interface.

use crate::ports::{Decision, Prompt, SunshineApi};
use std::collections::HashMap;
use std::sync::Mutex;
use std::time::Duration;
use tokio::sync::oneshot;

/// How long the PC waits for a click on Allow.
pub const PAIR_TIMEOUT: Duration = Duration::from_secs(120);

/// A Mac asking to pair. `pin` is the PIN the Mac gave Sunshine; `code` is
/// the short code both screens show, so the person knows it is their Mac.
#[derive(Clone, Debug)]
pub struct PairRequest {
    pub mac_id: String,
    pub mac_name: String,
    pub pin: String,
    pub code: String,
}

#[derive(Debug, PartialEq, Eq)]
pub enum PairOutcome {
    Paired,
    Denied,
    /// Nobody answered at the PC within `PAIR_TIMEOUT`.
    Expired,
    /// The same Mac asked again before this request was answered.
    Replaced,
    /// Allow was clicked, but Sunshine did not take the PIN.
    SunshineDown,
}

pub struct Host<S, P> {
    sunshine: S,
    prompt: P,
    /// One open request per Mac; sending on the channel replaces it.
    pending: Mutex<HashMap<String, oneshot::Sender<()>>>,
}

impl<S: SunshineApi, P: Prompt> Host<S, P> {
    pub fn new(sunshine: S, prompt: P) -> Self {
        Self {
            sunshine,
            prompt,
            pending: Mutex::new(HashMap::new()),
        }
    }

    /// Pair a Mac. Nothing happens without a click on Allow at the PC. A
    /// newer request from the same Mac replaces this one.
    pub async fn pair(&self, request: PairRequest) -> PairOutcome {
        let (replace, replaced) = oneshot::channel();
        if let Some(older) = self
            .pending
            .lock()
            .unwrap()
            .insert(request.mac_id.clone(), replace)
        {
            let _ = older.send(());
        }

        let asked = tokio::time::timeout(
            PAIR_TIMEOUT,
            self.prompt.ask_allow(&request.mac_name, &request.code),
        );
        let answer = tokio::select! {
            answer = asked => answer,
            _ = replaced => return PairOutcome::Replaced,
        };
        self.pending.lock().unwrap().remove(&request.mac_id);

        match answer {
            Err(_) => PairOutcome::Expired,
            Ok(Decision::Deny) => PairOutcome::Denied,
            Ok(Decision::Allow) => match self.sunshine.submit_pin(&request.pin).await {
                Ok(()) => PairOutcome::Paired,
                Err(_) => PairOutcome::SunshineDown,
            },
        }
    }
}
