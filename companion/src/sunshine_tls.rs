//! The companion's trust in Sunshine's local HTTPS API.
//!
//! Sunshine serves `https://127.0.0.1:47990` with the self-signed certificate
//! it keeps as `credentials/cacert.pem`, and its key as `credentials/cakey.pem`
//! (Sunshine `src/config.cpp` and `src/confighttp.cpp`, tag v2026.914.233613).
//! That certificate has no subject alternative name, so no name check can ever
//! accept it. The companion therefore trusts exactly that certificate, byte for
//! byte, and nothing else. Any other certificate on the loopback address is
//! refused, and so is a missing or unreadable pin.

use crate::tls;
use rustls::client::danger::{HandshakeSignatureValid, ServerCertVerified, ServerCertVerifier};
use rustls::crypto::{
    CryptoProvider, verify_tls12_signature as check_tls12, verify_tls13_signature as check_tls13,
};
use rustls::pki_types::pem::PemObject;
use rustls::pki_types::{CertificateDer, ServerName, UnixTime};
use rustls::{ClientConfig, DigitallySignedStruct, Error, SignatureScheme};
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::Duration;

/// Accepts one certificate: the pinned one. The pin is the identity, so the
/// name the client asked for is not checked. The handshake signature is still
/// verified, so the server must hold the pinned certificate's key.
#[derive(Debug)]
struct Pinned {
    cert: CertificateDer<'static>,
    provider: Arc<CryptoProvider>,
}

impl ServerCertVerifier for Pinned {
    fn verify_server_cert(
        &self,
        end_entity: &CertificateDer<'_>,
        _intermediates: &[CertificateDer<'_>],
        _server_name: &ServerName<'_>,
        _ocsp_response: &[u8],
        _now: UnixTime,
    ) -> Result<ServerCertVerified, Error> {
        if end_entity.as_ref() == self.cert.as_ref() {
            Ok(ServerCertVerified::assertion())
        } else {
            Err(Error::General(
                "Sunshine presented a certificate other than the pinned one".into(),
            ))
        }
    }

    fn verify_tls12_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        dss: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, Error> {
        check_tls12(
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
    ) -> Result<HandshakeSignatureValid, Error> {
        check_tls13(
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

/// An HTTP client that talks to Sunshine only if it presents `pinned_der`, the
/// DER bytes of the certificate Sunshine wrote to disk.
pub fn pinned_client(pinned_der: &[u8]) -> Result<reqwest::Client, String> {
    // reqwest's rustls-no-provider build needs a process default provider before
    // it builds a client. Installing one that is already set is harmless.
    let _ = tls::provider().install_default();
    let provider = Arc::new(tls::provider());
    let verifier = Pinned {
        cert: CertificateDer::from(pinned_der.to_vec()),
        provider: provider.clone(),
    };
    let config: ClientConfig = ClientConfig::builder_with_provider(provider)
        .with_safe_default_protocol_versions()
        .map_err(|e| e.to_string())?
        .dangerous()
        .with_custom_certificate_verifier(Arc::new(verifier))
        .with_no_client_auth();
    reqwest::Client::builder()
        .tls_backend_preconfigured(config)
        .timeout(Duration::from_secs(5))
        .build()
        .map_err(|e| e.to_string())
}

/// The DER bytes of the PEM certificate at `path`.
pub fn load_pinned_der(path: &Path) -> Result<Vec<u8>, String> {
    let pem = std::fs::read(path).map_err(|e| format!("cannot read {}: {e}", path.display()))?;
    let cert = CertificateDer::from_pem_slice(&pem)
        .map_err(|e| format!("{} is not a PEM certificate: {e}", path.display()))?;
    Ok(cert.as_ref().to_vec())
}

/// Where Sunshine keeps the certificate it serves its web API with. Sunshine
/// writes it under its appdata folder, `credentials/cacert.pem`. On Linux, a
/// Flatpak Sunshine keeps its appdata under `~/.var/app`, otherwise it uses
/// `$XDG_CONFIG_HOME/sunshine` or `~/.config/sunshine` (`appdata()` in Sunshine's
/// `src/platform/linux/misc.cpp`). `SUNSHINE_CERT_PATH` overrides all of it.
/// Elsewhere there is no default yet, so the companion refuses to start
/// without the override rather than guess.
pub fn default_cert_path() -> Option<PathBuf> {
    if let Some(path) = std::env::var_os("SUNSHINE_CERT_PATH").filter(|p| !p.is_empty()) {
        return Some(PathBuf::from(path));
    }
    if !cfg!(target_os = "linux") {
        return None;
    }
    let home = PathBuf::from(std::env::var_os("HOME")?);
    let flatpak =
        home.join(".var/app/dev.lizardbyte.app.Sunshine/config/sunshine/credentials/cacert.pem");
    if flatpak.is_file() {
        return Some(flatpak);
    }
    let config = std::env::var_os("XDG_CONFIG_HOME")
        .filter(|v| !v.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| home.join(".config"));
    Some(config.join("sunshine/credentials/cacert.pem"))
}
