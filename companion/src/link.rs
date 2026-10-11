//! Link: the Mac's way in, over the home network, on HTTPS with the
//! companion's own certificate (the Mac pins its fingerprint). `GET /hello`
//! says the companion is here; then:
//!
//! - `POST /pair` returns the code the PC shows, at once, and a ticket.
//!   `GET /pair/{ticket}` waits for the person at the PC; on Allow the Mac
//!   gets a token it keeps.
//! - `POST /lease` (with the token) keeps the PC awake for `LEASE_TTL`.
//! - `DELETE /pair` (with the token) unpairs the Mac, here and in Sunshine.
//!
//! Tokens are stored as SHA-256 hashes in one JSON file, so a restart keeps
//! every Mac paired (a Mac must never pair twice: see DESIGN.md).

use crate::host::{Host, PairOutcome, PairRequest, new_code};
use crate::ports::{Awake, Prompt, SunshineApi, SunshineError};
use crate::tls::TlsListener;
use axum::extract::{Path, State};
use axum::http::{HeaderMap, StatusCode};
use axum::routing::{get, post};
use axum::{Json, Router};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::path::{Path as FsPath, PathBuf};
use std::sync::{Arc, Mutex};
use tokio::task::JoinHandle;

struct Link<S, P, A: Awake> {
    host: Arc<Host<S, P, A>>,
    macs: PathBuf,
    /// Pairing requests the Mac has not collected the answer to yet.
    asks: Mutex<HashMap<String, Ask>>,
}

struct Ask {
    mac_id: String,
    mac_name: String,
    answer: JoinHandle<PairOutcome>,
}

/// Serve the Mac over TLS until the listener closes.
pub async fn serve<S, P, A>(
    listener: tokio::net::TcpListener,
    tls: tokio_rustls::TlsAcceptor,
    host: Host<S, P, A>,
    macs: PathBuf,
) where
    S: SunshineApi + 'static,
    P: Prompt + 'static,
    A: Awake + 'static,
{
    let link = Arc::new(Link {
        host: Arc::new(host),
        macs,
        asks: Mutex::new(HashMap::new()),
    });
    let app = Router::new()
        .route("/hello", get(hello))
        .route("/pair", post(ask::<S, P, A>).delete(unpair::<S, P, A>))
        .route("/pair/{ticket}", get(answer::<S, P, A>))
        .route("/lease", post(lease::<S, P, A>))
        .with_state(link);
    let _ = axum::serve(TlsListener::new(listener, tls), app).await;
}

/// Step one: the Mac asks. The PC shows the code at once and the answer
/// comes later, to whoever holds the ticket.
async fn ask<S, P, A>(
    State(link): State<Arc<Link<S, P, A>>>,
    Json(request): Json<PairRequest>,
) -> (StatusCode, Json<Value>)
where
    S: SunshineApi + 'static,
    P: Prompt + 'static,
    A: Awake + 'static,
{
    let code = new_code();
    let ticket = new_ticket();
    let (mac_id, mac_name) = (request.mac_id.clone(), request.mac_name.clone());
    let host = link.host.clone();
    let shown = code.clone();
    let answer = tokio::spawn(async move { host.pair(request, code).await });
    let mut asks = link.asks.lock().unwrap();
    // A request nobody collected, from a Mac that went away, is dropped.
    asks.retain(|_, ask| !ask.answer.is_finished());
    asks.insert(
        ticket.clone(),
        Ask {
            mac_id,
            mac_name,
            answer,
        },
    );
    (StatusCode::OK, Json(json!({ "code": shown, "ticket": ticket })))
}

