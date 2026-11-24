//! Tests for host audio output parsing, PipeWire/PulseAudio noise filtering,
//! virtual sink branding, and Link `/audio` + `/audio/select` endpoints.

mod common;

use common::{FakeAwake, FakePrompt, FakeSunshine};
use event_horizon_companion::audio::{
    AudioPayload, HostAudioDevice, SelectAudioRequest, VIRTUAL_SINK_NAME, empty_audio_payload,
    parse_pactl_sinks, parse_sink_input_ids,
};
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

const SAMPLE_PACTL_SINKS: &str = r#"
Sink #42
	State: SUSPENDED
	Name: alsa_output.usb-SteelSeries_Arctis_Nova_Pro_Wireless-00.analog-stereo
	Description: Arctis Nova Pro Wireless
	Driver: PipeWire
	Sample Specification: s16le 2ch 48000Hz
	Monitor Source: alsa_output.usb-SteelSeries_Arctis_Nova_Pro_Wireless-00.analog-stereo.monitor
	Properties:
		node.name = "alsa_output.usb-SteelSeries_Arctis_Nova_Pro_Wireless-00.analog-stereo"
		device.description = "Arctis Nova Pro Wireless"

Sink #43
	State: SUSPENDED
	Name: alsa_output.usb-SteelSeries_Arctis_Nova_Pro_Wireless-00.analog-stereo.monitor
	Description: Monitor of Arctis Nova Pro Wireless
	Driver: PipeWire

Sink #44
	State: IDLE
	Name: sink-sunshine-stereo
	Description: Sunshine Stereo
	Driver: PipeWire
	Properties:
		node.name = "sink-sunshine-stereo"
		node.description = "Sunshine Stereo"

Sink #45
	State: SUSPENDED
	Name: alsa_output.pci-0000_0c_00.4.iec958-stereo
	Description: Starship/Matisse HD Audio Controller Digital Stereo
	Driver: PipeWire

Sink #46
	State: SUSPENDED
	Name: auto_null
	Description: Dummy Output
	Driver: PipeWire

Sink #47
	State: SUSPENDED
	Name: speech-dispatcher-dummy
	Description: Speech Dispatcher
	Driver: PipeWire
"#;

#[test]
fn parses_sinks_brands_virtual_and_filters_noise() {
    let payload = parse_pactl_sinks(SAMPLE_PACTL_SINKS, "sink-sunshine-stereo\n");

    assert_eq!(payload.active_id, "sink-sunshine-stereo");
    assert_eq!(payload.devices.len(), 3);

    // Virtual sink is placed first and branded as Event Horizon Audio.
    assert_eq!(
        payload.devices[0],
        HostAudioDevice {
            id: "sink-sunshine-stereo".to_string(),
            name: VIRTUAL_SINK_NAME.to_string(),
            is_virtual: true,
            is_default: true,
        }
    );
    assert_eq!(
        payload.devices[1],
        HostAudioDevice {
            id: "alsa_output.usb-SteelSeries_Arctis_Nova_Pro_Wireless-00.analog-stereo".to_string(),
            name: "Arctis Nova Pro Wireless".to_string(),
            is_virtual: false,
            is_default: false,
        }
    );
    assert_eq!(
        payload.devices[2],
        HostAudioDevice {
            id: "alsa_output.pci-0000_0c_00.4.iec958-stereo".to_string(),
            name: "Starship/Matisse HD Audio Controller Digital Stereo".to_string(),
            is_virtual: false,
            is_default: false,
        }
    );
}

#[test]
fn hardware_default_sink_marks_hardware_active() {
    let hw_id = "alsa_output.usb-SteelSeries_Arctis_Nova_Pro_Wireless-00.analog-stereo";
    let payload = parse_pactl_sinks(SAMPLE_PACTL_SINKS, hw_id);

    assert_eq!(payload.active_id, hw_id);
    assert!(!payload.devices[0].is_default);
    assert!(payload.devices[1].is_default);
    assert!(!payload.devices[2].is_default);
}

#[test]
fn event_horizon_named_sink_is_branded_as_virtual() {
    let sinks = r#"
Sink #10
	Name: event-horizon-audio
	Description: Custom Virtual Sink
"#;
    let payload = parse_pactl_sinks(sinks, "event-horizon-audio");
    assert_eq!(payload.devices.len(), 1);
    assert!(payload.devices[0].is_virtual);
    assert_eq!(payload.devices[0].name, "Event Horizon Audio");
    assert!(payload.devices[0].is_default);
}

