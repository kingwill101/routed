use std::ffi::{c_char, CStr};
use std::fs::File;
use std::io::{self, BufReader, ErrorKind, IoSlice};
use std::net::SocketAddr;
use std::path::PathBuf;
use std::ptr::null_mut;
use std::sync::Arc;
use std::thread;
use std::time::Duration;

use axum::body::{Body, BodyDataStream, Bytes, HttpBody};
use axum::extract::State;
use axum::http::{HeaderMap, Request, Response, StatusCode, Version};
use axum::routing::any;
use axum::Router;
use hyper::upgrade::OnUpgrade;
use hyper_util::rt::{TokioExecutor, TokioIo};
use hyper_util::server::conn::auto::Builder as AutoBuilder;
use hyper_util::service::TowerToHyperService;
use parking_lot::Mutex;
use pkcs8::der::pem::PemLabel;
use socket2::{Domain, Protocol, Socket, Type};
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt};
#[cfg(unix)]
use tokio::net::UnixStream;
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::{mpsc, oneshot};
use tokio_rustls::rustls::server::WebPkiClientVerifier;
use tokio_rustls::rustls::{RootCertStore, ServerConfig};
use tokio_rustls::TlsAcceptor;
use tokio_stream::{wrappers::ReceiverStream, StreamExt};

const MAX_PROXY_BODY_BYTES: usize = 32 * 1024 * 1024;
const MAX_BRIDGE_FRAME_BYTES: usize = 64 * 1024 * 1024;
const BRIDGE_BODY_CHUNK_BYTES: usize = 64 * 1024;
const BRIDGE_PROTOCOL_VERSION: u8 = 1;
const BRIDGE_REQUEST_FRAME_TYPE: u8 = 1; // legacy single-frame request
const BRIDGE_RESPONSE_FRAME_TYPE: u8 = 2; // legacy single-frame response
const BRIDGE_REQUEST_START_FRAME_TYPE: u8 = 3;
const BRIDGE_REQUEST_CHUNK_FRAME_TYPE: u8 = 4;
const BRIDGE_REQUEST_END_FRAME_TYPE: u8 = 5;
const BRIDGE_RESPONSE_START_FRAME_TYPE: u8 = 6;
const BRIDGE_RESPONSE_CHUNK_FRAME_TYPE: u8 = 7;
const BRIDGE_RESPONSE_END_FRAME_TYPE: u8 = 8;
const BRIDGE_TUNNEL_CHUNK_FRAME_TYPE: u8 = 9;
const BRIDGE_TUNNEL_CLOSE_FRAME_TYPE: u8 = 10;
const BRIDGE_BACKEND_KIND_TCP: u8 = 0;
const BRIDGE_BACKEND_KIND_UNIX: u8 = 1;
const BENCHMARK_MODE_NONE: u8 = 0;
const BENCHMARK_MODE_STATIC_OK: u8 = 1;
const BENCHMARK_STATIC_OK_BODY: &[u8] = br#"{"ok":true,"label":"routed_ffi_native_direct"}"#;

#[repr(C)]
pub struct RoutedFfiProxyConfig {
    pub host: *const c_char,
    pub port: u16,
    pub backend_host: *const c_char,
    pub backend_port: u16,
    pub backend_kind: u8,
    pub backend_path: *const c_char,
    pub backlog: u32,
    pub v6_only: u8,
    pub shared: u8,
    pub request_client_certificate: u8,
    pub http3: u8,
    pub tls_cert_path: *const c_char,
    pub tls_key_path: *const c_char,
    pub tls_cert_password: *const c_char,
    pub benchmark_mode: u8,
}

#[derive(Clone)]
struct ProxyState {
    bridge_pool: Arc<BridgePool>,
    benchmark_mode: u8,
}

#[derive(Clone)]
struct ProxyTlsConfig {
    cert_path: String,
    key_path: String,
    cert_password: Option<String>,
}

pub struct ProxyServerHandle {
    shutdown_tx: Option<oneshot::Sender<()>>,
    join_handle: Option<thread::JoinHandle<()>>,
}

struct BridgePool {
    endpoint: BridgeEndpoint,
    max_idle: usize,
    hot: Mutex<Option<BridgeConnection>>,
    idle: Mutex<Vec<BridgeConnection>>,
}

trait BridgeStream: AsyncRead + AsyncWrite + Unpin + Send {}
impl<T> BridgeStream for T where T: AsyncRead + AsyncWrite + Unpin + Send {}
type BoxBridgeStream = Box<dyn BridgeStream>;

struct BridgeConnection {
    stream: BoxBridgeStream,
    read_buffer: Vec<u8>,
}

#[derive(Clone)]
enum BridgeEndpoint {
    Tcp(String),
    #[cfg(unix)]
    Unix(PathBuf),
    #[cfg(not(unix))]
    Unix(String),
}

impl BridgePool {
    fn new(endpoint: BridgeEndpoint, max_idle: usize) -> Self {
        Self {
            endpoint,
            max_idle,
            hot: Mutex::new(None),
            idle: Mutex::new(Vec::new()),
        }
    }

    async fn acquire(&self) -> Result<BridgeConnection, String> {
        {
            let mut hot = self.hot.lock();
            if let Some(stream) = hot.take() {
                return Ok(stream);
            }
        }
        {
            let mut idle = self.idle.lock();
            if let Some(stream) = idle.pop() {
                return Ok(stream);
            }
        }

        self.connect_new().await
    }

    async fn connect_new(&self) -> Result<BridgeConnection, String> {
        match &self.endpoint {
            BridgeEndpoint::Tcp(addr) => {
                let stream = TcpStream::connect(addr)
                    .await
                    .map_err(|error| format!("connect failed: {error}"))?;
                stream
                    .set_nodelay(true)
                    .map_err(|error| format!("set_nodelay failed: {error}"))?;
                Ok(BridgeConnection {
                    stream: Box::new(stream),
                    read_buffer: Vec::with_capacity(8 * 1024),
                })
            }
            #[cfg(unix)]
            BridgeEndpoint::Unix(path) => {
                let stream = UnixStream::connect(path)
                    .await
                    .map_err(|error| format!("connect failed: {error}"))?;
                Ok(BridgeConnection {
                    stream: Box::new(stream),
                    read_buffer: Vec::with_capacity(8 * 1024),
                })
            }
            #[cfg(not(unix))]
            BridgeEndpoint::Unix(_) => {
                Err("unix bridge backend is not supported on this platform".to_string())
            }
        }
    }

    fn release(&self, mut connection: BridgeConnection) {
        // Prevent one oversized frame from permanently bloating pooled buffers.
        if connection.read_buffer.capacity() > MAX_BRIDGE_FRAME_BYTES {
            connection.read_buffer = Vec::with_capacity(8 * 1024);
        } else {
            connection.read_buffer.clear();
        }
        let mut connection = Some(connection);
        {
            let mut hot = self.hot.lock();
            if hot.is_none() {
                *hot = connection.take();
            }
        }
        let Some(connection) = connection else {
            return;
        };
        let mut idle = self.idle.lock();
        if idle.len() < self.max_idle {
            idle.push(connection);
        }
    }
}

struct BridgeRequestRef<'a> {
    method: &'a str,
    scheme: &'a str,
    authority: &'a str,
    path: &'a str,
    query: &'a str,
    protocol: &'a str,
    headers: &'a HeaderMap,
}