/// Step two: the Mac waits for the person at the PC to answer.
async fn answer<S, P, A>(
    State(link): State<Arc<Link<S, P, A>>>,
    Path(ticket): Path<String>,
) -> (StatusCode, Json<Value>)
where
    S: SunshineApi + 'static,
    P: Prompt + 'static,
    A: Awake + 'static,
{
    let Some(ask) = link.asks.lock().unwrap().remove(&ticket) else {
        return (StatusCode::NOT_FOUND, Json(json!({ "outcome": "unknown" })));
    };
    let outcome = ask.answer.await.unwrap_or(PairOutcome::Expired);
    let (status, name) = match outcome {
        PairOutcome::Paired { sunshine_client } => {
            // Sunshine refuses a certificate that more than one record holds, so
            // the Mac's earlier record goes once its new one exists. When Sunshine
            // could not say which record is new, the earlier one stays.
            let earlier = sunshine_client_of(&link.macs, &ask.mac_id);
            if let (Some(earlier), Some(new)) = (&earlier, &sunshine_client)
                && earlier != new
                && let Err(error) = link.host.sunshine().unpair(earlier).await
            {
                eprintln!("pairing: could not remove the earlier Sunshine record: {error:?}");
            }
            let token = new_token();
            remember(&link.macs, &ask.mac_id, &ask.mac_name, &token, sunshine_client);
            return (
                StatusCode::OK,
                Json(json!({ "outcome": "paired", "token": token })),
            );
        }
        PairOutcome::Denied => (StatusCode::FORBIDDEN, "denied"),
        PairOutcome::Expired => (StatusCode::REQUEST_TIMEOUT, "expired"),
        PairOutcome::Replaced => (StatusCode::CONFLICT, "replaced"),
        PairOutcome::SunshineDown => (StatusCode::BAD_GATEWAY, "sunshine_down"),
    };
    (status, Json(json!({ "outcome": name })))
}

/// The body may carry the Mac's usage-stats choice, `{"share_usage_stats": true}`,
/// which decides whether this PC may send its crash reports.
async fn lease<S, P, A>(
    State(link): State<Arc<Link<S, P, A>>>,
    headers: HeaderMap,
    body: String,
) -> StatusCode
where
    S: SunshineApi + 'static,
    P: Prompt + 'static,
    A: Awake + 'static,
{
    let Some(mac_id) = paired_mac(&link.macs, &headers) else {
        return StatusCode::UNAUTHORIZED;
    };
    let choice = serde_json::from_str::<Value>(&body).ok();
    if let Some(share) = choice.and_then(|c| c["share_usage_stats"].as_bool()) {
        remember_stats_choice(&link.macs, &mac_id, share);
        if share {
            tokio::spawn(crate::crash::send_due(link.macs.clone()));
        } else {
            crate::crash::drop_unless_shared(&link.macs);
        }
    }
    link.host.lease(&mac_id).await;
    StatusCode::NO_CONTENT
}

/// The Mac removes its own pairing: its record here, and its client in Sunshine.
/// If Sunshine cannot be reached, nothing is removed, so the Mac can try again.
async fn unpair<S, P, A>(
    State(link): State<Arc<Link<S, P, A>>>,
    headers: HeaderMap,
) -> StatusCode
where
    S: SunshineApi + 'static,
    P: Prompt + 'static,
    A: Awake + 'static,
{
    let Some(mac_id) = paired_mac(&link.macs, &headers) else {
        return StatusCode::UNAUTHORIZED;
    };
    match unpair_mac(link.host.sunshine(), &link.macs, &mac_id).await {
        Ok(true) => StatusCode::NO_CONTENT,
        Ok(false) => StatusCode::NOT_FOUND,
        Err(_) => StatusCode::BAD_GATEWAY,
    }
}

/// Open to anyone on the network: it only says this PC runs the companion.
async fn hello() -> Json<Value> {
    Json(json!({ "app": "event-horizon-companion", "v": 1 }))
}

/// Forget one Mac: its client in Sunshine first (when this companion made
/// one), then its record. Returns false when no such Mac is paired.
pub async fn unpair_mac<S: SunshineApi>(
    sunshine: &S,
    macs: &FsPath,
    mac_id: &str,
) -> Result<bool, SunshineError> {
    let document = load(macs);
    let list = document["macs"].as_array().expect("macs is an array");
    let Some(record) = list.iter().find(|m| m["mac_id"] == mac_id).cloned() else {
        return Ok(false);
    };
    if let Some(client) = record["sunshine_client"].as_str() {
        sunshine.unpair(client).await?;
    }
    edit(macs, |document| {
        if let Some(list) = document["macs"].as_array_mut() {
            list.retain(|m| m["mac_id"] != mac_id);
        }
        true
    });
    Ok(true)
}

/// The Macs paired with this companion: (id, name), in the order they paired.
pub fn list(macs: &FsPath) -> Vec<(String, String)> {
    load(macs)["macs"]
        .as_array()
        .map(|list| {
            list.iter()
                .filter_map(|m| {
                    Some((
                        m["mac_id"].as_str()?.to_string(),
                        m["mac_name"].as_str()?.to_string(),
                    ))
                })
                .collect()
        })
        .unwrap_or_default()
}

