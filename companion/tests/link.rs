//! Link: how a Mac reaches the companion over the home network, on HTTPS with
//! the companion's own certificate.

mod common;

use common::{FakeAwake, FakePrompt, FakeSunshine};
use event_horizon_companion::{Decision, Host, link, tls};
use rustls::client::danger::{HandshakeSignatureValid, ServerCertVerified, ServerCertVerifier};
use rustls::pki_types::{CertificateDer, ServerName, UnixTime};
use rustls::{DigitallySignedStruct, SignatureScheme};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::path::Path;
use std::sync::Arc;
use std::time::Duration;

struct Companion {
    base: String,
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
    let base = format!("https://{}", listener.local_addr().unwrap());
    tokio::spawn(link::serve(
        listener,
        identity.acceptor,
        host,
        dir.join("macs.json"),
    ));
    Companion {
        base,
        fingerprint: identity.fingerprint,
        awake,
        sunshine,
    }
}

async fn start(answer: Decision, dir: &Path) -> Companion {
    let prompt = FakePrompt::after(Some(answer), Duration::ZERO);
    start_with(prompt, FakeSunshine::default(), dir).await
}

/// The companion's certificate is self-signed, so the test client accepts it;
/// the fingerprint is checked separately, by `a_mac_that_pins_the_fingerprint...`.
fn client() -> reqwest::Client {
    reqwest::Client::builder()
        .danger_accept_invalid_certs(true)
        .build()
        .unwrap()
}

/// Step one: the Mac asks. Returns the PC's answer (status and body).
async fn ask(base: &str, mac_id: &str, pin: Option<&str>) -> (u16, Value) {
    let mut body = json!({ "mac_id": mac_id, "mac_name": "Raptor" });
    if let Some(pin) = pin {
        body["pin"] = json!(pin);
    }
    let response = client()
        .post(format!("{base}/pair"))
        .json(&body)
        .send()
        .await
        .unwrap();
    (response.status().as_u16(), response.json().await.unwrap())
}

/// Step two: the Mac waits for the person at the PC.
async fn answer(base: &str, ticket: &str) -> (u16, Value) {
    let response = client()
        .get(format!("{base}/pair/{ticket}"))
        .send()
        .await
        .unwrap();
    (response.status().as_u16(), response.json().await.unwrap())
}

/// Both steps for one Mac with a Sunshine PIN.
async fn pair(base: &str) -> (u16, Value) {
    let (status, asked) = ask(base, "mac-1", Some("4821")).await;
    assert_eq!(status, 200);
    answer(base, asked["ticket"].as_str().unwrap()).await
}

async fn lease(base: &str, token: Option<&str>) -> u16 {
    let mut request = client().post(format!("{base}/lease"));
    if let Some(token) = token {
        request = request.bearer_auth(token);
    }
    request.send().await.unwrap().status().as_u16()
}

async fn unpair(base: &str, token: Option<&str>) -> u16 {
    let mut request = client().delete(format!("{base}/pair"));
    if let Some(token) = token {
        request = request.bearer_auth(token);
    }
    request.send().await.unwrap().status().as_u16()
}

#[tokio::test]
async fn allow_gives_the_mac_a_token_that_keeps_the_pc_awake() {
    let dir = tempfile::tempdir().unwrap();
    let companion = start(Decision::Allow, dir.path()).await;

    let (status, body) = pair(&companion.base).await;
    assert_eq!(status, 200);
    assert_eq!(body["outcome"], "paired");
    let token = body["token"].as_str().expect("a token on Allow");
    assert!(token.len() >= 32);

    assert_eq!(lease(&companion.base, Some(token)).await, 204);
    assert_eq!(companion.awake.held(), 1);
}

#[tokio::test]
async fn the_pc_shows_a_six_digit_code_and_the_mac_is_given_the_same_one() {
    let dir = tempfile::tempdir().unwrap();
    let prompt = FakePrompt::after(Some(Decision::Allow), Duration::ZERO);
    let companion = start_with(prompt.clone(), FakeSunshine::default(), dir.path()).await;

    let (status, asked) = ask(&companion.base, "mac-1", Some("4821")).await;

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

    let (status, body) = answer(&companion.base, "no-such-ticket").await;

    assert_eq!(status, 404);
    assert_eq!(body["outcome"], "unknown");
}

#[tokio::test]
async fn a_second_request_from_the_same_mac_replaces_the_first_at_the_link() {
    let dir = tempfile::tempdir().unwrap();
    let nobody = FakePrompt::after(None, Duration::ZERO);
    let companion = start_with(nobody, FakeSunshine::default(), dir.path()).await;

    let (_, first) = ask(&companion.base, "mac-1", Some("1111")).await;
    let (_, _second) = ask(&companion.base, "mac-1", Some("2222")).await;
    let (status, body) = answer(&companion.base, first["ticket"].as_str().unwrap()).await;

    assert_eq!(status, 409);
    assert_eq!(body["outcome"], "replaced");
}