struct BridgeResponse {
    status: u16,
    headers: Vec<(axum::http::header::HeaderName, axum::http::HeaderValue)>,
    body_bytes: Bytes,
}

struct BridgeCallResult {
    status: u16,
    headers: Vec<(axum::http::header::HeaderName, axum::http::HeaderValue)>,
    body: Body,
    tunnel_socket: Option<BridgeConnection>,
}

#[no_mangle]
pub extern "C" fn routed_ffi_transport_version() -> i32 {
    1
}

#[no_mangle]
pub extern "C" fn routed_ffi_start_proxy_server(
    config: *const RoutedFfiProxyConfig,
    out_port: *mut u16,
) -> *mut ProxyServerHandle {
    if config.is_null() || out_port.is_null() {
        eprintln!("[routed_ffi_native] invalid start parameters");
        return null_mut();
    }

    let config = unsafe { &*config };
    let host = match c_string_to_string(config.host) {
        Some(value) if !value.is_empty() => value,
        _ => {
            eprintln!("[routed_ffi_native] invalid host");
            return null_mut();
        }
    };
    let port = config.port;
    let bridge_endpoint = match config.backend_kind {
        BRIDGE_BACKEND_KIND_TCP => {
            let bridge_host = match c_string_to_string(config.backend_host) {
                Some(value) if !value.is_empty() => value,
                _ => {
                    eprintln!("[routed_ffi_native] invalid backend_host");
                    return null_mut();
                }
            };
            let bridge_port = config.backend_port;
            BridgeEndpoint::Tcp(format!("{}:{}", bridge_host, bridge_port))
        }
        BRIDGE_BACKEND_KIND_UNIX => {
            let path = match c_string_to_string(config.backend_path) {
                Some(value) if !value.is_empty() => value,
                _ => {
                    eprintln!("[routed_ffi_native] invalid backend_path");
                    return null_mut();
                }
            };
            #[cfg(unix)]
            {
                BridgeEndpoint::Unix(PathBuf::from(path))
            }
            #[cfg(not(unix))]
            {
                BridgeEndpoint::Unix(path)
            }
        }
        backend_kind => {
            eprintln!("[routed_ffi_native] invalid backend_kind: {backend_kind}");
            return null_mut();
        }
    };
    let enable_http3 = config.http3 != 0;
    let backlog = config.backlog;
    let v6_only = config.v6_only != 0;
    let shared = config.shared != 0;
    let request_client_certificate = config.request_client_certificate != 0;
    let benchmark_mode = config.benchmark_mode;
    if benchmark_mode != BENCHMARK_MODE_NONE && benchmark_mode != BENCHMARK_MODE_STATIC_OK {
        eprintln!("[routed_ffi_native] invalid benchmark_mode: {benchmark_mode}");
        return null_mut();
    }
    let tls_cert_path = c_string_to_string(config.tls_cert_path).filter(|value| !value.is_empty());
    let tls_key_path = c_string_to_string(config.tls_key_path).filter(|value| !value.is_empty());
    let tls_cert_password =
        c_string_to_string(config.tls_cert_password).filter(|value| !value.is_empty());
    let tls_config = match (tls_cert_path, tls_key_path) {
        (None, None) => None,
        (Some(cert_path), Some(key_path)) => Some(ProxyTlsConfig {
            cert_path,
            key_path,
            cert_password: tls_cert_password,
        }),
        _ => {
            eprintln!(
                "[routed_ffi_native] invalid tls settings: both tls_cert_path and tls_key_path are required"
            );
            return null_mut();
        }
    };

    let (startup_tx, startup_rx) = std::sync::mpsc::channel::<Result<u16, String>>();
    let (shutdown_tx, shutdown_rx) = oneshot::channel::<()>();

    let join_handle = thread::spawn(move || {
        let worker_threads = std::thread::available_parallelism()
            .map(|value| value.get())
            .unwrap_or(2)
            .clamp(2, 16);
        let runtime = match tokio::runtime::Builder::new_multi_thread()
            .enable_all()
            .worker_threads(worker_threads)
            .thread_name("routed-ffi-proxy")
            .build()
        {
            Ok(runtime) => runtime,
            Err(error) => {
                let _ = startup_tx.send(Err(format!("failed to build runtime: {error}")));
                return;
            }
        };

        runtime.block_on(async move {
            let listener = match bind_tcp_listener(&host, port, backlog, v6_only, shared).await {
                Ok(listener) => listener,
                Err(error) => {
                    let _ = startup_tx.send(Err(format!("bind failed: {error}")));
                    return;
                }
            };

            let actual_port = match listener.local_addr() {
                Ok(addr) => addr.port(),
                Err(error) => {
                    let _ = startup_tx.send(Err(format!("local_addr failed: {error}")));
                    return;
                }
            };

            let state = ProxyState {
                bridge_pool: Arc::new(BridgePool::new(bridge_endpoint, 256)),
                benchmark_mode,
            };
            let app = Router::new().fallback(any(proxy_request)).with_state(state);
            let _ = startup_tx.send(Ok(actual_port));

            let result = match tls_config {
                Some(tls_config) => {
                    run_tls_proxy(
                        listener,
                        app,
                        shutdown_rx,
                        tls_config,
                        enable_http3,
                        request_client_certificate,
                    )
                    .await
                }
                None => {
                    if request_client_certificate {
                        eprintln!(
                            "[routed_ffi_native] request_client_certificate requires tls cert/key; option ignored"
                        );
                    }
                    if enable_http3 {
                        eprintln!(
                            "[routed_ffi_native] http3 requested without tls cert/key; running http1/http2 only"
                        );
                    }
                    run_plain_proxy(listener, app, shutdown_rx).await
                }
            };

            if let Err(error) = result {
                eprintln!("[routed_ffi_native] proxy server error: {error}");
            }
        });
    });

    let actual_port = match startup_rx.recv_timeout(Duration::from_secs(10)) {
        Ok(Ok(port)) => port,
        Ok(Err(error)) => {
            eprintln!("[routed_ffi_native] startup failed: {error}");
            let _ = join_handle.join();
            return null_mut();
        }
        Err(error) => {
            eprintln!("[routed_ffi_native] startup timeout/error: {error}");
            let _ = join_handle.join();
            return null_mut();
        }
    };

    unsafe {
        *out_port = actual_port;
    }

    let handle = ProxyServerHandle {
        shutdown_tx: Some(shutdown_tx),
        join_handle: Some(join_handle),
    };
    Box::into_raw(Box::new(handle))
}

#[no_mangle]
pub extern "C" fn routed_ffi_stop_proxy_server(handle: *mut ProxyServerHandle) {
    if handle.is_null() {
        return;
    }

    let mut handle = unsafe { Box::from_raw(handle) };
    if let Some(tx) = handle.shutdown_tx.take() {
        let _ = tx.send(());
    }
    if let Some(join_handle) = handle.join_handle.take() {
        let _ = join_handle.join();
    }
}

async fn bind_tcp_listener(
    host: &str,
    port: u16,
    backlog: u32,
    v6_only: bool,
    shared: bool,
) -> Result<TcpListener, String> {
    let mut resolved = tokio::net::lookup_host((host, port))
        .await
        .map_err(|error| format!("resolve {host}:{port} failed: {error}"))?;
    let mut last_error: Option<String> = None;

    while let Some(addr) = resolved.next() {
        match bind_tcp_listener_addr(addr, backlog, v6_only, shared) {
            Ok(listener) => return Ok(listener),
            Err(error) => {
                last_error = Some(format!("bind {addr} failed: {error}"));
            }
        }
    }

    Err(last_error.unwrap_or_else(|| format!("no resolved addresses for {host}:{port}")))
}

