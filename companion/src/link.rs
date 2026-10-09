//! Link: the Mac's way in, over the home network. `GET /hello` says the
//! companion is here; then three requests:
//!
//! - `POST /pair` asks the person at the PC; on Allow, Sunshine takes the
//!   Mac's PIN and the Mac gets a token it keeps.
//! - `POST /lease` (with the token) keeps the PC awake for `LEASE_TTL`.
//! - `GET /status` (with the token) says what is on the PC. (Next slice.)
//!
//! Tokens are stored as SHA-256 hashes in one JSON file, so a restart keeps
//! every Mac paired (a Mac must never pair twice: see DESIGN.md).

use crate::host::{Host, PairOutcome, PairRequest};
use crate::ports::{Awake, Prompt, SunshineApi};
use axum::extract::State;
use axum::http::{HeaderMap, StatusCode};
use axum::routing::{get, post};
use axum::{Json, Router};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::path::PathBuf;
use std::sync::Arc;

struct Link<S, P, A: Awake> {
    host: Host<S, P, A>,
    macs: PathBuf,
}

/// Serve the Mac until the listener closes.
pub async fn serve<S, P, A>(listener: tokio::net::TcpListener, host: Host<S, P, A>, macs: PathBuf)
where
    S: SunshineApi + 'static,
    P: Prompt + 'static,
    A: Awake + 'static,
{
    let link = Arc::new(Link { host, macs });
    let app = Router::new()
        .route("/hello", get(hello))
        .route("/pair", post(pair::<S, P, A>))
        .route("/lease", post(lease::<S, P, A>))
        .with_state(link);
    let _ = axum::serve(listener, app).await;
}

async fn pair<S, P, A>(
    State(link): State<Arc<Link<S, P, A>>>,
    Json(request): Json<PairRequest>,
) -> (StatusCode, Json<Value>)
where
    S: SunshineApi + 'static,
    P: Prompt + 'static,
    A: Awake + 'static,
{
    let (mac_id, mac_name) = (request.mac_id.clone(), request.mac_name.clone());
    let (status, outcome) = match link.host.pair(request).await {
        PairOutcome::Paired => {
            let token = new_token();
            remember(&link.macs, &mac_id, &mac_name, &token);
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
    (status, Json(json!({ "outcome": outcome })))
}

async fn lease<S, P, A>(State(link): State<Arc<Link<S, P, A>>>, headers: HeaderMap) -> StatusCode
where
    S: SunshineApi + 'static,
    P: Prompt + 'static,
    A: Awake + 'static,
{
    let Some(mac_id) = paired_mac(&link.macs, &headers) else {
        return StatusCode::UNAUTHORIZED;
    };
    link.host.lease(&mac_id).await;
    StatusCode::NO_CONTENT
}

/// Open to anyone on the network: it only says this PC runs the companion.
async fn hello() -> Json<Value> {
    Json(json!({ "app": "event-horizon-companion", "v": 1 }))
}

fn new_token() -> String {
    let mut bytes = [0u8; 32];
    getrandom::fill(&mut bytes).expect("the OS gives random bytes");
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

fn hash(token: &str) -> String {
    Sha256::digest(token.as_bytes())
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect()
}

fn load(macs: &PathBuf) -> Value {
    std::fs::read_to_string(macs)
        .ok()
        .and_then(|text| serde_json::from_str(&text).ok())
        .unwrap_or_else(|| json!({ "macs": [] }))
}

/// Store the Mac's token hash; a newer pairing of the same Mac replaces it.
fn remember(macs: &PathBuf, mac_id: &str, mac_name: &str, token: &str) {
    let mut document = load(macs);
    let list = document["macs"].as_array_mut().expect("macs is an array");
    list.retain(|m| m["mac_id"] != mac_id);
    list.push(json!({ "mac_id": mac_id, "mac_name": mac_name, "token_sha256": hash(token) }));
    if let Some(dir) = macs.parent() {
        let _ = std::fs::create_dir_all(dir);
    }
    let _ = std::fs::write(
        macs,
        serde_json::to_string_pretty(&document).expect("JSON serialises"),
    );
}

/// The Mac whose token this request carries, if it is one we paired.
fn paired_mac(macs: &PathBuf, headers: &HeaderMap) -> Option<String> {
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
