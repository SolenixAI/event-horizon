#![allow(dead_code)] // each test file uses only some of these fakes
//! In-memory adapters for the Host's ports. Tests drive the Host only
//! through its interface; these stand in for the PC.

use event_horizon_companion::{Awake, Decision, Prompt, SunshineApi, SunshineError};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

/// Sunshine that records every PIN it is given.
#[derive(Clone, Default)]
pub struct FakeSunshine {
    pub pins: Arc<Mutex<Vec<String>>>,
    pub down: bool,
}

impl SunshineApi for FakeSunshine {
    async fn submit_pin(&self, pin: &str) -> Result<(), SunshineError> {
        if self.down {
            return Err(SunshineError::Unreachable);
        }
        self.pins.lock().unwrap().push(pin.to_string());
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
