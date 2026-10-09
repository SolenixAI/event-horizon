//! Sunshine's local config API on this PC (https://127.0.0.1:47990), the
//! same on Windows and Linux. Routes and shapes are from Sunshine
//! v2026.914 `src/confighttp.cpp` (see docs/research/companion.md, section 2).

use crate::ports::{SunshineApi, SunshineError};
use serde_json::{Value, json};
use std::time::Duration;

/// The waiting pairing `mac_name` started, newest first. Sunshine lists
/// pairings in the order they arrived.
pub fn pairing_for(pending: &Value, mac_name: &str) -> Option<String> {
    pending["pairings"]
        .as_array()?
        .iter()
        .rev()
        .find(|p| p["name"] == mac_name)
        .and_then(|p| p["id"].as_str())
        .map(str::to_string)
}

/// The companion's login to Sunshine's web API, set by the installer.
pub struct LocalSunshine {
    base: String,
    user: String,
    password: String,
    http: reqwest::Client,
}

impl LocalSunshine {
    /// Sunshine on this PC. Its certificate is self-signed, so the client
    /// accepts it; the address is loopback only, so nothing else can answer.
    pub fn new(user: impl Into<String>, password: impl Into<String>) -> Self {
        Self::at("https://127.0.0.1:47990", user, password)
    }

    pub fn at(
        base: impl Into<String>,
        user: impl Into<String>,
        password: impl Into<String>,
    ) -> Self {
        let http = reqwest::Client::builder()
            .danger_accept_invalid_certs(true)
            .timeout(Duration::from_secs(5))
            .build()
            .expect("an HTTP client with default settings builds");
        Self {
            base: base.into(),
            user: user.into(),
            password: password.into(),
            http,
        }
    }

    async fn pending(&self) -> Result<Value, SunshineError> {
        let response = self
            .http
            .get(format!("{}/api/pin", self.base))
            .basic_auth(&self.user, Some(&self.password))
            .send()
            .await
            .map_err(|e| SunshineError::Unreachable(format!("{e:?}")))?;
        if !response.status().is_success() {
            return Err(SunshineError::Rejected(format!(
                "pending pairings: {}",
                response.status()
            )));
        }
        response
            .json()
            .await
            .map_err(|e| SunshineError::Rejected(e.to_string()))
    }
}

impl SunshineApi for LocalSunshine {
    async fn submit_pin(&self, mac_name: &str, pin: &str) -> Result<(), SunshineError> {
        // The Mac starts its pairing with Sunshine as it asks us, so its
        // pending entry may land a moment later: look for up to 10 s.
        let mut pairing = None;
        for _ in 0..20 {
            pairing = pairing_for(&self.pending().await?, mac_name);
            if pairing.is_some() {
                break;
            }
            tokio::time::sleep(Duration::from_millis(500)).await;
        }
        let Some(pairing_id) = pairing else {
            return Err(SunshineError::Rejected(format!(
                "no pairing from {mac_name} is waiting"
            )));
        };
        // No Origin header: Sunshine skips the browser CSRF check for API clients.
        let response = self
            .http
            .post(format!("{}/api/pin", self.base))
            .basic_auth(&self.user, Some(&self.password))
            .json(&json!({ "pairing_id": pairing_id, "pin": pin, "name": mac_name }))
            .send()
            .await
            .map_err(|e| SunshineError::Unreachable(format!("{e:?}")))?;
        let body: Value = response
            .json()
            .await
            .map_err(|e| SunshineError::Rejected(e.to_string()))?;
        if body["status"] == true {
            Ok(())
        } else {
            Err(SunshineError::Rejected(format!(
                "Sunshine refused the PIN: {body}"
            )))
        }
    }
}
