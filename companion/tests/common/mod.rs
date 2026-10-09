#![allow(dead_code)] // each test file uses only some of these fakes
//! In-memory adapters for the Host's ports. Tests drive the Host only
//! through its interface; these stand in for the PC.

use event_horizon_companion::{Awake, Decision, Prompt, SunshineApi, SunshineError};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

/// Sunshine that records every PIN it is given.
#[derive(Clone)]
pub struct FakeSunshine {
    /// (Mac name, PIN) for every PIN Sunshine was given.
    pub pins: Arc<Mutex<Vec<(String, String)>>>,
    pub down: bool,
    /// Sunshine's apps document, and how many saves it took.
    pub apps: Arc<Mutex<serde_json::Value>>,
    pub saves: Arc<Mutex<usize>>,
}

impl Default for FakeSunshine {
    fn default() -> Self {
        Self {
            pins: Default::default(),
            down: false,
            apps: Arc::new(Mutex::new(serde_json::json!({ "apps": [], "env": {} }))),
            saves: Default::default(),
        }
    }
}

impl SunshineApi for FakeSunshine {
    async fn apps(&self) -> Result<serde_json::Value, SunshineError> {
        Ok(self.apps.lock().unwrap().clone())
    }

    /// Like Sunshine: -1 adds, an index replaces, then the list is sorted by name.
    async fn save_app(&self, index: i64, app: serde_json::Value) -> Result<(), SunshineError> {
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

    async fn submit_pin(&self, mac_name: &str, pin: &str) -> Result<(), SunshineError> {
        if self.down {
            return Err(SunshineError::Unreachable("fake: down".into()));
        }
        self.pins
            .lock()
            .unwrap()
            .push((mac_name.to_string(), pin.to_string()));
        Ok(())
    }
}

/// The person at the PC: answers after `delay`, or never.
#[derive(Clone)]
pub struct FakePrompt {
    pub answer: Option<Decision>,
    pub delay: Duration,
}

impl FakePrompt {
    pub fn answers(answer: Decision) -> Self {
        Self {
            answer: Some(answer),
            delay: Duration::from_secs(3),
        }
    }
}

impl Prompt for FakePrompt {
    async fn ask_allow(&self, _mac_name: &str, _code: &str) -> Decision {
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
