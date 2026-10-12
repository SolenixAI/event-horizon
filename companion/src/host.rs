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

/// A Mac asking to pair. `pin` is the PIN the Mac gave Sunshine; none means
/// the Mac is already paired with Sunshine and only needs the companion's
/// token. The Mac's id names its pairing with Sunshine, so it is unique.
#[derive(Clone, Debug, serde::Deserialize)]
pub struct PairRequest {
    pub mac_id: String,
    pub mac_name: String,
    #[serde(default)]
    pub pin: Option<String>,
}

#[derive(Debug, PartialEq, Eq)]
pub enum PairOutcome {
    /// `sunshine_client` is Sunshine's id for the client this pairing added,
    /// when this request added one (none when the Mac was already paired).
    Paired {
        sunshine_client: Option<String>,
    },
    Denied,
    /// Nobody answered at the PC within `PAIR_TIMEOUT`.
    Expired,
    /// The same Mac asked again before this request was answered.
    Replaced,
    /// Allow was clicked, but Sunshine did not take the PIN.
    SunshineDown,
}

/// The six digits both screens show for one pairing request.
pub fn new_code() -> String {
    let mut bytes = [0u8; 4];
    getrandom::fill(&mut bytes).expect("the OS gives random bytes");
    format!("{:06}", u32::from_le_bytes(bytes) % 1_000_000)
}

/// The code as people read it: "123 456". The PC's prompts use it.
#[cfg(any(target_os = "linux", windows))]
pub fn spaced(code: &str) -> String {
    format!("{} {}", &code[..3], &code[3..])
}

pub struct Host<S, P, A: Awake> {
    sunshine: S,
    prompt: P,
    awake: A,
    /// One open request per Mac; sending on the channel replaces it.
    pending: Mutex<HashMap<String, oneshot::Sender<()>>>,
    /// The open requests a paired Mac may answer: Mac id → (name, code, answer).
    waiting: Mutex<HashMap<String, Waiting>>,
    leases: Arc<Leases<A::Guard>>,
}

/// A request a paired Mac can see and answer.
struct Waiting {
    mac_name: String,
    code: String,
    answer: oneshot::Sender<Decision>,
}

/// A request waiting for an answer, as a paired Mac sees it.
#[derive(Clone, Debug, PartialEq, Eq, serde::Serialize)]
pub struct WaitingMac {
    pub mac_id: String,
    pub mac_name: String,
    pub code: String,
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
            waiting: Mutex::new(HashMap::new()),
            leases: Arc::new(Leases {
                seen: Mutex::new(HashMap::new()),
                held: Mutex::new(None),
            }),
        }
    }

    pub fn sunshine(&self) -> &S {
        &self.sunshine
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

    /// The requests waiting for an answer, for a Mac this PC already trusts to
    /// show with their codes. A PC with its monitor off is answered there.
    pub fn waiting(&self) -> Vec<WaitingMac> {
        let mut list: Vec<WaitingMac> = self
            .waiting
            .lock()
            .unwrap()
            .iter()
            .map(|(mac_id, w)| WaitingMac {
                mac_id: mac_id.clone(),
                mac_name: w.mac_name.clone(),
                code: w.code.clone(),
            })
            .collect();
        list.sort_by(|a, b| a.mac_id.cmp(&b.mac_id));
        list
    }

    /// A paired Mac answers the request from `mac_id`. False when none waits.
    pub fn answer_waiting(&self, mac_id: &str, decision: Decision) -> bool {
        match self.waiting.lock().unwrap().remove(mac_id) {
            Some(w) => w.answer.send(decision).is_ok(),
            None => false,
        }
    }

    /// Pair a Mac under the code the PC shows. Nothing happens without Allow,
    /// clicked at the PC or on a Mac it already trusts. A newer request from the
    /// same Mac replaces this one.
    pub async fn pair(&self, request: PairRequest, code: String) -> PairOutcome {
        let (replace, replaced) = oneshot::channel();
        if let Some(older) = self
            .pending
            .lock()
            .unwrap()
            .insert(request.mac_id.clone(), replace)
        {
            let _ = older.send(());
        }

        let (remote, remote_answer) = oneshot::channel();
        self.waiting.lock().unwrap().insert(
            request.mac_id.clone(),
            Waiting {
                mac_name: request.mac_name.clone(),
                code: code.clone(),
                answer: remote,
            },
        );
        // The first answer wins: the PC's prompt, or a Mac this PC trusts.
        let asked = tokio::time::timeout(PAIR_TIMEOUT, async {
            tokio::select! {
                decision = self.prompt.ask_allow(&request.mac_name, &code) => decision,
                Ok(decision) = remote_answer => decision,
            }
        });
        let answer = tokio::select! {
            answer = asked => answer,
            _ = replaced => {
                // The newer request put its own entry in place; leave that one.
                return PairOutcome::Replaced;
            }
        };
        self.pending.lock().unwrap().remove(&request.mac_id);
        self.waiting.lock().unwrap().remove(&request.mac_id);

        match answer {
            Err(_) => PairOutcome::Expired,
            Ok(Decision::Deny) => PairOutcome::Denied,
            Ok(Decision::Allow) => match &request.pin {
                None => PairOutcome::Paired {
                    sunshine_client: None,
                },
                Some(pin) => match self
                    .sunshine
                    .submit_pin(&request.mac_id, &request.mac_name, pin)
                    .await
                {
                    Ok(sunshine_client) => PairOutcome::Paired { sunshine_client },
                    Err(_) => PairOutcome::SunshineDown,
                },
            },
        }
    }
}
