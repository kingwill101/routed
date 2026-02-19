/// Ensures a rustls crypto provider is installed for this process.
///
/// Tries `aws-lc-rs` first, then falls back to `ring`.
fn ensure_rustls_crypto_provider() -> Result<(), String> {
    use tokio_rustls::rustls::crypto::CryptoProvider;

    if CryptoProvider::get_default().is_some() {
        return Ok(());
    }

    if tokio_rustls::rustls::crypto::aws_lc_rs::default_provider()
        .install_default()
        .is_ok()
    {
        return Ok(());
    }
    if CryptoProvider::get_default().is_some() {
        return Ok(());
    }

    if tokio_rustls::rustls::crypto::ring::default_provider()
        .install_default()
        .is_ok()
    {
        return Ok(());
    }
    if CryptoProvider::get_default().is_some() {
        return Ok(());
    }

    Err("failed to install rustls crypto provider".to_string())
}

/// Loads server-side rustls configuration for HTTP/1.1 + HTTP/2.
fn load_tls_server_config(
    cert_path: &str,
    key_path: &str,
    key_password: Option<&str>,
    enable_http2: bool,
    request_client_certificate: bool,
) -> Result<ServerConfig, String> {
    let certs = load_tls_cert_chain(cert_path)?;

    let key = load_tls_private_key(key_path, key_password)?;
    let mut server_config = if request_client_certificate {
        ServerConfig::builder()
            .with_client_cert_verifier(load_optional_client_verifier()?)
            .with_single_cert(certs, key)
            .map_err(|error| format!("invalid tls cert/key pair: {error}"))?
    } else {
        ServerConfig::builder()
            .with_no_client_auth()
            .with_single_cert(certs, key)
            .map_err(|error| format!("invalid tls cert/key pair: {error}"))?
    };
    server_config.alpn_protocols = if enable_http2 {
        vec![b"h2".to_vec(), b"http/1.1".to_vec()]
    } else {
        vec![b"http/1.1".to_vec()]
    };
    Ok(server_config)
}

/// Loads certificate chain PEM entries from disk.
fn load_tls_cert_chain(
    cert_path: &str,
) -> Result<Vec<tokio_rustls::rustls::pki_types::CertificateDer<'static>>, String> {
    let cert_file = File::open(cert_path)
        .map_err(|error| format!("open tls cert failed ({cert_path}): {error}"))?;
    let mut cert_reader = BufReader::new(cert_file);
    let certs = rustls_pemfile::certs(&mut cert_reader)
        .collect::<Result<Vec<_>, _>>()
        .map_err(|error| format!("read tls cert failed ({cert_path}): {error}"))?;
    if certs.is_empty() {
        return Err(format!(
            "tls cert file contains no certificates: {cert_path}"
        ));
    }
    Ok(certs)
}

/// Loads private key material from disk.
///
/// Supports:
/// - encrypted PKCS#8 PEM (when `key_password` is provided),
/// - unencrypted PKCS#8 PEM,
/// - RSA PEM.
fn load_tls_private_key(
    key_path: &str,
    key_password: Option<&str>,
) -> Result<tokio_rustls::rustls::pki_types::PrivateKeyDer<'static>, String> {
    if let Some(password) = key_password {
        let key_pem = std::fs::read_to_string(key_path)
            .map_err(|error| format!("read tls key failed ({key_path}): {error}"))?;
        if key_pem.contains("BEGIN ENCRYPTED PRIVATE KEY") {
            let (label, doc) = pkcs8::der::SecretDocument::from_pem(&key_pem)
                .map_err(|error| format!("read encrypted key pem failed ({key_path}): {error}"))?;
            pkcs8::EncryptedPrivateKeyInfo::validate_pem_label(&label).map_err(|error| {
                format!("invalid encrypted key pem label ({key_path}): {error}")
            })?;
            let encrypted =
                pkcs8::EncryptedPrivateKeyInfo::try_from(doc.as_bytes()).map_err(|error| {
                    format!("parse encrypted pkcs8 key failed ({key_path}): {error}")
                })?;
            let decrypted = encrypted.decrypt(password).map_err(|error| {
                format!("decrypt encrypted pkcs8 key failed ({key_path}): {error}")
            })?;
            let key_der = decrypted.as_bytes().to_vec();
            return Ok(tokio_rustls::rustls::pki_types::PrivatePkcs8KeyDer::from(key_der).into());
        }
    }

    let pkcs8_file = File::open(key_path)
        .map_err(|error| format!("open tls key failed ({key_path}): {error}"))?;
    let mut pkcs8_reader = BufReader::new(pkcs8_file);
    let pkcs8_keys = rustls_pemfile::pkcs8_private_keys(&mut pkcs8_reader)
        .collect::<Result<Vec<_>, _>>()
        .map_err(|error| format!("read pkcs8 key failed ({key_path}): {error}"))?;
    if let Some(key) = pkcs8_keys.into_iter().next() {
        return Ok(key.into());
    }

    let rsa_file = File::open(key_path)
        .map_err(|error| format!("open tls key failed ({key_path}): {error}"))?;
    let mut rsa_reader = BufReader::new(rsa_file);
    let rsa_keys = rustls_pemfile::rsa_private_keys(&mut rsa_reader)
        .collect::<Result<Vec<_>, _>>()
        .map_err(|error| format!("read rsa key failed ({key_path}): {error}"))?;
    if let Some(key) = rsa_keys.into_iter().next() {
        return Ok(key.into());
    }

    Err(format!(
        "tls key file contains no supported private keys: {key_path}"
    ))
}

