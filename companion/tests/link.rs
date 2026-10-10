//! Link: how a Mac reaches the companion over the home network, on HTTPS with
//! the companion's own certificate. Every test client pins that certificate's
//! fingerprint, as the Mac does.

mod common;

use common::{FakeAwake, FakePrompt, FakeSunshine};
use event_horizon_companion::{Decision, Host, link, tls};
use rustls::client::danger::{HandshakeSignatureValid, ServerCertVerified, ServerCertVerifier};
use rustls::pki_types::{CertificateDer, ServerName, UnixTime};
use rustls::{DigitallySignedStruct, SignatureScheme};
use serde_json::{Value, json};
use std::path::Path;
use std::sync::Arc;
use std::time::Duration;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio_rustls::client::TlsStream;

struct Companion {
    /// `host:port` of the companion's Link on loopback.
    addr: String,
    fingerprint: String,
    awake: FakeAwake,
    sunshine: FakeSunshine,
}

/// A companion in `dir` (its certificate and `macs.json`), answering the
/// PC's prompt with `prompt` and serving on a free port.
async fn start_with(prompt: FakePrompt, sunshine: FakeSunshine, dir: &Path) -> Companion {
    let identity = tls::load_or_create(dir).unwrap();
    let awake = FakeAwake::default();
    let host = Host::new(sunshine.clone(), prompt, awake.clone());
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap().to_string();
    tokio::spawn(link::serve(
        listener,
        identity.acceptor,
        host,
        dir.join("macs.json"),
    ));
    Companion {
        addr,
        fingerprint: identity.fingerprint,
        awake,
        sunshine,
    }
}

async fn start(answer: Decision, dir: &Path) -> Companion {
    let prompt = FakePrompt::after(Some(answer), Duration::ZERO);
    start_with(prompt, FakeSunshine::default(), dir).await
}

/// Accepts the server certificate only when its SHA-256 matches the pin; the
/// handshake signature is checked as usual.
#[derive(Debug)]
struct Pinned {
    fingerprint: String,
    provider: Arc<rustls::crypto::CryptoProvider>,
}