fn bind_tcp_listener_addr(
    addr: SocketAddr,
    backlog: u32,
    v6_only: bool,
    shared: bool,
) -> Result<TcpListener, String> {
    let domain = if addr.is_ipv6() {
        Domain::IPV6
    } else {
        Domain::IPV4
    };
    let socket = Socket::new(domain, Type::STREAM, Some(Protocol::TCP))
        .map_err(|error| format!("socket create failed: {error}"))?;

    if addr.is_ipv6() {
        socket
            .set_only_v6(v6_only)
            .map_err(|error| format!("set_only_v6 failed: {error}"))?;
    }

    if shared {
        socket
            .set_reuse_address(true)
            .map_err(|error| format!("set_reuse_address failed: {error}"))?;
        #[cfg(unix)]
        socket
            .set_reuse_port(true)
            .map_err(|error| format!("set_reuse_port failed: {error}"))?;
    }

    socket
        .bind(&addr.into())
        .map_err(|error| format!("socket bind failed: {error}"))?;

    let backlog = if backlog == 0 {
        1024
    } else {
        backlog.min(i32::MAX as u32)
    };
    socket
        .listen(backlog as i32)
        .map_err(|error| format!("socket listen failed: {error}"))?;

    socket
        .set_nonblocking(true)
        .map_err(|error| format!("set_nonblocking failed: {error}"))?;

    let listener = std::net::TcpListener::from(socket);
    TcpListener::from_std(listener).map_err(|error| format!("from_std failed: {error}"))
}

async fn run_plain_proxy(
    listener: TcpListener,
    app: Router,
    mut shutdown_rx: oneshot::Receiver<()>,
) -> Result<(), String> {
    let mut connections = tokio::task::JoinSet::new();

    loop {
        tokio::select! {
            _ = &mut shutdown_rx => {
                break;
            }
            accepted = listener.accept() => {
                let (stream, _) = match accepted {
                    Ok(value) => value,
                    Err(error) => {
                        eprintln!("[routed_ffi_native] plain accept failed: {error}");
                        continue;
                    }
                };
                if let Err(error) = stream.set_nodelay(true) {
                    eprintln!("[routed_ffi_native] set_nodelay failed: {error}");
                }
                let app = app.clone();
                connections.spawn(async move {
                    let builder = AutoBuilder::new(TokioExecutor::new());
                    let service = TowerToHyperService::new(app);
                    builder
                        .serve_connection_with_upgrades(TokioIo::new(stream), service)
                        .await
                        .map_err(|error| format!("plain connection failed: {error}"))
                });
            }
        }
    }

    while let Some(result) = connections.join_next().await {
        match result {
            Ok(Ok(())) => {}
            Ok(Err(error)) => eprintln!("[routed_ffi_native] {error}"),
            Err(error) => eprintln!("[routed_ffi_native] plain task join failed: {error}"),
        }
    }

    Ok(())
}

async fn run_tls_proxy(
    listener: TcpListener,
    app: Router,
    mut shutdown_rx: oneshot::Receiver<()>,
    tls_config: ProxyTlsConfig,
    enable_http3: bool,
    request_client_certificate: bool,
) -> Result<(), String> {
    ensure_rustls_crypto_provider()?;
    let tls = load_tls_server_config(
        &tls_config.cert_path,
        &tls_config.key_path,
        tls_config.cert_password.as_deref(),
        request_client_certificate,
    )?;
    let acceptor = TlsAcceptor::from(Arc::new(tls));
    let mut connections = tokio::task::JoinSet::new();
    let local_addr = listener
        .local_addr()
        .map_err(|error| format!("local_addr failed: {error}"))?;
    let h3_endpoint = if enable_http3 {
        match create_h3_endpoint(
            local_addr,
            &tls_config.cert_path,
            &tls_config.key_path,
            tls_config.cert_password.as_deref(),
            request_client_certificate,
        ) {
            Ok(endpoint) => {
                eprintln!(
                    "[routed_ffi_native] http3 endpoint enabled on https://{}:{}",
                    local_addr.ip(),
                    local_addr.port()
                );
                Some(endpoint)
            }
            Err(error) => {
                eprintln!(
                    "[routed_ffi_native] http3 setup failed; continuing with http1/http2 only: {error}"
                );
                None
            }
        }
    } else {
        None
    };

    if let Some(endpoint) = h3_endpoint.as_ref() {
        loop {
            tokio::select! {
                _ = &mut shutdown_rx => {
                    break;
                }
                accepted = listener.accept() => {
                    let (stream, _) = match accepted {
                        Ok(value) => value,
                        Err(error) => {
                            eprintln!("[routed_ffi_native] tls accept failed: {error}");
                            continue;
                        }
                    };
                    let acceptor = acceptor.clone();
                    let app = app.clone();
                    connections.spawn(async move {
                        let tls_stream = acceptor
                            .accept(stream)
                            .await
                            .map_err(|error| format!("tls handshake failed: {error}"))?;
                        let builder = AutoBuilder::new(TokioExecutor::new());
                        let service = TowerToHyperService::new(app);
                        builder
                            .serve_connection_with_upgrades(TokioIo::new(tls_stream), service)
                            .await
                            .map_err(|error| format!("tls connection failed: {error}"))
                    });
                }
                incoming = endpoint.accept() => {
                    let Some(incoming) = incoming else {
                        break;
                    };
                    let app = app.clone();
                    connections.spawn(async move { handle_h3_connection(incoming, app).await });
                }
            }
        }
    } else {
        loop {
            tokio::select! {
                _ = &mut shutdown_rx => {
                    break;
                }
                accepted = listener.accept() => {
                    let (stream, _) = match accepted {
                        Ok(value) => value,
                        Err(error) => {
                            eprintln!("[routed_ffi_native] tls accept failed: {error}");
                            continue;
                        }
                    };
                    let acceptor = acceptor.clone();
                    let app = app.clone();
                    connections.spawn(async move {
                        let tls_stream = acceptor
                            .accept(stream)
                            .await
                            .map_err(|error| format!("tls handshake failed: {error}"))?;
                        let builder = AutoBuilder::new(TokioExecutor::new());
                        let service = TowerToHyperService::new(app);
                        builder
                            .serve_connection_with_upgrades(TokioIo::new(tls_stream), service)
                            .await
                            .map_err(|error| format!("tls connection failed: {error}"))
                    });
                }
            }
        }
    }

    if let Some(endpoint) = h3_endpoint {
        endpoint.close(0_u32.into(), b"shutdown");
    }

    while let Some(result) = connections.join_next().await {
        match result {
            Ok(Ok(())) => {}
            Ok(Err(error)) => eprintln!("[routed_ffi_native] {error}"),
            Err(error) => eprintln!("[routed_ffi_native] tls task join failed: {error}"),
        }
    }

    Ok(())
}

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

fn load_tls_server_config(
    cert_path: &str,
    key_path: &str,
    key_password: Option<&str>,
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
    server_config.alpn_protocols = vec![b"h2".to_vec(), b"http/1.1".to_vec()];
    Ok(server_config)
}

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