/// Creates QUIC endpoint config used for HTTP/3.
fn create_h3_endpoint(
    addr: SocketAddr,
    cert_path: &str,
    key_path: &str,
    key_password: Option<&str>,
    request_client_certificate: bool,
) -> Result<quinn::Endpoint, String> {
    let certs = load_tls_cert_chain(cert_path)?;
    let key = load_tls_private_key(key_path, key_password)?;

    let mut tls_config = if request_client_certificate {
        ServerConfig::builder()
            .with_client_cert_verifier(load_optional_client_verifier()?)
            .with_single_cert(certs, key)
            .map_err(|error| format!("invalid h3 tls cert/key pair: {error}"))?
    } else {
        ServerConfig::builder()
            .with_no_client_auth()
            .with_single_cert(certs, key)
            .map_err(|error| format!("invalid h3 tls cert/key pair: {error}"))?
    };
    tls_config.alpn_protocols = vec![b"h3".to_vec()];
    tls_config.max_early_data_size = u32::MAX;

    let mut server_config = quinn::ServerConfig::with_crypto(Arc::new(
        quinn::crypto::rustls::QuicServerConfig::try_from(tls_config)
            .map_err(|error| format!("invalid h3 quic tls config: {error}"))?,
    ));
    let transport = Arc::get_mut(&mut server_config.transport)
        .ok_or_else(|| "unable to configure h3 transport".to_string())?;
    transport
        .max_concurrent_bidi_streams(100_u32.into())
        .max_concurrent_uni_streams(100_u32.into());
    let idle_timeout = Duration::from_secs(60)
        .try_into()
        .map_err(|error| format!("invalid h3 idle timeout: {error}"))?;
    transport.max_idle_timeout(Some(idle_timeout));

    quinn::Endpoint::server(server_config, addr)
        .map_err(|error| format!("bind h3 endpoint failed: {error}"))
}

/// Builds an optional client-cert verifier from native trust roots.
fn load_optional_client_verifier(
) -> Result<Arc<dyn tokio_rustls::rustls::server::danger::ClientCertVerifier>, String> {
    let roots = load_native_root_store()?;
    let verifier = WebPkiClientVerifier::builder(roots.into())
        .allow_unauthenticated()
        .build()
        .map_err(|error| format!("build client verifier failed: {error}"))?;
    Ok(verifier)
}

/// Loads native root certificates from the host operating system.
fn load_native_root_store() -> Result<RootCertStore, String> {
    let mut roots = RootCertStore::empty();
    let native = rustls_native_certs::load_native_certs();
    if !native.errors.is_empty() {
        eprintln!(
            "[routed_ffi_native] some native root certificates failed to load: {}",
            native.errors.len()
        );
    }
    if native.certs.is_empty() {
        return Err("no native root certificates available for client verification".to_string());
    }
    roots.add_parsable_certificates(native.certs);
    Ok(roots)
}

/// Serves one accepted HTTP/3 connection until graceful close.
async fn handle_h3_connection(incoming: quinn::Incoming, app: Router) -> Result<(), String> {
    let conn = incoming
        .await
        .map_err(|error| format!("h3 connection accept failed: {error}"))?;
    let h3_conn = h3::server::builder()
        .build(h3_quinn::Connection::new(conn))
        .await
        .map_err(|error| format!("h3 handshake failed: {error}"))?;
    tokio::pin!(h3_conn);

    loop {
        match h3_conn.accept().await {
            Ok(Some(resolver)) => {
                let app = app.clone();
                tokio::spawn(async move {
                    if let Err(error) = h3_axum::serve_h3_with_axum(app, resolver).await {
                        eprintln!("[routed_ffi_native] h3 request error: {error}");
                    }
                });
            }
            Ok(None) => break,
            Err(error) => {
                if !h3_axum::is_graceful_h3_close(&error) {
                    return Err(format!("h3 connection error: {error:?}"));
                }
                break;
            }
        }
    }

    Ok(())
}