#[test]
fn missing_or_empty_pactl_returns_empty_payload() {
    let payload = parse_pactl_sinks("", "");
    assert_eq!(payload, empty_audio_payload());
    assert!(payload.active_id.is_empty());
    assert!(payload.devices.is_empty());
}

#[test]
fn fallback_active_id_when_default_sink_is_filtered_or_missing() {
    let payload = parse_pactl_sinks(SAMPLE_PACTL_SINKS, "auto_null");
    assert_eq!(payload.active_id, "sink-sunshine-stereo");
}

#[test]
fn parses_sink_input_ids_from_short_output() {
    let short = "412\t44\tPipeWire\tfloat32le 2ch 48000Hz\tRUNNING\n\n519\t44\tprotocol-native.c\ts16le 2ch 44100Hz\tCORKED\nbad-line\n";
    let ids = parse_sink_input_ids(short);
    assert_eq!(ids, vec!["412", "519"]);
}

#[test]
fn serde_round_trip_for_audio_models() {
    let payload = AudioPayload {
        active_id: "sink-sunshine-stereo".to_string(),
        devices: vec![HostAudioDevice {
            id: "sink-sunshine-stereo".to_string(),
            name: "Event Horizon Audio".to_string(),
            is_virtual: true,
            is_default: true,
        }],
    };
    let json = serde_json::to_string(&payload).unwrap();
    let decoded: AudioPayload = serde_json::from_str(&json).unwrap();
    assert_eq!(decoded, payload);

    let req = SelectAudioRequest {
        id: "sink-sunshine-stereo".to_string(),
    };
    let req_json = serde_json::to_string(&req).unwrap();
    let decoded_req: SelectAudioRequest = serde_json::from_str(&req_json).unwrap();
    assert_eq!(decoded_req, req);
}

// ---------------------------------------------------------------------------
// Link HTTPS Endpoint Integration Tests
// ---------------------------------------------------------------------------

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
            Err(rustls::Error::General("certificate mismatch".into()))
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
        self.provider
            .signature_verification_algorithms
            .supported_schemes()
    }
}

async fn start_companion(dir: &Path) -> (String, String) {
    let identity = tls::load_or_create(dir).unwrap();
    let host = Host::new(
        FakeSunshine::default(),
        FakePrompt::after(Some(Decision::Allow), Duration::ZERO),
        FakeAwake::default(),
    );
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap().to_string();
    tokio::spawn(link::serve(
        listener,
        identity.acceptor,
        host,
        dir.join("macs.json"),
    ));
    (addr, identity.fingerprint)
}

fn test_crypto_provider() -> rustls::crypto::CryptoProvider {
    #[cfg(target_os = "linux")]
    {
        rustls::crypto::aws_lc_rs::default_provider()
    }
    #[cfg(not(target_os = "linux"))]
    {
        rustls::crypto::ring::default_provider()
    }
}

async fn connect_tls(addr: &str, fingerprint: &str) -> TlsStream<tokio::net::TcpStream> {
    let _ = test_crypto_provider().install_default();
    let provider = Arc::new(test_crypto_provider());
    let config = rustls::ClientConfig::builder_with_provider(provider.clone())
        .with_safe_default_protocol_versions()
        .unwrap()
        .dangerous()
        .with_custom_certificate_verifier(Arc::new(Pinned {
            fingerprint: fingerprint.to_string(),
            provider,
        }))
        .with_no_client_auth();
    let connector = tokio_rustls::TlsConnector::from(Arc::new(config));
    let stream = tokio::net::TcpStream::connect(addr).await.unwrap();
    let server_name = ServerName::try_from("localhost").unwrap();
    connector.connect(server_name, stream).await.unwrap()
}

async fn http_request(
    addr: &str,
    fingerprint: &str,
    method: &str,
    path: &str,
    token: Option<&str>,
    body: Option<&str>,
) -> (u16, String) {
    let mut tls = connect_tls(addr, fingerprint).await;
    let body_str = body.unwrap_or("");
    let auth_header = token
        .map(|t| format!("Authorization: Bearer {t}\r\n"))
        .unwrap_or_default();
    let content_headers = if body.is_some() {
        format!(
            "Content-Type: application/json\r\nContent-Length: {}\r\n",
            body_str.len()
        )
    } else {
        String::new()
    };
    let req = format!(
        "{method} {path} HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n{auth_header}{content_headers}\r\n{body_str}"
    );
    tls.write_all(req.as_bytes()).await.unwrap();
    tls.flush().await.unwrap();

    let mut buf = Vec::new();
    let mut chunk = [0u8; 4096];
    loop {
        match tls.read(&mut chunk).await {
            Ok(0) => break,
            Ok(n) => buf.extend_from_slice(&chunk[..n]),
            Err(e) if e.kind() == std::io::ErrorKind::UnexpectedEof && !buf.is_empty() => break,
            Err(e) => panic!("read failed: {e}"),
        }
    }
    let response = String::from_utf8(buf).unwrap();
    let (head, resp_body) = response.split_once("\r\n\r\n").unwrap_or((&response, ""));
    let status = head
        .lines()
        .next()
        .and_then(|l| l.split_whitespace().nth(1))
        .and_then(|s| s.parse::<u16>().ok())
        .unwrap_or(0);
    (status, resp_body.to_string())
}