#[tokio::test]
async fn a_lease_without_a_valid_token_is_refused() {
    let dir = tempfile::tempdir().unwrap();
    let companion = start(Decision::Allow, dir.path()).await;

    assert_eq!(lease(&companion.base, None).await, 401);
    assert_eq!(lease(&companion.base, Some("not-a-token")).await, 401);
    assert_eq!(companion.awake.held(), 0);
}

#[tokio::test]
async fn deny_gives_no_token() {
    let dir = tempfile::tempdir().unwrap();
    let companion = start(Decision::Deny, dir.path()).await;

    let (status, body) = pair(&companion.base).await;
    assert_eq!(status, 403);
    assert_eq!(body["outcome"], "denied");
    assert!(body.get("token").is_none());
}

#[tokio::test]
async fn a_paired_mac_stays_paired_after_the_companion_restarts() {
    let dir = tempfile::tempdir().unwrap();
    let first = start(Decision::Allow, dir.path()).await;
    let (_, body) = pair(&first.base).await;
    let token = body["token"].as_str().unwrap().to_string();

    let second = start(Decision::Allow, dir.path()).await;

    assert_eq!(lease(&second.base, Some(&token)).await, 204);
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

    let body: Value = client()
        .get(format!("{}/hello", companion.base))
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();

    assert_eq!(body["app"], "event-horizon-companion");
    assert_eq!(body["v"], 1);
}

#[tokio::test]
async fn unpair_forgets_the_mac_here_and_in_sunshine() {
    let dir = tempfile::tempdir().unwrap();
    let companion = start(Decision::Allow, dir.path()).await;
    let (_, body) = pair(&companion.base).await;
    let token = body["token"].as_str().unwrap().to_string();

    assert_eq!(unpair(&companion.base, Some(&token)).await, 204);

    assert_eq!(lease(&companion.base, Some(&token)).await, 401);
    assert_eq!(*companion.sunshine.unpaired.lock().unwrap(), ["uuid-mac-1"]);
    assert!(link::list(&dir.path().join("macs.json")).is_empty());
}

#[tokio::test]
async fn unpair_needs_the_macs_own_token() {
    let dir = tempfile::tempdir().unwrap();
    let companion = start(Decision::Allow, dir.path()).await;
    pair(&companion.base).await;

    assert_eq!(unpair(&companion.base, None).await, 401);
    assert_eq!(unpair(&companion.base, Some("not-a-token")).await, 401);
    assert_eq!(link::list(&dir.path().join("macs.json")).len(), 1);
    assert!(companion.sunshine.unpaired.lock().unwrap().is_empty());
}

#[tokio::test]
async fn unpair_keeps_the_pairing_when_sunshine_cannot_be_reached() {
    let dir = tempfile::tempdir().unwrap();
    let companion = start(Decision::Allow, dir.path()).await;
    let (_, body) = pair(&companion.base).await;
    let token = body["token"].as_str().unwrap().to_string();

    companion.sunshine.go_down();

    assert_eq!(unpair(&companion.base, Some(&token)).await, 502);
    assert_eq!(lease(&companion.base, Some(&token)).await, 204);
    assert_eq!(link::list(&dir.path().join("macs.json")).len(), 1);
}

#[tokio::test]
async fn a_mac_paired_only_for_the_link_is_forgotten_without_touching_sunshine() {
    let dir = tempfile::tempdir().unwrap();
    let companion = start(Decision::Allow, dir.path()).await;
    let (_, asked) = ask(&companion.base, "mac-1", None).await;
    let (_, body) = answer(&companion.base, asked["ticket"].as_str().unwrap()).await;
    let token = body["token"].as_str().unwrap().to_string();

    assert_eq!(unpair(&companion.base, Some(&token)).await, 204);
    assert!(companion.sunshine.unpaired.lock().unwrap().is_empty());
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
        let seen: String = Sha256::digest(end_entity)
            .iter()
            .map(|b| format!("{b:02x}"))
            .collect();
        if seen == self.fingerprint {
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

/// GET /hello over TLS, pinned to `fingerprint`.
async fn hello_pinned(addr: &str, fingerprint: &str) -> Result<String, std::io::Error> {
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
    let mut stream = connector
        .connect(ServerName::try_from("localhost").unwrap(), tcp)
        .await?;
    use tokio::io::{AsyncReadExt, AsyncWriteExt};
    stream
        .write_all(b"GET /hello HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n")
        .await?;
    let mut reply = String::new();
    stream.read_to_string(&mut reply).await?;
    Ok(reply)
}

#[tokio::test]
async fn a_mac_that_pins_the_advertised_fingerprint_connects_and_another_does_not() {
    let dir = tempfile::tempdir().unwrap();
    let companion = start(Decision::Allow, dir.path()).await;
    let addr = companion.base.trim_start_matches("https://").to_string();

    let reply = hello_pinned(&addr, &companion.fingerprint).await.unwrap();
    assert!(reply.contains("event-horizon-companion"), "{reply}");

    let other = "00".repeat(32);
    assert!(hello_pinned(&addr, &other).await.is_err());
}