fn load_optional_client_verifier(
) -> Result<Arc<dyn tokio_rustls::rustls::server::danger::ClientCertVerifier>, String> {
    let roots = load_native_root_store()?;
    let verifier = WebPkiClientVerifier::builder(roots.into())
        .allow_unauthenticated()
        .build()
        .map_err(|error| format!("build client verifier failed: {error}"))?;
    Ok(verifier)
}

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

async fn proxy_request(State(state): State<ProxyState>, request: Request<Body>) -> Response<Body> {
    if state.benchmark_mode == BENCHMARK_MODE_STATIC_OK {
        return benchmark_static_ok_response();
    }

    let (mut parts, body) = request.into_parts();
    let websocket_upgrade_requested = is_websocket_upgrade(&parts.headers);
    let upgrade = if websocket_upgrade_requested {
        parts.extensions.remove::<OnUpgrade>()
    } else {
        None
    };

    let path_and_query = parts
        .uri
        .path_and_query()
        .map(|value| value.as_str())
        .unwrap_or(parts.uri.path());
    let (path, query) = split_path_and_query_ref(path_and_query);
    let request_body_known_empty = body.size_hint().exact() == Some(0);
    let body_stream = body.into_data_stream();

    let authority = parts
        .headers
        .get("host")
        .and_then(|value| value.to_str().ok())
        .unwrap_or_default();
    let scheme = parts.uri.scheme_str().unwrap_or("http");

    let bridge_request = BridgeRequestRef {
        method: parts.method.as_str(),
        scheme,
        authority,
        path,
        query,
        protocol: http_version_to_protocol(parts.version),
        headers: &parts.headers,
    };

    let mut bridge_result = match call_bridge(
        &state.bridge_pool,
        bridge_request,
        body_stream,
        request_body_known_empty,
        websocket_upgrade_requested,
    )
    .await
    {
        Ok(response) => response,
        Err(error) => {
            return text_response(
                StatusCode::BAD_GATEWAY,
                format!("bridge call failed: {error}"),
            );
        }
    };

    let status = match StatusCode::from_u16(bridge_result.status) {
        Ok(status) => status,
        Err(_) => StatusCode::BAD_GATEWAY,
    };

    if websocket_upgrade_requested && status == StatusCode::SWITCHING_PROTOCOLS {
        let Some(upgrade) = upgrade else {
            return text_response(
                StatusCode::BAD_GATEWAY,
                "websocket upgrade failed: missing hyper upgrade handle",
            );
        };
        let Some(tunnel_connection) = bridge_result.tunnel_socket.take() else {
            return text_response(
                StatusCode::BAD_GATEWAY,
                "websocket upgrade failed: bridge did not expose detached socket",
            );
        };
        tokio::spawn(async move {
            if let Err(error) = run_websocket_tunnel(upgrade, tunnel_connection.stream).await {
                eprintln!("[routed_ffi_native] websocket tunnel error: {error}");
            }
        });
    }

    let mut response = Response::new(bridge_result.body);
    *response.status_mut() = status;
    for (header_name, header_value) in bridge_result.headers {
        response.headers_mut().append(header_name, header_value);
    }
    response
}

fn benchmark_static_ok_response() -> Response<Body> {
    let mut response = Response::new(Body::from(BENCHMARK_STATIC_OK_BODY));
    *response.status_mut() = StatusCode::OK;
    response.headers_mut().insert(
        axum::http::header::CONTENT_TYPE,
        axum::http::HeaderValue::from_static("application/json"),
    );
    response
}

async fn call_bridge(
    bridge_pool: &Arc<BridgePool>,
    request: BridgeRequestRef<'_>,
    mut request_body_stream: BodyDataStream,
    request_body_known_empty: bool,
    websocket_upgrade_requested: bool,
) -> Result<BridgeCallResult, String> {
    let mut connection = bridge_pool.acquire().await?;
    let mut request_body_empty = true;
    if let Err(error) = write_bridge_request(
        &mut *connection.stream,
        &request,
        &mut request_body_stream,
        &mut request_body_empty,
        request_body_known_empty,
    )
    .await
    {
        if request_body_empty {
            return call_bridge_retry_empty_body(
                bridge_pool,
                &request,
                websocket_upgrade_requested,
            )
            .await;
        }
        return Err(error);
    }

    if !read_bridge_frame_reuse(&mut *connection.stream, &mut connection.read_buffer).await? {
        if request_body_empty {
            return call_bridge_retry_empty_body(
                bridge_pool,
                &request,
                websocket_upgrade_requested,
            )
            .await;
        }
        return Err("bridge closed connection without response".to_string());
    }

    match decode_bridge_response_stream(
        connection,
        bridge_pool.clone(),
        websocket_upgrade_requested,
    )
    .await
    {
        Ok(response) => Ok(response),
        Err(error) => {
            if request_body_empty {
                return call_bridge_retry_empty_body(
                    bridge_pool,
                    &request,
                    websocket_upgrade_requested,
                )
                .await;
            }
            Err(error)
        }
    }
}

async fn call_bridge_retry_empty_body(
    bridge_pool: &Arc<BridgePool>,
    request: &BridgeRequestRef<'_>,
    websocket_upgrade_requested: bool,
) -> Result<BridgeCallResult, String> {
    let mut connection = bridge_pool.connect_new().await?;
    write_bridge_empty_request(&mut *connection.stream, request).await?;
    if !read_bridge_frame_reuse(&mut *connection.stream, &mut connection.read_buffer).await? {
        return Err("bridge closed connection without response".to_string());
    }
    decode_bridge_response_stream(connection, bridge_pool.clone(), websocket_upgrade_requested)
        .await
}

async fn write_bridge_request(
    socket: &mut dyn BridgeStream,
    request: &BridgeRequestRef<'_>,
    request_body_stream: &mut BodyDataStream,
    request_body_empty: &mut bool,
    request_body_known_empty: bool,
) -> Result<(), String> {
    if request_body_known_empty {
        *request_body_empty = true;
        write_bridge_empty_request(socket, request).await?;
        return Ok(());
    }
    *request_body_empty = true;
    let mut first_non_empty_chunk: Option<Bytes> = None;
    while let Some(next_chunk) = request_body_stream.next().await {
        let chunk =
            next_chunk.map_err(|error| format!("failed to read request body chunk: {error}"))?;
        if chunk.is_empty() {
            continue;
        }
        *request_body_empty = false;
        first_non_empty_chunk = Some(chunk);
        break;
    }

    if first_non_empty_chunk.is_none() {
        write_bridge_empty_request(socket, request).await?;
        return Ok(());
    }

    let start_payload = encode_bridge_request_start(request)?;
    write_bridge_frame(socket, &start_payload).await?;

    let mut total_body_bytes = 0usize;
    if let Some(first_chunk) = first_non_empty_chunk {
        total_body_bytes =
            write_bridge_request_body_chunk(socket, first_chunk.as_ref(), total_body_bytes).await?;
    }

    while let Some(next_chunk) = request_body_stream.next().await {
        let chunk =
            next_chunk.map_err(|error| format!("failed to read request body chunk: {error}"))?;
        if chunk.is_empty() {
            continue;
        }
        total_body_bytes =
            write_bridge_request_body_chunk(socket, chunk.as_ref(), total_body_bytes).await?;
    }

    let end_payload = encode_bridge_request_end();
    write_bridge_frame(socket, &end_payload).await
}

