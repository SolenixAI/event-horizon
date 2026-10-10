//! The companion's own TLS identity: one self-signed certificate, made on
//! first use and kept beside `macs.json`. The Mac pins its SHA-256
//! fingerprint, so no certificate authority is involved.

use rcgen::{CertificateParams, KeyPair};
use rustls::ServerConfig;
use rustls::crypto::CryptoProvider;
use rustls::pki_types::{CertificateDer, PrivateKeyDer, PrivatePkcs8KeyDer};
use sha2::{Digest, Sha256};
use std::io;
use std::net::SocketAddr;
use std::path::Path;
use std::sync::Arc;
use std::time::Duration;
use tokio::net::{TcpListener, TcpStream};
use tokio_rustls::TlsAcceptor;
use tokio_rustls::server::TlsStream;

const CERT_FILE: &str = "companion-cert.der";
const KEY_FILE: &str = "companion-key.der";
/// A client that takes longer than this to finish its handshake is dropped.
const HANDSHAKE: Duration = Duration::from_secs(5);

/// The certificate the companion serves, and the fingerprint the Mac pins.
pub struct Identity {
    pub acceptor: TlsAcceptor,
    /// SHA-256 of the certificate's DER bytes, in lowercase hex.
    pub fingerprint: String,
}

/// The companion's certificate in `dir`: made on first use, then kept.
pub fn load_or_create(dir: &Path) -> io::Result<Identity> {
    let (cert, key) = match (
        std::fs::read(dir.join(CERT_FILE)),
        std::fs::read(dir.join(KEY_FILE)),
    ) {
        (Ok(cert), Ok(key)) => (cert, key),
        _ => {
            let (cert, key) = generate()?;
            std::fs::create_dir_all(dir)?;
            std::fs::write(dir.join(CERT_FILE), &cert)?;
            write_private(&dir.join(KEY_FILE), &key)?;
            (cert, key)
        }
    };
    let config = ServerConfig::builder_with_provider(Arc::new(provider()))
        .with_safe_default_protocol_versions()
        .map_err(io::Error::other)?
        .with_no_client_auth()
        .with_single_cert(
            vec![CertificateDer::from(cert.clone())],
            PrivateKeyDer::Pkcs8(PrivatePkcs8KeyDer::from(key)),
        )
        .map_err(io::Error::other)?;
    Ok(Identity {
        acceptor: TlsAcceptor::from(Arc::new(config)),
        fingerprint: fingerprint(&cert),
    })
}

/// SHA-256 of a certificate's DER bytes, in lowercase hex.
pub fn fingerprint(cert_der: &[u8]) -> String {
    Sha256::digest(cert_der)
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect()
}

/// The TLS crypto provider. Linux uses the one reqwest already uses there;
/// the other OSes use ring, which needs no NASM or CMake to build.
#[cfg(target_os = "linux")]
pub fn provider() -> CryptoProvider {
    rustls::crypto::aws_lc_rs::default_provider()
}

#[cfg(not(target_os = "linux"))]
pub fn provider() -> CryptoProvider {
    rustls::crypto::ring::default_provider()
}

/// A new certificate (DER) and its PKCS#8 key (DER).
fn generate() -> io::Result<(Vec<u8>, Vec<u8>)> {
    let key = KeyPair::generate().map_err(io::Error::other)?;
    let cert = CertificateParams::new(vec!["event-horizon-companion".to_string()])
        .map_err(io::Error::other)?
        .self_signed(&key)
        .map_err(io::Error::other)?;
    Ok((cert.der().as_ref().to_vec(), key.serialize_der()))
}

/// The key is readable by its owner only.
fn write_private(path: &Path, bytes: &[u8]) -> io::Result<()> {
    #[cfg(unix)]
    {
        use std::io::Write;
        use std::os::unix::fs::OpenOptionsExt;
        let mut file = std::fs::OpenOptions::new()
            .write(true)
            .create(true)
            .truncate(true)
            .mode(0o600)
            .open(path)?;
        file.write_all(bytes)
    }
    #[cfg(not(unix))]
    {
        std::fs::write(path, bytes)
    }
}

/// Accepts TCP connections and finishes each TLS handshake, for axum to serve.
pub struct TlsListener {
    tcp: TcpListener,
    acceptor: TlsAcceptor,
}

impl TlsListener {
    pub fn new(tcp: TcpListener, acceptor: TlsAcceptor) -> Self {
        Self { tcp, acceptor }
    }
}

impl axum::serve::Listener for TlsListener {
    type Io = TlsStream<TcpStream>;
    type Addr = SocketAddr;

    async fn accept(&mut self) -> (Self::Io, Self::Addr) {
        loop {
            let (tcp, addr) = match self.tcp.accept().await {
                Ok(connection) => connection,
                Err(_) => {
                    tokio::time::sleep(Duration::from_secs(1)).await;
                    continue;
                }
            };
            let handshake = tokio::time::timeout(HANDSHAKE, self.acceptor.accept(tcp));
            if let Ok(Ok(stream)) = handshake.await {
                return (stream, addr);
            }
        }
    }

    fn local_addr(&self) -> io::Result<Self::Addr> {
        self.tcp.local_addr()
    }
}
