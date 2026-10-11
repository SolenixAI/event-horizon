//! Sunshine's local config API on this PC (https://127.0.0.1:47990), the
//! same on Windows and Linux. Routes and shapes are from Sunshine
//! v2026.914 `src/confighttp.cpp` (see docs/research/companion.md, section 2).

use crate::ports::{SunshineApi, SunshineError};
use crate::sunshine_tls::{load_pinned_der, pinned_client};
use serde_json::{Value, json};
use std::path::PathBuf;
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::Mutex;

/// The waiting pairing that `mac_id` started, newest first. The Mac names its
/// Sunshine pairing by its id, so two Macs with one display name never match.
pub fn pairing_for(pending: &Value, mac_id: &str) -> Option<String> {
    pending["pairings"]
        .as_array()?
        .iter()
        .rev()
        .find(|p| p["name"] == mac_id)
        .and_then(|p| p["id"].as_str())
        .map(str::to_string)
}

/// The waiting pairings a Mac left under its id or its display name, oldest first.
pub fn stale_pairings(pending: &Value, mac_id: &str, mac_name: &str) -> Vec<String> {
    pending["pairings"]
        .as_array()
        .map(|list| {
            list.iter()
                .filter(|p| p["name"] == mac_id || p["name"] == mac_name)
                .filter_map(|p| p["id"].as_str().map(str::to_string))
                .collect()
        })
        .unwrap_or_default()
}

/// The ids of Sunshine's paired clients.
fn client_ids(list: &Value) -> Vec<String> {
    list["named_certs"]
        .as_array()
        .map(|certs| {
            certs
                .iter()
                .filter_map(|c| c["uuid"].as_str().map(str::to_string))
                .collect()
        })
        .unwrap_or_default()
}

/// The companion's login to Sunshine's web API, set by the installer.
#[derive(Clone)]
pub struct LocalSunshine {
    base: String,
    user: String,
    password: String,
    /// Sunshine's certificate, read on every call: it may not be written yet.
    pin_path: PathBuf,
    /// Serialises pairings, so the client a pairing adds is the only new one.
    pairing: Arc<Mutex<()>>,
}

impl LocalSunshine {
    /// Sunshine on this PC, trusted only through the certificate at `pin_path`.
    /// The address is loopback only.
    pub fn new(user: impl Into<String>, password: impl Into<String>, pin_path: PathBuf) -> Self {
        Self::at("https://127.0.0.1:47990", user, password, pin_path)
    }

    pub fn at(
        base: impl Into<String>,
        user: impl Into<String>,
        password: impl Into<String>,
        pin_path: PathBuf,
    ) -> Self {
        Self {
            base: base.into(),
            user: user.into(),
            password: password.into(),
            pin_path,
            pairing: Arc::new(Mutex::new(())),
        }
    }

    /// The client for one call. It trusts only the certificate on disk right
    /// now, so until Sunshine has written that certificate every call is refused.
    fn client(&self) -> Result<reqwest::Client, SunshineError> {
        let pinned = load_pinned_der(&self.pin_path).map_err(SunshineError::Unreachable)?;
        pinned_client(&pinned).map_err(SunshineError::Unreachable)
    }

    async fn get(&self, path: &str) -> Result<Value, SunshineError> {
        let response = self
            .client()?
            .get(format!("{}{path}", self.base))
            .basic_auth(&self.user, Some(&self.password))
            .send()
            .await
            .map_err(|e| SunshineError::Unreachable(format!("{e:?}")))?;
        if !response.status().is_success() {
            return Err(SunshineError::Rejected(format!(
                "{path}: {}",
                response.status()
            )));
        }
        response
            .json()
            .await
            .map_err(|e| SunshineError::Rejected(e.to_string()))
    }

    async fn pending(&self) -> Result<Value, SunshineError> {
        self.get("/api/pin").await
    }

    async fn clients(&self) -> Result<Vec<String>, SunshineError> {
        Ok(client_ids(&self.get("/api/clients/list").await?))
    }
}

impl SunshineApi for LocalSunshine {
    async fn apps(&self) -> Result<Value, SunshineError> {
        self.get("/api/apps").await
    }

    async fn save_app(&self, index: i64, mut app: Value) -> Result<(), SunshineError> {
        app["index"] = json!(index);
        let response = self
            .client()?
            .post(format!("{}/api/apps", self.base))
            .basic_auth(&self.user, Some(&self.password))
            .json(&app)
            .send()
            .await
            .map_err(|e| SunshineError::Unreachable(format!("{e:?}")))?;
        if response.status().is_success() {
            Ok(())
        } else {
            Err(SunshineError::Rejected(format!(
                "save app: {}",
                response.status()
            )))
        }
    }

    async fn submit_pin(
        &self,
        mac_id: &str,
        mac_name: &str,
        pin: &str,
    ) -> Result<Option<String>, SunshineError> {
        let _one_at_a_time = self.pairing.lock().await;
        // The Mac starts its pairing with Sunshine as it asks us, so its
        // pending entry may land a moment later: look for up to 10 s.
        let mut pairing = None;
        for _ in 0..20 {
            pairing = pairing_for(&self.pending().await?, mac_id);
            if pairing.is_some() {
                break;
            }
            tokio::time::sleep(Duration::from_millis(500)).await;
        }
        let Some(pairing_id) = pairing else {
            return Err(SunshineError::Rejected(format!(
                "no pairing from {mac_id} is waiting"
            )));
        };
        let before = self.clients().await?;
        // No Origin header: Sunshine skips the browser CSRF check for API clients.
        let response = self
            .client()?
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
        if body["status"] != true {
            return Err(SunshineError::Rejected(format!(
                "Sunshine refused the PIN: {body}"
            )));
        }
        let after = self.clients().await?;
        Ok(after.into_iter().find(|id| !before.contains(id)))
    }

    async fn cancel_pairings(&self, mac_id: &str, mac_name: &str) -> Result<usize, SunshineError> {
        let mut cancelled = 0;
        for pairing_id in stale_pairings(&self.pending().await?, mac_id, mac_name) {
            // DELETE /api/pin; no Origin header, so Sunshine skips its browser CSRF check.
            let response = self
                .client()?
                .delete(format!("{}/api/pin", self.base))
                .basic_auth(&self.user, Some(&self.password))
                .json(&json!({ "pairing_id": pairing_id }))
                .send()
                .await
                .map_err(|e| SunshineError::Unreachable(format!("{e:?}")))?;
            let body: Value = response
                .json()
                .await
                .map_err(|e| SunshineError::Rejected(e.to_string()))?;
            // `false`: the pairing finished or expired in the meantime.
            if body["status"] == true {
                cancelled += 1;
            }
        }
        Ok(cancelled)
    }

    async fn unpair(&self, client: &str) -> Result<(), SunshineError> {
        // Sunshine answers `status: false` when the client is already gone.
        let response = self
            .client()?
            .post(format!("{}/api/clients/unpair", self.base))
            .basic_auth(&self.user, Some(&self.password))
            .json(&json!({ "uuid": client }))
            .send()
            .await
            .map_err(|e| SunshineError::Unreachable(format!("{e:?}")))?;
        if response.status().is_success() {
            Ok(())
        } else {
            Err(SunshineError::Rejected(format!(
                "unpair: {}",
                response.status()
            )))
        }
    }
}
