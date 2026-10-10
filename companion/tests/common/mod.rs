#![allow(dead_code)] // each test file uses only some of these fakes
//! In-memory adapters for the Host's ports. Tests drive the Host only
//! through its interface; these stand in for the PC.

use event_horizon_companion::{Awake, Decision, Prompt, SunshineApi, SunshineError};
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

/// Sunshine that records every PIN it is given and every client it unpairs.
#[derive(Clone)]
pub struct FakeSunshine {
    /// (Mac name, PIN) for every PIN Sunshine was given.
    pub pins: Arc<Mutex<Vec<(String, String)>>>,
    /// Sunshine's client id for every Mac it unpaired, in order.
    pub unpaired: Arc<Mutex<Vec<String>>>,
    pub down: Arc<AtomicBool>,
    /// Sunshine's apps document, and how many saves it took.
    pub apps: Arc<Mutex<serde_json::Value>>,
    pub saves: Arc<Mutex<usize>>,
}

impl Default for FakeSunshine {
    fn default() -> Self {
        Self {
            pins: Default::default(),
            unpaired: Default::default(),
            down: Default::default(),
            apps: Arc::new(Mutex::new(serde_json::json!({ "apps": [], "env": {} }))),
            saves: Default::default(),
        }
    }
}

impl FakeSunshine {
    /// From now on every call fails, as if Sunshine stopped.
    pub fn go_down(&self) {
        self.down.store(true, Ordering::SeqCst);
    }

    /// Sunshine answers again.
    pub fn come_up(&self) {
        self.down.store(false, Ordering::SeqCst);
    }

    fn is_down(&self) -> bool {
        self.down.load(Ordering::SeqCst)
    }
}

impl SunshineApi for FakeSunshine {
    async fn apps(&self) -> Result<serde_json::Value, SunshineError> {
        if self.is_down() {
            return Err(SunshineError::Unreachable("fake: down".into()));
        }
        Ok(self.apps.lock().unwrap().clone())
    }

    /// Like Sunshine: -1 adds, an index replaces, then the list is sorted by name.
    async fn save_app(&self, index: i64, app: serde_json::Value) -> Result<(), SunshineError> {
        if self.is_down() {
            return Err(SunshineError::Unreachable("fake: down".into()));
        }
        let mut document = self.apps.lock().unwrap();
        let list = document["apps"].as_array_mut().unwrap();
        if index == -1 {
            list.push(app);
        } else {
            list[index as usize] = app;
        }
        list.sort_by(|a, b| a["name"].as_str().cmp(&b["name"].as_str()));
        *self.saves.lock().unwrap() += 1;
        Ok(())
    }

    /// Like Sunshine, every pairing adds a new client: `uuid-<mac id>` the first
    /// time, `uuid-<mac id>-<n>` for the nth pairing of the same Mac.
    async fn submit_pin(
        &self,
        mac_id: &str,
        mac_name: &str,
        pin: &str,
    ) -> Result<Option<String>, SunshineError> {
        if self.is_down() {
            return Err(SunshineError::Unreachable("fake: down".into()));
        }
        let mut pins = self.pins.lock().unwrap();
        pins.push((mac_name.to_string(), pin.to_string()));
        let pairings = pins.iter().filter(|(name, _)| name == mac_name).count();
        Ok(Some(if pairings == 1 {
            format!("uuid-{mac_id}")
        } else {
            format!("uuid-{mac_id}-{pairings}")
        }))
    }

    async fn unpair(&self, client: &str) -> Result<(), SunshineError> {
        if self.is_down() {
            return Err(SunshineError::Unreachable("fake: down".into()));
        }
        self.unpaired.lock().unwrap().push(client.to_string());
        Ok(())
    }
}

/// The person at the PC: answers after `delay`, or never. Records each code
/// it was asked to show.
#[derive(Clone)]
pub struct FakePrompt {
    pub answer: Option<Decision>,
    pub delay: Duration,
    pub codes: Arc<Mutex<Vec<String>>>,
}

impl FakePrompt {
    pub fn answers(answer: Decision) -> Self {
        Self {
            answer: Some(answer),
            delay: Duration::from_secs(3),
            codes: Default::default(),
        }
    }

    pub fn after(answer: Option<Decision>, delay: Duration) -> Self {
        Self {
            answer,
            delay,
            codes: Default::default(),
        }
    }
}

impl Prompt for FakePrompt {
    async fn ask_allow(&self, _mac_name: &str, code: &str) -> Decision {
        self.codes.lock().unwrap().push(code.to_string());
        tokio::time::sleep(self.delay).await;
        match self.answer {
            Some(answer) => answer,
            None => std::future::pending().await,
        }
    }
}

/// The PC's display: counts who is holding it awake right now, and how many
/// holds were ever taken.
#[derive(Clone, Default)]
pub struct FakeAwake {
    active: Arc<AtomicUsize>,
    taken: Arc<AtomicUsize>,
}

impl FakeAwake {
    pub fn held(&self) -> usize {
        self.active.load(Ordering::SeqCst)
    }
    pub fn holds_taken(&self) -> usize {
        self.taken.load(Ordering::SeqCst)
    }
}

pub struct FakeAwakeGuard(Arc<AtomicUsize>);

impl Drop for FakeAwakeGuard {
    fn drop(&mut self) {
        self.0.fetch_sub(1, Ordering::SeqCst);
    }
}

impl Awake for FakeAwake {
    type Guard = FakeAwakeGuard;
    fn hold(&self) -> FakeAwakeGuard {
        self.active.fetch_add(1, Ordering::SeqCst);
        self.taken.fetch_add(1, Ordering::SeqCst);
        FakeAwakeGuard(self.active.clone())
    }
}

/// A Host on fakes that never need a person: Allow at once, Sunshine up.
pub fn host_on_fakes() -> (
    event_horizon_companion::Host<FakeSunshine, FakePrompt, FakeAwake>,
    FakeAwake,
) {
    let awake = FakeAwake::default();
    let host = event_horizon_companion::Host::new(
        FakeSunshine::default(),
        FakePrompt::answers(Decision::Allow),
        awake.clone(),
    );
    (host, awake)
}

/// A PC with a fixed list of installed games.
pub struct FakeGames(pub Vec<event_horizon_companion::library::LibraryGame>);

impl event_horizon_companion::GameSources for FakeGames {
    fn installed(&self) -> Vec<event_horizon_companion::library::LibraryGame> {
        self.0.clone()
    }
}
