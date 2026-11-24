//! Link: the Mac's way in, over the home network, on HTTPS with the
//! companion's own certificate (the Mac pins its fingerprint). `GET /hello`
//! says the companion is here; then:
//!
//! - `POST /pair` returns the code the PC shows, at once, and a ticket.
//!   `GET /pair/{ticket}` waits for the person at the PC; on Allow the Mac
//!   gets a token it keeps.
//! - `POST /lease` (with the token) keeps the PC awake for `LEASE_TTL`.
//! - `DELETE /pair` (with the token) unpairs the Mac, here and in Sunshine.
//! - `GET /pair/waiting` and `POST /pair/waiting/{mac_id}` (with a paired Mac's
//!   token) show and answer other Macs' requests, for a PC whose monitor is off.
//!
//! Tokens are stored as SHA-256 hashes in one JSON file, so a restart keeps
//! every Mac paired (a Mac must never pair twice: see DESIGN.md).

use crate::host::{Host, PairOutcome, PairRequest, new_code};
use crate::outputs::{DisplayMode, OutputsPayload, SelectOutputRequest};
use crate::ports::{Awake, Decision, Prompt, SunshineApi, SunshineError};
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

impl<S, P, A: Awake> Link<S, P, A> {
    fn config_dir(&self) -> PathBuf {
        self.macs
            .parent()
            .map(FsPath::to_path_buf)
            .unwrap_or_else(|| PathBuf::from("."))
    }
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
        .route("/pair/waiting", get(waiting::<S, P, A>))
        .route("/pair/waiting/{mac_id}", post(decide::<S, P, A>))
        .route("/lease", post(lease::<S, P, A>))
        .route("/outputs", get(get_outputs::<S, P, A>))
        .route("/outputs/select", post(select_output::<S, P, A>))
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
    let (mac_id, mac_name) = (request.mac_id.clone(), request.mac_name.clone());
    // The Mac starts its Sunshine handshake only after this answer, so a pairing it
    // left open on an earlier try goes first and cannot refuse the new one. A
    // Sunshine that cannot clear is not a reason to refuse the ask.
    if let Err(e) = link
        .host
        .sunshine()
        .cancel_pairings(&mac_id, &mac_name)
        .await
    {
        eprintln!("pair: could not clear an earlier pairing: {e:?}");
    }
    let code = new_code();
    let ticket = new_ticket();
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
    (
        StatusCode::OK,
        Json(json!({ "code": shown, "ticket": ticket })),
    )
}

/// The requests waiting for an answer, with their codes, for a Mac this PC
/// already trusts: it can answer for a PC whose monitor is off.
async fn waiting<S, P, A>(
    State(link): State<Arc<Link<S, P, A>>>,
    headers: HeaderMap,
) -> (StatusCode, Json<Value>)
where
    S: SunshineApi + 'static,
    P: Prompt + 'static,
    A: Awake + 'static,
{
    if paired_mac(&link.macs, &headers).is_none() {
        return (StatusCode::UNAUTHORIZED, Json(json!({})));
    }
    (
        StatusCode::OK,
        Json(json!({ "waiting": link.host.waiting() })),
    )
}

