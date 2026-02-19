use std::fs::File;
use std::io::BufReader;
use std::net::SocketAddr;
use std::path::PathBuf;
use std::sync::Arc;
use std::time::Duration;

fn tls_assets() -> (PathBuf, PathBuf) {
    let crate_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let cert = crate_dir.join("../../../examples/http2/cert.pem");
    let key = crate_dir.join("../../../examples/http2/key.pem");
    assert!(cert.exists(), "missing cert asset: {}", cert.display());
    assert!(key.exists(), "missing key asset: {}", key.display());
    (cert, key)
}

fn load_cert_chain(
    cert_path: &PathBuf,
) -> Vec<tokio_rustls::rustls::pki_types::CertificateDer<'static>> {
    let cert_file = File::open(cert_path).expect("open cert");
    let mut cert_reader = BufReader::new(cert_file);
    let certs = rustls_pemfile::certs(&mut cert_reader)
        .collect::<Result<Vec<_>, _>>()
        .expect("read cert chain");
    assert!(!certs.is_empty(), "empty cert chain");
    certs
}

fn load_private_key(key_path: &PathBuf) -> tokio_rustls::rustls::pki_types::PrivateKeyDer<'static> {
    let pkcs8_file = File::open(key_path).expect("open key");
    let mut pkcs8_reader = BufReader::new(pkcs8_file);
    let pkcs8_keys = rustls_pemfile::pkcs8_private_keys(&mut pkcs8_reader)
        .collect::<Result<Vec<_>, _>>()
        .expect("read pkcs8 keys");
    if let Some(key) = pkcs8_keys.into_iter().next() {
        return key.into();
    }

    let rsa_file = File::open(key_path).expect("open key");
    let mut rsa_reader = BufReader::new(rsa_file);
    let rsa_keys = rustls_pemfile::rsa_private_keys(&mut rsa_reader)
        .collect::<Result<Vec<_>, _>>()
        .expect("read rsa keys");
    rsa_keys
        .into_iter()
        .next()
        .expect("no supported key")
        .into()
}

fn build_quinn_server_config(cert: &PathBuf, key: &PathBuf) -> quinn::ServerConfig {
    ensure_rustls_crypto_provider();
    let certs = load_cert_chain(cert);
    let key = load_private_key(key);

    let mut tls_config = tokio_rustls::rustls::ServerConfig::builder()
        .with_no_client_auth()
        .with_single_cert(certs, key)
        .expect("valid cert/key");
    tls_config.alpn_protocols = vec![b"h3".to_vec()];
    tls_config.max_early_data_size = u32::MAX;

    let mut server_config = quinn::ServerConfig::with_crypto(Arc::new(
        quinn::crypto::rustls::QuicServerConfig::try_from(tls_config).expect("quic tls config"),
    ));
    let transport = Arc::get_mut(&mut server_config.transport).expect("transport mut");
    transport
        .max_concurrent_bidi_streams(100_u32.into())
        .max_concurrent_uni_streams(100_u32.into());
    let idle_timeout = Duration::from_secs(60).try_into().expect("idle timeout");
    transport.max_idle_timeout(Some(idle_timeout));
    server_config
}

fn ensure_rustls_crypto_provider() {
    use tokio_rustls::rustls::crypto::CryptoProvider;

    if CryptoProvider::get_default().is_some() {
        return;
    }
    if tokio_rustls::rustls::crypto::aws_lc_rs::default_provider()
        .install_default()
        .is_ok()
    {
        return;
    }
    if CryptoProvider::get_default().is_some() {
        return;
    }
    let _ = tokio_rustls::rustls::crypto::ring::default_provider().install_default();
}

#[tokio::test(flavor = "current_thread")]
async fn binds_h3_endpoint_on_ephemeral_port() {
    let (cert, key) = tls_assets();
    let server_config = build_quinn_server_config(&cert, &key);
    let addr = SocketAddr::from(([127, 0, 0, 1], 0));
    let endpoint = quinn::Endpoint::server(server_config, addr).expect("bind h3 endpoint");
    endpoint.close(0_u32.into(), b"test");
}

#[tokio::test(flavor = "current_thread")]
async fn binds_h3_endpoint_alongside_tcp_same_port() {
    let (cert, key) = tls_assets();
    let tcp_listener =
        std::net::TcpListener::bind(SocketAddr::from(([127, 0, 0, 1], 0))).expect("bind tcp");
    let port = tcp_listener.local_addr().expect("tcp local addr").port();

    let server_config = build_quinn_server_config(&cert, &key);
    let addr = SocketAddr::from(([127, 0, 0, 1], port));
    let endpoint = quinn::Endpoint::server(server_config, addr).expect("bind h3 endpoint");
    endpoint.close(0_u32.into(), b"test");
    drop(tcp_listener);
}