async fn write_bridge_empty_request(
    socket: &mut dyn BridgeStream,
    request: &BridgeRequestRef<'_>,
) -> Result<(), String> {
    let payload = encode_bridge_request(request, &[])?;
    write_bridge_frame(socket, &payload).await
}

async fn write_bridge_request_body_chunk(
    socket: &mut dyn BridgeStream,
    chunk: &[u8],
    total_body_bytes: usize,
) -> Result<usize, String> {
    let total_body_bytes = total_body_bytes
        .checked_add(chunk.len())
        .ok_or_else(|| "request body length overflow".to_string())?;
    if total_body_bytes > MAX_PROXY_BODY_BYTES {
        return Err(format!(
            "failed to read request body: body too large: {total_body_bytes}"
        ));
    }

    for frame_chunk in chunk.chunks(BRIDGE_BODY_CHUNK_BYTES) {
        write_bridge_request_chunk_frame(socket, frame_chunk).await?;
    }

    Ok(total_body_bytes)
}

fn encode_bridge_request_start(request: &BridgeRequestRef<'_>) -> Result<Vec<u8>, String> {
    let mut writer = BridgeByteWriter::new();
    writer.reserve(256 + request.headers.len() * 32);
    writer.put_u8(BRIDGE_PROTOCOL_VERSION);
    writer.put_u8(BRIDGE_REQUEST_START_FRAME_TYPE);
    writer.put_string(request.method)?;
    writer.put_string(request.scheme)?;
    writer.put_string(request.authority)?;
    writer.put_string(request.path)?;
    writer.put_string(request.query)?;
    writer.put_string(request.protocol)?;
    let count_pos = writer.reserve_u32();
    let mut count: u32 = 0;
    for (name, value) in request.headers.iter() {
        let Ok(value) = value.to_str() else {
            continue;
        };
        count = count
            .checked_add(1)
            .ok_or_else(|| "bridge request has too many headers".to_string())?;
        writer.put_string(name.as_str())?;
        writer.put_string(value)?;
    }
    writer.patch_u32(count_pos, count);
    Ok(writer.into_inner())
}

fn encode_bridge_request(
    request: &BridgeRequestRef<'_>,
    body_bytes: &[u8],
) -> Result<Vec<u8>, String> {
    let mut writer = BridgeByteWriter::new();
    writer.reserve(256 + request.headers.len() * 32 + body_bytes.len());
    writer.put_u8(BRIDGE_PROTOCOL_VERSION);
    writer.put_u8(BRIDGE_REQUEST_FRAME_TYPE);
    writer.put_string(request.method)?;
    writer.put_string(request.scheme)?;
    writer.put_string(request.authority)?;
    writer.put_string(request.path)?;
    writer.put_string(request.query)?;
    writer.put_string(request.protocol)?;
    let count_pos = writer.reserve_u32();
    let mut count: u32 = 0;
    for (name, value) in request.headers.iter() {
        let Ok(value) = value.to_str() else {
            continue;
        };
        count = count
            .checked_add(1)
            .ok_or_else(|| "bridge request has too many headers".to_string())?;
        writer.put_string(name.as_str())?;
        writer.put_string(value)?;
    }
    writer.patch_u32(count_pos, count);
    writer.put_bytes(body_bytes)?;
    Ok(writer.into_inner())
}

fn encode_bridge_request_end() -> Vec<u8> {
    vec![BRIDGE_PROTOCOL_VERSION, BRIDGE_REQUEST_END_FRAME_TYPE]
}

async fn write_bridge_request_chunk_frame(
    socket: &mut dyn BridgeStream,
    chunk: &[u8],
) -> Result<(), String> {
    write_bridge_chunk_frame_with_type(socket, BRIDGE_REQUEST_CHUNK_FRAME_TYPE, chunk).await
}

async fn write_bridge_tunnel_chunk_frame<S: AsyncWrite + Unpin + ?Sized>(
    socket: &mut S,
    chunk: &[u8],
) -> Result<(), String> {
    write_bridge_chunk_frame_with_type(socket, BRIDGE_TUNNEL_CHUNK_FRAME_TYPE, chunk).await
}

async fn write_bridge_chunk_frame_with_type<S: AsyncWrite + Unpin + ?Sized>(
    socket: &mut S,
    frame_type: u8,
    chunk: &[u8],
) -> Result<(), String> {
    let chunk_len = u32::try_from(chunk.len())
        .map_err(|_| "bridge chunk length does not fit u32".to_string())?;
    let payload_len = 6usize
        .checked_add(chunk.len())
        .ok_or_else(|| "bridge frame length overflow".to_string())?;
    if payload_len > MAX_BRIDGE_FRAME_BYTES {
        return Err(format!("bridge frame too large: {payload_len}"));
    }
    let payload_len = u32::try_from(payload_len)
        .map_err(|_| "bridge frame length does not fit u32".to_string())?;

    let header = payload_len.to_be_bytes();
    let mut prefix = [0_u8; 6];
    prefix[0] = BRIDGE_PROTOCOL_VERSION;
    prefix[1] = frame_type;
    prefix[2..6].copy_from_slice(&chunk_len.to_be_bytes());
    if chunk.is_empty() {
        write_all_vectored(socket, &[&header, &prefix])
            .await
            .map_err(|error| format!("write frame payload failed: {error}"))?;
        return Ok(());
    }

    write_all_vectored(socket, &[&header, &prefix, chunk])
        .await
        .map_err(|error| format!("write frame payload failed: {error}"))?;
    Ok(())
}

async fn decode_bridge_response_stream(
    mut connection: BridgeConnection,
    bridge_pool: Arc<BridgePool>,
    websocket_upgrade_requested: bool,
) -> Result<BridgeCallResult, String> {
    let first_frame_type = peek_bridge_frame_type(&connection.read_buffer)?;
    if first_frame_type == BRIDGE_RESPONSE_FRAME_TYPE {
        let legacy_response = decode_bridge_response(&connection.read_buffer)
            .map_err(|error| format!("decode response failed: {error}"))?;
        if websocket_upgrade_requested
            && legacy_response.status == StatusCode::SWITCHING_PROTOCOLS.as_u16()
        {
            return Ok(BridgeCallResult {
                status: legacy_response.status,
                headers: legacy_response.headers,
                body: Body::empty(),
                tunnel_socket: Some(connection),
            });
        }
        bridge_pool.release(connection);
        return Ok(BridgeCallResult {
            status: legacy_response.status,
            headers: legacy_response.headers,
            body: Body::from(legacy_response.body_bytes),
            tunnel_socket: None,
        });
    }
    if first_frame_type != BRIDGE_RESPONSE_START_FRAME_TYPE {
        return Err(format!(
            "decode response failed: invalid bridge response frame type: {first_frame_type}"
        ));
    }

    let (status, headers) = decode_bridge_response_start(&connection.read_buffer)
        .map_err(|error| format!("decode response failed: {error}"))?;

    if !read_bridge_frame_reuse(&mut *connection.stream, &mut connection.read_buffer).await? {
        return Err(
            "decode response failed: bridge closed connection before response end".to_string(),
        );
    }
    let next_frame_type = peek_bridge_frame_type(&connection.read_buffer)
        .map_err(|error| format!("decode response failed: {error}"))?;

    if next_frame_type == BRIDGE_RESPONSE_END_FRAME_TYPE {
        decode_bridge_response_end(&connection.read_buffer)
            .map_err(|error| format!("decode response failed: {error}"))?;
        if websocket_upgrade_requested && status == StatusCode::SWITCHING_PROTOCOLS.as_u16() {
            return Ok(BridgeCallResult {
                status,
                headers,
                body: Body::empty(),
                tunnel_socket: Some(connection),
            });
        }
        bridge_pool.release(connection);
        return Ok(BridgeCallResult {
            status,
            headers,
            body: Body::empty(),
            tunnel_socket: None,
        });
    }
    if next_frame_type != BRIDGE_RESPONSE_CHUNK_FRAME_TYPE {
        return Err(format!(
            "decode response failed: unexpected bridge response frame type: {next_frame_type}"
        ));
    }

    let first_chunk = decode_bridge_response_chunk(&connection.read_buffer)
        .map_err(|error| format!("decode response failed: {error}"))?;

    let (tx, rx) = mpsc::channel::<Result<Bytes, io::Error>>(8);
    if !first_chunk.is_empty() {
        tx.send(Ok(first_chunk))
            .await
            .map_err(|_| "decode response failed: response body stream closed".to_string())?;
    }

    tokio::spawn(async move {
        stream_bridge_response_chunks(connection, tx, bridge_pool).await;
    });

    Ok(BridgeCallResult {
        status,
        headers,
        body: Body::from_stream(ReceiverStream::new(rx)),
        tunnel_socket: None,
    })
}