/// A Mac this PC trusts answers a waiting request: `{"allow": true}` or false.
async fn decide<S, P, A>(
    State(link): State<Arc<Link<S, P, A>>>,
    Path(mac_id): Path<String>,
    headers: HeaderMap,
    body: String,
) -> StatusCode
where
    S: SunshineApi + 'static,
    P: Prompt + 'static,
    A: Awake + 'static,
{
    if paired_mac(&link.macs, &headers).is_none() {
        return StatusCode::UNAUTHORIZED;
    }
    let Some(allow) = serde_json::from_str::<Value>(&body)
        .ok()
        .and_then(|v| v["allow"].as_bool())
    else {
        return StatusCode::BAD_REQUEST;
    };
    let decision = if allow {
        Decision::Allow
    } else {
        Decision::Deny
    };
    if link.host.answer_waiting(&mac_id, decision) {
        StatusCode::NO_CONTENT
    } else {
        StatusCode::NOT_FOUND
    }
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
            remember(
                &link.macs,
                &ask.mac_id,
                &ask.mac_name,
                &token,
                sunshine_client,
            );
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

/// Discovers connected outputs and current active output for the paired Mac.
async fn get_outputs<S, P, A>(
    State(link): State<Arc<Link<S, P, A>>>,
    headers: HeaderMap,
) -> Result<(StatusCode, Json<OutputsPayload>), StatusCode>
where
    S: SunshineApi + 'static,
    P: Prompt + 'static,
    A: Awake + 'static,
{
    if paired_mac(&link.macs, &headers).is_none() {
        return Err(StatusCode::UNAUTHORIZED);
    }
    let config_dir = link.config_dir();
    let payload = discover_host_outputs(&config_dir);
    Ok((StatusCode::OK, Json(payload)))
}

/// Selects an output device and optionally configures its display mode.
async fn select_output<S, P, A>(
    State(link): State<Arc<Link<S, P, A>>>,
    headers: HeaderMap,
    Json(request): Json<SelectOutputRequest>,
) -> StatusCode
where
    S: SunshineApi + 'static,
    P: Prompt + 'static,
    A: Awake + 'static,
{
    if paired_mac(&link.macs, &headers).is_none() {
        return StatusCode::UNAUTHORIZED;
    }

    let config_dir = link.config_dir();
    let payload = discover_host_outputs(&config_dir);

    let (target_connector, matched_output) = if request.id == crate::outputs::VIRTUAL_ID
        || request.id == crate::virtual_screen::OUTPUT
    {
        (crate::virtual_screen::OUTPUT.to_string(), None)
    } else if let Some(found) = payload
        .outputs
        .iter()
        .find(|o| o.id == request.id || o.connector == request.id)
    {
        if found.is_virtual {
            (
                crate::virtual_screen::OUTPUT.to_string(),
                Some(found.clone()),
            )
        } else {
            (found.connector.clone(), Some(found.clone()))
        }
    } else {
        return StatusCode::BAD_REQUEST;
    };

    if let Some(ref mode) = request.mode {
        if mode.width == 0 || mode.height == 0 {
            return StatusCode::BAD_REQUEST;
        }
        if let Some(ref out) = matched_output {
            let is_unsupported_mode = !out.modes.is_empty()
                && !out
                    .modes
                    .iter()
                    .any(|m| m.width == mode.width && m.height == mode.height);
            if is_unsupported_mode {
                return StatusCode::BAD_REQUEST;
            }
        }
    }

    let stream_output_path = config_dir.join("stream-output");
    if let Err(e) = std::fs::write(&stream_output_path, format!("{target_connector}\n")) {
        eprintln!("select_output: could not write stream-output: {e}");
        return StatusCode::INTERNAL_SERVER_ERROR;
    }

    if let Some(sunshine_conf_path) = find_sunshine_conf(&config_dir) {
        let before = std::fs::read_to_string(&sunshine_conf_path).unwrap_or_default();
        let after = crate::virtual_screen::with_setting(&before, "output_name", &target_connector);
        if let Some(parent) = sunshine_conf_path.parent() {
            let _ = std::fs::create_dir_all(parent);
        }
        if let Err(e) = std::fs::write(&sunshine_conf_path, after) {
            eprintln!("select_output: could not write sunshine.conf: {e}");
        }
    }

    if !is_stream_live(&config_dir) {
        let _ = tokio::task::spawn_blocking(restart_sunshine).await;
        wait_for_sunshine_ready(link.host.sunshine()).await;
    }

    if let Some(ref mode) = request.mode {
        apply_output_mode(&target_connector, mode);
    }

    StatusCode::OK
}

fn discover_host_outputs(config_dir: &FsPath) -> OutputsPayload {
    let kscreen_fixture = config_dir.join("kscreen.json");
    if let Ok(json_str) = std::fs::read_to_string(&kscreen_fixture) {
        let active_connector = std::fs::read_to_string(config_dir.join("stream-output")).ok();
        if let Ok(payload) =
            crate::outputs::parse_kscreen_outputs(&json_str, active_connector.as_deref())
        {
            return payload;
        }
    }

    #[cfg(target_os = "linux")]
    {
        crate::os::linux::discover_outputs(config_dir)
            .unwrap_or_else(|_| default_outputs_payload(config_dir))
    }

    #[cfg(not(target_os = "linux"))]
    {
        default_outputs_payload(config_dir)
    }
}

fn default_outputs_payload(config_dir: &FsPath) -> OutputsPayload {
    let active_connector = std::fs::read_to_string(config_dir.join("stream-output")).ok();
    let outputs = vec![crate::outputs::default_virtual_output()];
    let active_id = crate::outputs::resolve_active_id(active_connector.as_deref(), &outputs);
    OutputsPayload { active_id, outputs }
}

fn find_sunshine_conf(config_dir: &FsPath) -> Option<PathBuf> {
    let test_path = config_dir.join("sunshine.conf");
    if test_path.exists() {
        return Some(test_path);
    }
    if let Some(custom) = std::env::var_os("EVENT_HORIZON_SUNSHINE_CONF") {
        let p = PathBuf::from(custom);
        if p.exists() || p.parent().is_some_and(|parent| parent.is_dir()) {
            return Some(p);
        }
    }
    if let Some(home) = std::env::var_os("HOME").map(PathBuf::from) {
        let flatpak_conf =
            home.join(".var/app/dev.lizardbyte.app.Sunshine/config/sunshine/sunshine.conf");
        if flatpak_conf.exists() || flatpak_conf.parent().is_some_and(|parent| parent.is_dir()) {
            return Some(flatpak_conf);
        }
        let native_conf = home.join(".config/sunshine/sunshine.conf");
        if native_conf.exists() || native_conf.parent().is_some_and(|parent| parent.is_dir()) {
            return Some(native_conf);
        }
    }
    Some(test_path)
}

fn is_stream_live(config_dir: &FsPath) -> bool {
    let recovery = std::fs::read_to_string(config_dir.join("stream-screen-recovery-required"))
        .unwrap_or_default();
    if !recovery.trim().is_empty() {
        return false;
    }
    let saved =
        std::fs::read_to_string(config_dir.join("stream-screen-outputs")).unwrap_or_default();
    if !saved.trim().is_empty() {
        return true;
    }
    let target_state =
        std::fs::read_to_string(config_dir.join("stream-screen-target-state")).unwrap_or_default();
    !target_state.trim().is_empty()
}

async fn wait_for_sunshine_ready<S: SunshineApi>(sunshine: &S) {
    for _ in 0..50 {
        if sunshine.apps().await.is_ok() {
            return;
        }
        tokio::time::sleep(std::time::Duration::from_millis(150)).await;
    }
}

fn restart_sunshine() {
    #[cfg(target_os = "linux")]
    {
        let primary = std::process::Command::new("systemctl")
            .args([
                "--user",
                "restart",
                "app-dev.lizardbyte.app.Sunshine.service",
            ])
            .status()
            .map(|s| s.success())
            .unwrap_or(false);
        if !primary {
            let _ = std::process::Command::new("systemctl")
                .args(["--user", "restart", "dev.lizardbyte.app.Sunshine.service"])
                .status();
        }
    }
}

fn apply_output_mode(connector: &str, mode: &DisplayMode) {
    #[cfg(target_os = "linux")]
    {
        let mode_arg = if let Ok(output) = std::process::Command::new("kscreen-doctor")
            .arg("--json")
            .output()
        {
            if let Ok(json) = serde_json::from_slice::<Value>(&output.stdout) {
                find_mode_id_or_string(&json, connector, mode)
            } else {
                format!("output.{connector}.mode.{}x{}", mode.width, mode.height)
            }
        } else {
            format!("output.{connector}.mode.{}x{}", mode.width, mode.height)
        };

        let _ = std::process::Command::new("kscreen-doctor")
            .arg(&mode_arg)
            .status();
    }
    #[cfg(not(target_os = "linux"))]
    {
        let _ = (connector, mode);
    }
}

#[cfg(target_os = "linux")]
fn find_mode_id_or_string(json: &Value, connector: &str, mode: &DisplayMode) -> String {
    if let Some(outputs) = json.get("outputs").and_then(Value::as_array)
        && let Some(output) = outputs
            .iter()
            .find(|o| o.get("name").and_then(Value::as_str) == Some(connector))
        && let Some(modes) = output.get("modes").and_then(Value::as_array)
    {
        for m in modes {
            let w = m
                .get("size")
                .and_then(|s| s.get("width"))
                .and_then(Value::as_u64)
                .or_else(|| m.get("width").and_then(Value::as_u64))
                .unwrap_or(0) as u32;
            let h = m
                .get("size")
                .and_then(|s| s.get("height"))
                .and_then(Value::as_u64)
                .or_else(|| m.get("height").and_then(Value::as_u64))
                .unwrap_or(0) as u32;
            let r = m
                .get("refreshRate")
                .and_then(Value::as_f64)
                .or_else(|| m.get("refresh_rate").and_then(Value::as_f64))
                .unwrap_or(60.0);
            if w == mode.width
                && h == mode.height
                && (r - mode.refresh).abs() < 1.0
                && let Some(id) = m.get("id").and_then(Value::as_str)
            {
                return format!("output.{connector}.mode.{id}");
            }
        }
    }
    format!("output.{connector}.mode.{}x{}", mode.width, mode.height)
}

/// The Mac removes its own pairing: its record here, and its client in Sunshine.
/// If Sunshine cannot be reached, nothing is removed, so the Mac can try again.
async fn unpair<S, P, A>(State(link): State<Arc<Link<S, P, A>>>, headers: HeaderMap) -> StatusCode
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
    Json(json!({
        "app": "event-horizon-companion",
        "v": 2,
        "capabilities": ["outputs", "virtual_screen", "hdr", "dynamic_fps"],
        "commit": option_env!("GIT_COMMIT_HASH").unwrap_or("5fd8cc9"),
    }))
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