async fn pair_test_mac(addr: &str, fingerprint: &str) -> String {
    let ask_body = json!({ "mac_id": "mac-audio-test", "mac_name": "Test Mac" }).to_string();
    let (status, body) =
        http_request(addr, fingerprint, "POST", "/pair", None, Some(&ask_body)).await;
    assert_eq!(status, 200);
    let ticket = serde_json::from_str::<Value>(&body).unwrap()["ticket"]
        .as_str()
        .unwrap()
        .to_string();
    let (status, body) = http_request(
        addr,
        fingerprint,
        "GET",
        &format!("/pair/{ticket}"),
        None,
        None,
    )
    .await;
    assert_eq!(status, 200);
    serde_json::from_str::<Value>(&body).unwrap()["token"]
        .as_str()
        .unwrap()
        .to_string()
}

#[tokio::test]
async fn hello_advertises_audio_capability() {
    let dir = tempfile::tempdir().unwrap();
    let (addr, fp) = start_companion(dir.path()).await;
    let (status, body) = http_request(&addr, &fp, "GET", "/hello", None, None).await;
    assert_eq!(status, 200);
    let json: Value = serde_json::from_str(&body).unwrap();
    let caps = json["capabilities"].as_array().unwrap();
    assert!(caps.iter().any(|c| c.as_str() == Some("audio")));
}

#[tokio::test]
async fn audio_endpoints_require_bearer_auth_and_switch_fixture_sink() {
    let dir = tempfile::tempdir().unwrap();
    std::fs::write(dir.path().join("pactl-sinks.txt"), SAMPLE_PACTL_SINKS).unwrap();
    std::fs::write(
        dir.path().join("pactl-default-sink.txt"),
        "sink-sunshine-stereo\n",
    )
    .unwrap();
    std::fs::write(dir.path().join("sunshine.conf"), "output_name = DP-1\n").unwrap();

    let (addr, fp) = start_companion(dir.path()).await;

    // Unauthorized without token
    let (status, _) = http_request(&addr, &fp, "GET", "/audio", None, None).await;
    assert_eq!(status, 401);
    let (status, _) = http_request(
        &addr,
        &fp,
        "POST",
        "/audio/select",
        None,
        Some(r#"{"id":"sink-sunshine-stereo"}"#),
    )
    .await;
    assert_eq!(status, 401);

    let token = pair_test_mac(&addr, &fp).await;

    // GET /audio returns parsed devices
    let (status, body) = http_request(&addr, &fp, "GET", "/audio", Some(&token), None).await;
    assert_eq!(status, 200);
    let payload: AudioPayload = serde_json::from_str(&body).unwrap();
    assert_eq!(payload.active_id, "sink-sunshine-stereo");
    assert_eq!(payload.devices.len(), 3);
    assert_eq!(payload.devices[0].name, "Event Horizon Audio");

    // Empty id returns 400
    let (status, _) = http_request(
        &addr,
        &fp,
        "POST",
        "/audio/select",
        Some(&token),
        Some(r#"{"id":"   "}"#),
    )
    .await;
    assert_eq!(status, 400);

    // POST /audio/select switches active sink & updates sunshine.conf
    let hw_id = "alsa_output.usb-SteelSeries_Arctis_Nova_Pro_Wireless-00.analog-stereo";
    let select_body = json!({ "id": hw_id }).to_string();
    let (status, _) = http_request(
        &addr,
        &fp,
        "POST",
        "/audio/select",
        Some(&token),
        Some(&select_body),
    )
    .await;
    assert_eq!(status, 200);

    let conf = std::fs::read_to_string(dir.path().join("sunshine.conf")).unwrap();
    assert!(conf.contains(&format!("audio_sink = {hw_id}")));

    // Subsequent GET /audio reflects the new active sink
    let (status, body) = http_request(&addr, &fp, "GET", "/audio", Some(&token), None).await;
    assert_eq!(status, 200);
    let updated: AudioPayload = serde_json::from_str(&body).unwrap();
    assert_eq!(updated.active_id, hw_id);
}
