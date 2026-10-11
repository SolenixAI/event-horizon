//! The companion trusts Sunshine only through the one certificate it pins.

use event_horizon_companion::sunshine_tls::{load_pinned_der, pinned_client};
use rustls::pki_types::{CertificateDer, PrivateKeyDer, PrivatePkcs8KeyDer};
use std::sync::Arc;
use tokio::io::{AsyncReadExt, AsyncWriteExt};

/// A self-signed certificate and its key, made the way Sunshine makes its own.
fn self_signed(name: &str) -> (CertificateDer<'static>, PrivatePkcs8KeyDer<'static>) {
    let made = rcgen::generate_simple_self_signed(vec![name.to_string()]).unwrap();
    let key = PrivatePkcs8KeyDer::from(made.signing_key.serialize_der());
    (made.cert.der().clone(), key)
}

/// Serves one fixed answer over TLS on a loopback port, and returns the port.
async fn serve(cert: CertificateDer<'static>, key: PrivatePkcs8KeyDer<'static>) -> u16 {
    let provider = Arc::new(event_horizon_companion::tls::provider());
    let config = rustls::ServerConfig::builder_with_provider(provider)
        .with_safe_default_protocol_versions()
        .unwrap()
        .with_no_client_auth()
        .with_single_cert(vec![cert], PrivateKeyDer::Pkcs8(key))
        .unwrap();
    let acceptor = tokio_rustls::TlsAcceptor::from(Arc::new(config));
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = listener.local_addr().unwrap().port();
    tokio::spawn(async move {
        while let Ok((tcp, _)) = listener.accept().await {
            let acceptor = acceptor.clone();
            tokio::spawn(async move {
                if let Ok(mut tls) = acceptor.accept(tcp).await {
                    let mut request = [0u8; 4096];
                    let _ = tls.read(&mut request).await;
                    let _ = tls
                        .write_all(
                            b"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 2\r\nConnection: close\r\n\r\n{}",
                        )
                        .await;
                    let _ = tls.shutdown().await;
                }
            });
        }
    });
    port
}

#[tokio::test]
async fn the_pinned_certificate_is_accepted_whatever_its_name() {
    // The companion dials 127.0.0.1, but the certificate names another host,
    // as Sunshine's own certificate does not name the loopback address.
    let (cert, key) = self_signed("sunshine.test");
    let port = serve(cert.clone(), key).await;
    let client = pinned_client(cert.as_ref()).unwrap();
    let response = client
        .get(format!("https://127.0.0.1:{port}/api/apps"))
        .send()
        .await
        .unwrap();
    assert_eq!(response.status(), 200);
}

#[tokio::test]
async fn another_self_signed_certificate_is_refused() {
    let (pinned, _) = self_signed("sunshine.test");
    let (other, key) = self_signed("sunshine.test");
    let port = serve(other, key).await;
    let client = pinned_client(pinned.as_ref()).unwrap();
    let result = client
        .get(format!("https://127.0.0.1:{port}/api/apps"))
        .send()
        .await;
    assert!(
        result.is_err(),
        "a certificate that is not pinned must be refused"
    );
}

#[test]
fn a_pin_that_is_not_a_certificate_is_an_error() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("cacert.pem");
    std::fs::write(&path, "this is not a certificate").unwrap();
    assert!(load_pinned_der(&path).is_err());
}

#[test]
fn a_missing_pin_is_an_error() {
    let dir = tempfile::tempdir().unwrap();
    assert!(load_pinned_der(&dir.path().join("cacert.pem")).is_err());
}