async fn stream_bridge_response_chunks(
    mut connection: BridgeConnection,
    tx: mpsc::Sender<Result<Bytes, io::Error>>,
    bridge_pool: Arc<BridgePool>,
) {
    let mut total_body_bytes = 0usize;
    loop {
        match read_bridge_frame_reuse(&mut *connection.stream, &mut connection.read_buffer).await {
            Ok(true) => {}
            Ok(false) => {
                let _ = tx
                    .send(Err(io::Error::new(
                        ErrorKind::UnexpectedEof,
                        "bridge closed connection before response end",
                    )))
                    .await;
                return;
            }
            Err(error) => {
                let _ = tx.send(Err(io::Error::new(ErrorKind::Other, error))).await;
                return;
            }
        }

        let frame_type = match peek_bridge_frame_type(&connection.read_buffer) {
            Ok(frame_type) => frame_type,
            Err(error) => {
                let _ = tx
                    .send(Err(io::Error::new(ErrorKind::InvalidData, error)))
                    .await;
                return;
            }
        };

        if frame_type == BRIDGE_RESPONSE_CHUNK_FRAME_TYPE {
            let chunk = match decode_bridge_response_chunk(&connection.read_buffer) {
                Ok(chunk) => chunk,
                Err(error) => {
                    let _ = tx
                        .send(Err(io::Error::new(ErrorKind::InvalidData, error)))
                        .await;
                    return;
                }
            };
            if chunk.is_empty() {
                continue;
            }
            total_body_bytes = match total_body_bytes.checked_add(chunk.len()) {
                Some(value) => value,
                None => {
                    let _ = tx
                        .send(Err(io::Error::new(
                            ErrorKind::InvalidData,
                            "bridge response body length overflow",
                        )))
                        .await;
                    return;
                }
            };
            if total_body_bytes > MAX_PROXY_BODY_BYTES {
                let _ = tx
                    .send(Err(io::Error::new(
                        ErrorKind::InvalidData,
                        format!("bridge response body too large: {total_body_bytes}"),
                    )))
                    .await;
                return;
            }
            if tx.send(Ok(chunk)).await.is_err() {
                return;
            }
            continue;
        }

        if frame_type == BRIDGE_RESPONSE_END_FRAME_TYPE {
            if let Err(error) = decode_bridge_response_end(&connection.read_buffer) {
                let _ = tx
                    .send(Err(io::Error::new(ErrorKind::InvalidData, error)))
                    .await;
                return;
            }
            bridge_pool.release(connection);
            return;
        }

        let _ = tx
            .send(Err(io::Error::new(
                ErrorKind::InvalidData,
                format!("unexpected bridge response frame type: {frame_type}"),
            )))
            .await;
        return;
    }
}

async fn run_websocket_tunnel(
    upgrade: OnUpgrade,
    bridge_socket: BoxBridgeStream,
) -> Result<(), String> {
    let upgraded = upgrade
        .await
        .map_err(|error| format!("frontend upgrade failed: {error}"))?;
    let upgraded = TokioIo::new(upgraded);
    let (mut frontend_reader, mut frontend_writer) = tokio::io::split(upgraded);
    let (mut bridge_reader, mut bridge_writer) = tokio::io::split(bridge_socket);

    let frontend_to_bridge = tokio::spawn(async move {
        let mut buffer = vec![0_u8; BRIDGE_BODY_CHUNK_BYTES];
        loop {
            let read = frontend_reader
                .read(&mut buffer)
                .await
                .map_err(|error| format!("read upgraded frontend stream failed: {error}"))?;
            if read == 0 {
                write_bridge_tunnel_close_frame(&mut bridge_writer).await?;
                return Ok::<(), String>(());
            }
            write_bridge_tunnel_chunk_frame(&mut bridge_writer, &buffer[..read]).await?;
        }
    });

    let bridge_to_frontend = tokio::spawn(async move {
        loop {
            let payload = match read_bridge_frame(&mut bridge_reader).await? {
                Some(payload) => payload,
                None => return Ok::<(), String>(()),
            };
            let frame_type = peek_bridge_frame_type(&payload)?;
            if frame_type == BRIDGE_TUNNEL_CHUNK_FRAME_TYPE {
                let chunk = decode_bridge_tunnel_chunk(&payload)?;
                if !chunk.is_empty() {
                    frontend_writer.write_all(&chunk).await.map_err(|error| {
                        format!("write upgraded frontend stream failed: {error}")
                    })?;
                }
                continue;
            }
            if frame_type == BRIDGE_TUNNEL_CLOSE_FRAME_TYPE {
                decode_bridge_tunnel_close(&payload)?;
                return Ok(());
            }
            return Err(format!("unexpected bridge tunnel frame type: {frame_type}"));
        }
    });

    let (frontend_result, bridge_result) = tokio::join!(frontend_to_bridge, bridge_to_frontend);

    match frontend_result {
        Ok(Ok(())) => {}
        Ok(Err(error)) => return Err(error),
        Err(error) => return Err(format!("frontend-to-bridge tunnel task failed: {error}")),
    }

    match bridge_result {
        Ok(Ok(())) => {}
        Ok(Err(error)) => return Err(error),
        Err(error) => return Err(format!("bridge-to-frontend tunnel task failed: {error}")),
    }

    Ok(())
}

fn decode_bridge_response(payload: &[u8]) -> Result<BridgeResponse, String> {
    let mut reader = BridgeByteReader::new(payload);
    let version = reader.get_u8()?;
    if version != BRIDGE_PROTOCOL_VERSION {
        return Err(format!("unsupported bridge protocol version: {version}"));
    }
    let frame_type = reader.get_u8()?;
    if frame_type != BRIDGE_RESPONSE_FRAME_TYPE {
        return Err(format!("invalid bridge response frame type: {frame_type}"));
    }

    let status = reader.get_u16()?;
    let header_count = reader.get_u32()? as usize;
    let mut headers = Vec::with_capacity(header_count);
    for _ in 0..header_count {
        let name = reader.get_bytes()?;
        let value = reader.get_bytes()?;
        let Ok(header_name) = axum::http::header::HeaderName::from_bytes(name) else {
            continue;
        };
        let Ok(header_value) = axum::http::HeaderValue::from_bytes(value) else {
            continue;
        };
        headers.push((header_name, header_value));
    }
    let body = reader.get_bytes()?;
    reader.ensure_done()?;
    let body_bytes = Bytes::copy_from_slice(body);

    Ok(BridgeResponse {
        status,
        headers,
        body_bytes,
    })
}

