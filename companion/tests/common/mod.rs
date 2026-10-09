//! In-memory adapters for the Host's ports. Tests drive the Host only
//! through its interface; these stand in for the PC.

use event_horizon_companion::{Decision, Prompt, SunshineApi, SunshineError};
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
