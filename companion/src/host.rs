//! The Host: everything the companion does, behind one small interface.

use crate::ports::{Awake, Decision, Prompt, SunshineApi};
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::Duration;
use tokio::sync::oneshot;
use tokio::time::Instant;

/// How long the PC waits for a click on Allow.
pub const PAIR_TIMEOUT: Duration = Duration::from_secs(120);

/// A Mac's lease lasts this long; it renews every 30 s while connected, so
/// two missed renewals in a row are tolerated.
pub const LEASE_TTL: Duration = Duration::from_secs(90);

/// A Mac asking to pair. `pin` is the PIN the Mac gave Sunshine; `code` is
/// the short code both screens show, so the person knows it is their Mac.
#[derive(Clone, Debug, serde::Deserialize)]
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

pub struct Host<S, P, A: Awake> {
    sunshine: S,
    prompt: P,
    awake: A,
    /// One open request per Mac; sending on the channel replaces it.
    pending: Mutex<HashMap<String, oneshot::Sender<()>>>,
    leases: Arc<Leases<A::Guard>>,
}

/// Which Macs checked in when, and the one hold on the PC's display while
/// any of them is still inside its lease.
struct Leases<G> {
    seen: Mutex<HashMap<String, Instant>>,
    held: Mutex<Option<G>>,
}

impl<G> Leases<G> {
    /// Forget Macs whose lease ran out; with none left, let the PC sleep.
    fn sweep(&self) {
        let mut seen = self.seen.lock().unwrap();
        seen.retain(|_, at| at.elapsed() < LEASE_TTL);
        if seen.is_empty() {
            self.held.lock().unwrap().take();
        }
    }
}

impl<S: SunshineApi, P: Prompt, A: Awake> Host<S, P, A> {
    pub fn new(sunshine: S, prompt: P, awake: A) -> Self {
        Self {
            sunshine,
            prompt,
            awake,
            pending: Mutex::new(HashMap::new()),
            leases: Arc::new(Leases {
                seen: Mutex::new(HashMap::new()),
                held: Mutex::new(None),
            }),
        }
    }

    /// A connected Mac checks in. The PC stays awake and unlocked until
    /// `LEASE_TTL` after the last check-in from any Mac.
    pub async fn lease(&self, mac_id: &str) {
        self.leases
            .seen
            .lock()
            .unwrap()
            .insert(mac_id.to_string(), Instant::now());
        self.leases
            .held
            .lock()
            .unwrap()
            .get_or_insert_with(|| self.awake.hold());
        let leases = self.leases.clone();
        tokio::spawn(async move {
            tokio::time::sleep(LEASE_TTL).await;
            leases.sweep();
        });
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
            Ok(Decision::Allow) => match self
                .sunshine
                .submit_pin(&request.mac_name, &request.pin)
                .await
            {
                Ok(()) => PairOutcome::Paired,
                Err(_) => PairOutcome::SunshineDown,
            },
        }
    }
}