fn decode_bridge_response_start(
    payload: &[u8],
) -> Result<
    (
        u16,
        Vec<(axum::http::header::HeaderName, axum::http::HeaderValue)>,
    ),
    String,
> {
    let mut reader = BridgeByteReader::new(payload);
    let version = reader.get_u8()?;
    if version != BRIDGE_PROTOCOL_VERSION {
        return Err(format!("unsupported bridge protocol version: {version}"));
    }
    let frame_type = reader.get_u8()?;
    if frame_type != BRIDGE_RESPONSE_START_FRAME_TYPE {
        return Err(format!(
            "invalid bridge response start frame type: {frame_type}"
        ));
    }
    let status = reader.get_u16()?;
    let header_count = reader.get_u32()? as usize;
    let mut headers = Vec::with_capacity(header_count);
    for _ in 0..header_count {
        let name = reader.get_bytes()?;
        let value = reader.get_bytes()?;
        let Ok(header_name) = axum::http::header::HeaderName::from_bytes(name) else {
            continue;
        };
        let Ok(header_value) = axum::http::HeaderValue::from_bytes(value) else {
            continue;
        };
        headers.push((header_name, header_value));
    }
    reader.ensure_done()?;
    Ok((status, headers))
}

fn decode_bridge_response_chunk(payload: &[u8]) -> Result<Bytes, String> {
    let mut reader = BridgeByteReader::new(payload);
    let version = reader.get_u8()?;
    if version != BRIDGE_PROTOCOL_VERSION {
        return Err(format!("unsupported bridge protocol version: {version}"));
    }
    let frame_type = reader.get_u8()?;
    if frame_type != BRIDGE_RESPONSE_CHUNK_FRAME_TYPE {
        return Err(format!(
            "invalid bridge response chunk frame type: {frame_type}"
        ));
    }
    let chunk = reader.get_bytes()?;
    reader.ensure_done()?;
    Ok(Bytes::copy_from_slice(chunk))
}

fn decode_bridge_response_end(payload: &[u8]) -> Result<(), String> {
    let mut reader = BridgeByteReader::new(payload);
    let version = reader.get_u8()?;
    if version != BRIDGE_PROTOCOL_VERSION {
        return Err(format!("unsupported bridge protocol version: {version}"));
    }
    let frame_type = reader.get_u8()?;
    if frame_type != BRIDGE_RESPONSE_END_FRAME_TYPE {
        return Err(format!(
            "invalid bridge response end frame type: {frame_type}"
        ));
    }
    reader.ensure_done()
}

fn decode_bridge_tunnel_chunk(payload: &[u8]) -> Result<Bytes, String> {
    let mut reader = BridgeByteReader::new(payload);
    let version = reader.get_u8()?;
    if version != BRIDGE_PROTOCOL_VERSION {
        return Err(format!("unsupported bridge protocol version: {version}"));
    }
    let frame_type = reader.get_u8()?;
    if frame_type != BRIDGE_TUNNEL_CHUNK_FRAME_TYPE {
        return Err(format!(
            "invalid bridge tunnel chunk frame type: {frame_type}"
        ));
    }
    let chunk = reader.get_bytes()?;
    reader.ensure_done()?;
    Ok(Bytes::copy_from_slice(chunk))
}

fn decode_bridge_tunnel_close(payload: &[u8]) -> Result<(), String> {
    let mut reader = BridgeByteReader::new(payload);
    let version = reader.get_u8()?;
    if version != BRIDGE_PROTOCOL_VERSION {
        return Err(format!("unsupported bridge protocol version: {version}"));
    }
    let frame_type = reader.get_u8()?;
    if frame_type != BRIDGE_TUNNEL_CLOSE_FRAME_TYPE {
        return Err(format!(
            "invalid bridge tunnel close frame type: {frame_type}"
        ));
    }
    reader.ensure_done()
}

fn peek_bridge_frame_type(payload: &[u8]) -> Result<u8, String> {
    if payload.len() < 2 {
        return Err("truncated bridge payload".to_string());
    }
    let version = payload[0];
    if version != BRIDGE_PROTOCOL_VERSION {
        return Err(format!("unsupported bridge protocol version: {version}"));
    }
    Ok(payload[1])
}

async fn write_bridge_frame<S: AsyncWrite + Unpin + ?Sized>(
    socket: &mut S,
    payload: &[u8],
) -> Result<(), String> {
    if payload.len() > MAX_BRIDGE_FRAME_BYTES {
        return Err(format!("bridge frame too large: {}", payload.len()));
    }
    let payload_len = u32::try_from(payload.len())
        .map_err(|_| "bridge frame length does not fit u32".to_string())?;
    let header = payload_len.to_be_bytes();
    if payload.is_empty() {
        socket
            .write_all(&header)
            .await
            .map_err(|error| format!("write frame header failed: {error}"))?;
        return Ok(());
    }
    write_all_vectored(socket, &[&header, payload])
        .await
        .map_err(|error| format!("write frame payload failed: {error}"))?;
    Ok(())
}

async fn write_bridge_tunnel_close_frame<S: AsyncWrite + Unpin + ?Sized>(
    socket: &mut S,
) -> Result<(), String> {
    let payload = [BRIDGE_PROTOCOL_VERSION, BRIDGE_TUNNEL_CLOSE_FRAME_TYPE];
    write_bridge_frame(socket, &payload).await
}

async fn write_all_vectored<S: AsyncWrite + Unpin + ?Sized>(
    socket: &mut S,
    buffers: &[&[u8]],
) -> io::Result<()> {
    let mut index = 0usize;
    let mut offset = 0usize;

    while index < buffers.len() {
        while index < buffers.len() && offset == buffers[index].len() {
            index += 1;
            offset = 0;
        }
        if index >= buffers.len() {
            break;
        }

        let remaining_buffers = buffers.len() - index;
        let written = if remaining_buffers <= 3 {
            let mut io_slices = [IoSlice::new(&[]), IoSlice::new(&[]), IoSlice::new(&[])];
            io_slices[0] = IoSlice::new(&buffers[index][offset..]);
            let mut slice_len = 1usize;
            if remaining_buffers >= 2 {
                io_slices[1] = IoSlice::new(buffers[index + 1]);
                slice_len = 2;
            }
            if remaining_buffers >= 3 {
                io_slices[2] = IoSlice::new(buffers[index + 2]);
                slice_len = 3;
            }
            socket.write_vectored(&io_slices[..slice_len]).await?
        } else {
            let mut io_slices = Vec::with_capacity(remaining_buffers);
            io_slices.push(IoSlice::new(&buffers[index][offset..]));
            for buffer in &buffers[(index + 1)..] {
                io_slices.push(IoSlice::new(buffer));
            }
            socket.write_vectored(&io_slices).await?
        };
        if written == 0 {
            return Err(io::Error::new(
                ErrorKind::WriteZero,
                "failed to write bridge frame bytes",
            ));
        }

        let mut remaining = written;
        while index < buffers.len() && remaining > 0 {
            let available = buffers[index].len() - offset;
            if remaining < available {
                offset += remaining;
                remaining = 0;
            } else {
                remaining -= available;
                index += 1;
                offset = 0;
            }
        }
    }

    Ok(())
}