impl ServerCertVerifier for Pinned {
    fn verify_server_cert(
        &self,
        end_entity: &CertificateDer<'_>,
        _intermediates: &[CertificateDer<'_>],
        _server_name: &ServerName<'_>,
        _ocsp: &[u8],
        _now: UnixTime,
    ) -> Result<ServerCertVerified, rustls::Error> {
        if tls::fingerprint(end_entity) == self.fingerprint {
            Ok(ServerCertVerified::assertion())
        } else {
            Err(rustls::Error::General("certificate is not the pinned one".into()))
        }
    }

    fn verify_tls12_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        dss: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, rustls::Error> {
        rustls::crypto::verify_tls12_signature(
            message,
            cert,
            dss,
            &self.provider.signature_verification_algorithms,
        )
    }

    fn verify_tls13_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        dss: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, rustls::Error> {
        rustls::crypto::verify_tls13_signature(
            message,
            cert,
            dss,
            &self.provider.signature_verification_algorithms,
        )
    }

    fn supported_verify_schemes(&self) -> Vec<SignatureScheme> {
        self.provider.signature_verification_algorithms.supported_schemes()
    }
}

/// A TLS connection to `addr` that accepts only the certificate with `fingerprint`.
async fn connect(addr: &str, fingerprint: &str) -> std::io::Result<TlsStream<tokio::net::TcpStream>> {
    let provider = Arc::new(tls::provider());
    let config = rustls::ClientConfig::builder_with_provider(provider.clone())
        .with_protocol_versions(&[&rustls::version::TLS13, &rustls::version::TLS12])
        .unwrap()
        .dangerous()
        .with_custom_certificate_verifier(Arc::new(Pinned {
            fingerprint: fingerprint.to_string(),
            provider,
        }))
        .with_no_client_auth();
    let connector = tokio_rustls::TlsConnector::from(Arc::new(config));
    let tcp = tokio::net::TcpStream::connect(addr).await?;
    connector
        .connect(ServerName::try_from("localhost").unwrap(), tcp)
        .await
}

/// One HTTP/1.1 request to the companion over a pinned TLS connection. Returns
/// the status and the JSON body (null when there is none).
async fn send(
    to: &Companion,
    method: &str,
    path: &str,
    token: Option<&str>,
    body: Option<Value>,
) -> (u16, Value) {
    let mut stream = connect(&to.addr, &to.fingerprint).await.unwrap();
    let payload = body.map(|b| b.to_string()).unwrap_or_default();
    let mut head = format!(
        "{method} {path} HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\nContent-Length: {}\r\n",
        payload.len()
    );
    if !payload.is_empty() {
        head.push_str("Content-Type: application/json\r\n");
    }
    if let Some(token) = token {
        head.push_str(&format!("Authorization: Bearer {token}\r\n"));
    }
    head.push_str("\r\n");
    stream.write_all(head.as_bytes()).await.unwrap();
    stream.write_all(payload.as_bytes()).await.unwrap();
    let mut reply = Vec::new();
    // The companion closes without a TLS close_notify; the reply is complete anyway.
    let _ = stream.read_to_end(&mut reply).await;
    let text = String::from_utf8_lossy(&reply).to_string();
    let (head, body) = text.split_once("\r\n\r\n").unwrap_or((text.as_str(), ""));
    let status = head.split_whitespace().nth(1).unwrap().parse().unwrap();
    let json = serde_json::from_str(body).unwrap_or(Value::Null);
    (status, json)
}

/// Step one: the Mac asks. Returns the PC's answer (status and body).
async fn ask(to: &Companion, mac_id: &str, pin: Option<&str>) -> (u16, Value) {
    let mut body = json!({ "mac_id": mac_id, "mac_name": "Raptor" });
    if let Some(pin) = pin {
        body["pin"] = json!(pin);
    }
    send(to, "POST", "/pair", None, Some(body)).await
}

/// Step two: the Mac waits for the person at the PC.
async fn answer(to: &Companion, ticket: &str) -> (u16, Value) {
    send(to, "GET", &format!("/pair/{ticket}"), None, None).await
}

/// Both steps for one Mac with a Sunshine PIN.
async fn pair(to: &Companion) -> (u16, Value) {
    let (status, asked) = ask(to, "mac-1", Some("4821")).await;
    assert_eq!(status, 200);
    answer(to, asked["ticket"].as_str().unwrap()).await
}

async fn lease(to: &Companion, token: Option<&str>) -> u16 {
    send(to, "POST", "/lease", token, None).await.0
}

async fn unpair(to: &Companion, token: Option<&str>) -> u16 {
    send(to, "DELETE", "/pair", token, None).await.0
}

#[tokio::test]
async fn allow_gives_the_mac_a_token_that_keeps_the_pc_awake() {
    let dir = tempfile::tempdir().unwrap();
    let companion = start(Decision::Allow, dir.path()).await;

    let (status, body) = pair(&companion).await;
    assert_eq!(status, 200);
    assert_eq!(body["outcome"], "paired");
    let token = body["token"].as_str().expect("a token on Allow");
    assert!(token.len() >= 32);

    assert_eq!(lease(&companion, Some(token)).await, 204);
    assert_eq!(companion.awake.held(), 1);
}

#[tokio::test]
async fn the_pc_shows_a_six_digit_code_and_the_mac_is_given_the_same_one() {
    let dir = tempfile::tempdir().unwrap();
    let prompt = FakePrompt::after(Some(Decision::Allow), Duration::ZERO);
    let companion = start_with(prompt.clone(), FakeSunshine::default(), dir.path()).await;

    let (status, asked) = ask(&companion, "mac-1", Some("4821")).await;

    assert_eq!(status, 200);
    let code = asked["code"].as_str().unwrap();
    assert_eq!(code.len(), 6);
    assert!(code.bytes().all(|b| b.is_ascii_digit()));
    assert_eq!(*prompt.codes.lock().unwrap(), vec![code.to_string()]);
}

#[tokio::test]
async fn an_unknown_ticket_is_not_found() {
    let dir = tempfile::tempdir().unwrap();
    let companion = start(Decision::Allow, dir.path()).await;

    let (status, body) = answer(&companion, "no-such-ticket").await;

    assert_eq!(status, 404);
    assert_eq!(body["outcome"], "unknown");
}

#[tokio::test]
async fn a_second_request_from_the_same_mac_replaces_the_first_at_the_link() {
    let dir = tempfile::tempdir().unwrap();
    let nobody = FakePrompt::after(None, Duration::ZERO);
    let companion = start_with(nobody, FakeSunshine::default(), dir.path()).await;

    let (_, first) = ask(&companion, "mac-1", Some("1111")).await;
    let (_, _second) = ask(&companion, "mac-1", Some("2222")).await;
    let (status, body) = answer(&companion, first["ticket"].as_str().unwrap()).await;

    assert_eq!(status, 409);
    assert_eq!(body["outcome"], "replaced");
}

#[tokio::test]
async fn a_lease_without_a_valid_token_is_refused() {
    let dir = tempfile::tempdir().unwrap();
    let companion = start(Decision::Allow, dir.path()).await;

    assert_eq!(lease(&companion, None).await, 401);
    assert_eq!(lease(&companion, Some("not-a-token")).await, 401);
    assert_eq!(companion.awake.held(), 0);
}

#[tokio::test]
async fn deny_gives_no_token() {
    let dir = tempfile::tempdir().unwrap();
    let companion = start(Decision::Deny, dir.path()).await;

    let (status, body) = pair(&companion).await;
    assert_eq!(status, 403);
    assert_eq!(body["outcome"], "denied");
    assert!(body.get("token").is_none());
}

#[tokio::test]
async fn a_paired_mac_stays_paired_after_the_companion_restarts() {
    let dir = tempfile::tempdir().unwrap();
    let first = start(Decision::Allow, dir.path()).await;
    let (_, body) = pair(&first).await;
    let token = body["token"].as_str().unwrap().to_string();

    let second = start(Decision::Allow, dir.path()).await;

    assert_eq!(lease(&second, Some(&token)).await, 204);
    assert_eq!(second.awake.held(), 1);
}

#[tokio::test]
async fn the_companion_keeps_one_certificate_across_restarts() {
    let dir = tempfile::tempdir().unwrap();
    let first = start(Decision::Allow, dir.path()).await;
    let second = start(Decision::Allow, dir.path()).await;

    assert_eq!(first.fingerprint, second.fingerprint);
    assert_eq!(first.fingerprint.len(), 64);
}

#[tokio::test]
async fn hello_tells_a_mac_this_pc_runs_the_companion() {
    let dir = tempfile::tempdir().unwrap();
    let companion = start(Decision::Allow, dir.path()).await;

    let (status, body) = send(&companion, "GET", "/hello", None, None).await;

    assert_eq!(status, 200);
    assert_eq!(body["app"], "event-horizon-companion");
    assert_eq!(body["v"], 1);
}

#[tokio::test]
async fn unpair_forgets_the_mac_here_and_in_sunshine() {
    let dir = tempfile::tempdir().unwrap();
    let companion = start(Decision::Allow, dir.path()).await;
    let (_, body) = pair(&companion).await;
    let token = body["token"].as_str().unwrap().to_string();

    assert_eq!(unpair(&companion, Some(&token)).await, 204);

    assert_eq!(lease(&companion, Some(&token)).await, 401);
    assert_eq!(*companion.sunshine.unpaired.lock().unwrap(), ["uuid-mac-1"]);
    assert!(link::list(&dir.path().join("macs.json")).is_empty());
}

#[tokio::test]
async fn pairing_again_leaves_sunshine_one_record_for_the_mac() {
    let dir = tempfile::tempdir().unwrap();
    let companion = start(Decision::Allow, dir.path()).await;
    pair(&companion).await;

    let (status, body) = pair(&companion).await;

    // Sunshine refuses a certificate that more than one record holds, so the
    // first pairing's record goes as the second one arrives.
    assert_eq!(status, 200);
    assert_eq!(*companion.sunshine.unpaired.lock().unwrap(), ["uuid-mac-1"]);
    // Unpairing later removes the record that is left, and nothing else.
    let token = body["token"].as_str().unwrap().to_string();
    assert_eq!(unpair(&companion, Some(&token)).await, 204);
    assert_eq!(*companion.sunshine.unpaired.lock().unwrap(), ["uuid-mac-1", "uuid-mac-1-2"]);
}

#[tokio::test]
async fn unpair_needs_the_macs_own_token() {
    let dir = tempfile::tempdir().unwrap();
    let companion = start(Decision::Allow, dir.path()).await;
    pair(&companion).await;

    assert_eq!(unpair(&companion, None).await, 401);
    assert_eq!(unpair(&companion, Some("not-a-token")).await, 401);
    assert_eq!(link::list(&dir.path().join("macs.json")).len(), 1);
    assert!(companion.sunshine.unpaired.lock().unwrap().is_empty());
}

#[tokio::test]
async fn unpair_keeps_the_pairing_when_sunshine_cannot_be_reached() {
    let dir = tempfile::tempdir().unwrap();
    let companion = start(Decision::Allow, dir.path()).await;
    let (_, body) = pair(&companion).await;
    let token = body["token"].as_str().unwrap().to_string();

    companion.sunshine.go_down();

    assert_eq!(unpair(&companion, Some(&token)).await, 502);
    assert_eq!(lease(&companion, Some(&token)).await, 204);
    assert_eq!(link::list(&dir.path().join("macs.json")).len(), 1);
}

#[tokio::test]
async fn a_mac_paired_only_for_the_link_is_forgotten_without_touching_sunshine() {
    let dir = tempfile::tempdir().unwrap();
    let companion = start(Decision::Allow, dir.path()).await;
    let (_, asked) = ask(&companion, "mac-1", None).await;
    let (_, body) = answer(&companion, asked["ticket"].as_str().unwrap()).await;
    let token = body["token"].as_str().unwrap().to_string();

    assert_eq!(unpair(&companion, Some(&token)).await, 204);
    assert!(companion.sunshine.unpaired.lock().unwrap().is_empty());
}

#[tokio::test]
async fn a_mac_that_pins_the_advertised_fingerprint_connects_and_another_does_not() {
    let dir = tempfile::tempdir().unwrap();
    let companion = start(Decision::Allow, dir.path()).await;

    let (status, _) = send(&companion, "GET", "/hello", None, None).await;
    assert_eq!(status, 200);

    let other = "00".repeat(32);
    assert!(connect(&companion.addr, &other).await.is_err());
}

#[tokio::test]
async fn the_companion_keeps_one_certificate_on_disk() {
    let dir = tempfile::tempdir().unwrap();
    let companion = start(Decision::Allow, dir.path()).await;

    let der = std::fs::read(dir.path().join("companion-cert.der")).unwrap();
    assert_eq!(tls::fingerprint(&der), companion.fingerprint);
}