fn new_random_hex(bytes: usize) -> String {
    let mut buffer = vec![0u8; bytes];
    getrandom::fill(&mut buffer).expect("the OS gives random bytes");
    buffer.iter().map(|b| format!("{b:02x}")).collect()
}

/// An unguessable ticket: only the Mac that asked can collect the answer.
fn new_ticket() -> String {
    new_random_hex(16)
}

fn new_token() -> String {
    new_random_hex(32)
}

fn hash(token: &str) -> String {
    Sha256::digest(token.as_bytes())
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect()
}

fn load(macs: &FsPath) -> Value {
    std::fs::read_to_string(macs)
        .ok()
        .and_then(|text| serde_json::from_str(&text).ok())
        .unwrap_or_else(|| json!({ "macs": [] }))
}

/// One writer at a time: a lease, a pairing and an unpair each read, change and
/// write the whole file, so without the lock one could undo another.
fn edit(macs: &FsPath, change: impl FnOnce(&mut Value) -> bool) {
    static LOCK: Mutex<()> = Mutex::new(());
    let _held = LOCK.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
    let mut document = load(macs);
    if change(&mut document) {
        save(macs, &document);
    }
}

fn save(macs: &FsPath, document: &Value) {
    if let Some(dir) = macs.parent() {
        let _ = std::fs::create_dir_all(dir);
    }
    let _ = std::fs::write(
        macs,
        serde_json::to_string_pretty(document).expect("JSON serialises"),
    );
}

/// The Sunshine client this companion recorded for a Mac, if any.
fn sunshine_client_of(macs: &FsPath, mac_id: &str) -> Option<String> {
    load(macs)["macs"]
        .as_array()?
        .iter()
        .find(|m| m["mac_id"] == mac_id)?["sunshine_client"]
        .as_str()
        .map(str::to_string)
}

/// Store the Mac's token hash and its Sunshine client; a newer pairing of the
/// same Mac replaces the record.
fn remember(
    macs: &FsPath,
    mac_id: &str,
    mac_name: &str,
    token: &str,
    sunshine_client: Option<String>,
) {
    edit(macs, |document| {
        let list = document["macs"].as_array_mut().expect("macs is an array");
        list.retain(|m| m["mac_id"] != mac_id);
        list.push(json!({
            "mac_id": mac_id,
            "mac_name": mac_name,
            "token_sha256": hash(token),
            "sunshine_client": sunshine_client,
        }));
        true
    });
}

/// Keep the Mac's choice, and since when it has shared: a crash is reported
/// only to a choice made before it.
fn remember_stats_choice(macs: &FsPath, mac_id: &str, share: bool) {
    edit(macs, |document| {
        let Some(list) = document["macs"].as_array_mut() else {
            return false;
        };
        let Some(record) = list.iter_mut().find(|m| m["mac_id"] == mac_id) else {
            return false;
        };
        if record["share_usage_stats"].as_bool() == Some(share) {
            return false;
        }
        record["share_usage_stats"] = json!(share);
        record["share_since"] = if share {
            json!(crate::crash::now())
        } else {
            Value::Null
        };
        true
    });
}

/// True when a paired Mac shares usage stats and chose to before `at` (Unix seconds).
pub fn shared_before(macs: &FsPath, at: u64) -> bool {
    load(macs)["macs"].as_array().is_some_and(|list| {
        list.iter().any(|m| {
            m["share_usage_stats"] == true
                && m["share_since"].as_u64().is_some_and(|since| since <= at)
        })
    })
}

/// True when any paired Mac has turned on usage stats.
pub fn any_mac_shares_stats(macs: &FsPath) -> bool {
    load(macs)["macs"]
        .as_array()
        .is_some_and(|list| list.iter().any(|m| m["share_usage_stats"] == true))
}

/// The Mac whose token this request carries, if it is one we paired.
fn paired_mac(macs: &FsPath, headers: &HeaderMap) -> Option<String> {
    let token = headers
        .get("authorization")?
        .to_str()
        .ok()?
        .strip_prefix("Bearer ")?;
    let wanted = hash(token);
    load(macs)["macs"]
        .as_array()?
        .iter()
        .find(|m| m["token_sha256"] == wanted.as_str())
        .and_then(|m| m["mac_id"].as_str())
        .map(str::to_string)
}