async fn read_bridge_frame<S: AsyncRead + Unpin + ?Sized>(
    socket: &mut S,
) -> Result<Option<Vec<u8>>, String> {
    let mut payload = Vec::new();
    let has_frame = read_bridge_frame_reuse(socket, &mut payload).await?;
    if !has_frame {
        return Ok(None);
    }
    Ok(Some(payload))
}

async fn read_bridge_frame_reuse<S: AsyncRead + Unpin + ?Sized>(
    socket: &mut S,
    payload: &mut Vec<u8>,
) -> Result<bool, String> {
    let mut header = [0_u8; 4];
    let mut read = 0;
    while read < header.len() {
        let n = socket
            .read(&mut header[read..])
            .await
            .map_err(|error| format!("read frame header failed: {error}"))?;
        if n == 0 {
            if read == 0 {
                return Ok(false);
            }
            return Err("bridge closed connection while reading frame header".to_string());
        }
        read += n;
    }

    let payload_len = u32::from_be_bytes(header) as usize;
    if payload_len > MAX_BRIDGE_FRAME_BYTES {
        return Err(format!("bridge frame too large: {payload_len}"));
    }

    payload.resize(payload_len, 0);
    let mut read = 0;
    while read < payload_len {
        let n = socket
            .read(&mut payload[read..payload_len])
            .await
            .map_err(|error| format!("read frame payload failed: {error}"))?;
        if n == 0 {
            return Err("bridge stream ended before response payload".to_string());
        }
        read += n;
    }

    Ok(true)
}

struct BridgeByteWriter {
    bytes: Vec<u8>,
}

impl BridgeByteWriter {
    fn new() -> Self {
        Self { bytes: Vec::new() }
    }

    fn reserve(&mut self, additional: usize) {
        self.bytes.reserve(additional);
    }

    fn reserve_u32(&mut self) -> usize {
        let pos = self.bytes.len();
        self.bytes.extend_from_slice(&0_u32.to_be_bytes());
        pos
    }

    fn patch_u32(&mut self, pos: usize, value: u32) {
        self.bytes[pos..pos + 4].copy_from_slice(&value.to_be_bytes());
    }

    fn into_inner(self) -> Vec<u8> {
        self.bytes
    }

    fn put_u8(&mut self, value: u8) {
        self.bytes.push(value);
    }

    fn put_u32(&mut self, value: u32) {
        self.bytes.extend_from_slice(&value.to_be_bytes());
    }

    fn put_string(&mut self, value: &str) -> Result<(), String> {
        self.put_bytes(value.as_bytes())
    }

    fn put_bytes(&mut self, bytes: &[u8]) -> Result<(), String> {
        let len = u32::try_from(bytes.len())
            .map_err(|_| "bridge field length does not fit u32".to_string())?;
        self.put_u32(len);
        self.bytes.extend_from_slice(bytes);
        Ok(())
    }
}

struct BridgeByteReader<'a> {
    bytes: &'a [u8],
    offset: usize,
}

impl<'a> BridgeByteReader<'a> {
    fn new(bytes: &'a [u8]) -> Self {
        Self { bytes, offset: 0 }
    }

    fn get_u8(&mut self) -> Result<u8, String> {
        let bytes = self.get_exact(1)?;
        Ok(bytes[0])
    }

    fn get_u16(&mut self) -> Result<u16, String> {
        let bytes = self.get_exact(2)?;
        Ok(u16::from_be_bytes([bytes[0], bytes[1]]))
    }

    fn get_u32(&mut self) -> Result<u32, String> {
        let bytes = self.get_exact(4)?;
        Ok(u32::from_be_bytes([bytes[0], bytes[1], bytes[2], bytes[3]]))
    }

    fn get_bytes(&mut self) -> Result<&'a [u8], String> {
        let (start, length) = self.get_bytes_range()?;
        Ok(&self.bytes[start..start + length])
    }

    fn get_bytes_range(&mut self) -> Result<(usize, usize), String> {
        let length = self.get_u32()? as usize;
        if self.offset + length > self.bytes.len() {
            return Err("truncated bridge payload".to_string());
        }
        let start = self.offset;
        self.offset += length;
        Ok((start, length))
    }

    fn ensure_done(&self) -> Result<(), String> {
        if self.offset == self.bytes.len() {
            return Ok(());
        }
        Err(format!(
            "unexpected trailing bridge payload bytes: {}",
            self.bytes.len() - self.offset
        ))
    }

    fn get_exact(&mut self, len: usize) -> Result<&'a [u8], String> {
        if self.offset + len > self.bytes.len() {
            return Err("truncated bridge payload".to_string());
        }
        let start = self.offset;
        self.offset += len;
        Ok(&self.bytes[start..start + len])
    }
}

fn http_version_to_protocol(version: Version) -> &'static str {
    match version {
        Version::HTTP_09 => "0.9",
        Version::HTTP_10 => "1.0",
        Version::HTTP_11 => "1.1",
        Version::HTTP_2 => "2",
        Version::HTTP_3 => "3",
        _ => "1.1",
    }
}

fn split_path_and_query_ref(path_and_query: &str) -> (&str, &str) {
    match path_and_query.split_once('?') {
        Some((path, query)) => (path, query),
        None => (path_and_query, ""),
    }
}

fn is_websocket_upgrade(headers: &axum::http::HeaderMap) -> bool {
    let has_upgrade = headers
        .get("connection")
        .and_then(|value| value.to_str().ok())
        .map(|value| value.to_ascii_lowercase().contains("upgrade"))
        .unwrap_or(false);
    let websocket_upgrade = headers
        .get("upgrade")
        .and_then(|value| value.to_str().ok())
        .map(|value| value.eq_ignore_ascii_case("websocket"))
        .unwrap_or(false);
    has_upgrade && websocket_upgrade
}

fn text_response(status: StatusCode, message: impl Into<String>) -> Response<Body> {
    let mut response = Response::new(Body::from(message.into()));
    *response.status_mut() = status;
    response
}

fn c_string_to_string(value: *const c_char) -> Option<String> {
    if value.is_null() {
        return None;
    }
    let value = unsafe { CStr::from_ptr(value) };
    value.to_str().ok().map(ToString::to_string)
}

#[cfg(test)]
mod tests {
    use super::{BridgeEndpoint, BridgePool};
    use std::time::Duration;
    use tokio::net::TcpListener;

    #[tokio::test]
    async fn bridge_pool_acquires_new_and_reused_sockets() {
        let listener = TcpListener::bind("127.0.0.1:0")
            .await
            .expect("bind listener");
        let addr = listener.local_addr().expect("listener local addr");
        let accept_task = tokio::spawn(async move {
            let (_stream, _) = listener.accept().await.expect("accept socket");
            tokio::time::sleep(Duration::from_millis(50)).await;
        });

        let pool = BridgePool::new(BridgeEndpoint::Tcp(addr.to_string()), 1);
        let stream = pool.acquire().await.expect("acquire fresh socket");
        pool.release(stream);

        let stream = pool.acquire().await.expect("acquire reused socket");
        drop(stream);

        accept_task.await.expect("accept task should complete");
    }
}
