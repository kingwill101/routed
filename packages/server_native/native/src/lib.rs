//! Native Rust transport runtime for `package:server_native`.
//!
//! This crate exposes a C ABI used by Dart FFI to boot and control a Rust HTTP
//! front server. The front server:
//! - accepts inbound HTTP/1.1, HTTP/2, and optional HTTP/3 traffic,
//! - translates requests into bridge frames,
//! - forwards those frames to Dart, and
//! - relays bridge responses back to network clients.
//!
//! The crate intentionally keeps the FFI surface small:
//! - `server_native_transport_version`
//! - `server_native_start_proxy_server`
//! - `server_native_stop_proxy_server`
//! - `server_native_push_direct_response_frame`
//! - `server_native_complete_direct_request`

use std::collections::HashMap;
use std::ffi::{c_char, c_void, CStr};
use std::fs::File;
use std::io::{self, BufReader, ErrorKind, IoSlice};
use std::net::SocketAddr;
use std::path::PathBuf;
use std::ptr::null_mut;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use std::thread;
use std::time::Duration;

use axum::body::{Body, BodyDataStream, Bytes, HttpBody};
use axum::extract::State;
use axum::http::{HeaderMap, Request, Response, StatusCode, Version};
use axum::routing::any;
use axum::Router;
use hyper::server::conn::http1;
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
use tokio::time;
use tokio_rustls::rustls::server::WebPkiClientVerifier;
use tokio_rustls::rustls::{RootCertStore, ServerConfig};
use tokio_rustls::TlsAcceptor;
use tokio_stream::{wrappers::ReceiverStream, StreamExt};

include!("tls_support.rs");
include!("bridge_protocol.rs");

// ---- Transport and protocol limits -----------------------------------------
//
// These constants define hard safety limits for inbound/outbound bridge and
// HTTP body handling. They are used to:
// - bound per-request memory growth,
// - avoid oversized frame allocations, and
// - keep backpressure behavior predictable across Rust <-> Dart.
const MAX_PROXY_BODY_BYTES: usize = 32 * 1024 * 1024;
const MAX_BRIDGE_FRAME_BYTES: usize = 64 * 1024 * 1024;
const BRIDGE_BODY_CHUNK_BYTES: usize = 64 * 1024;
const BRIDGE_COALESCE_WRITE_THRESHOLD_BYTES: usize = 4 * 1024;

// ---- Bridge protocol wire format -------------------------------------------
//
// All bridge frames are prefixed with:
// - u32 BE payload length
// followed by a payload starting with:
// - u8 protocol version
// - u8 frame type
//
// The *_TOKENIZED variants encode common header names as u16 tokens to reduce
// frame size and UTF-8 parsing overhead on hot paths.
const BRIDGE_PROTOCOL_VERSION: u8 = 1;
const BRIDGE_PROTOCOL_VERSION_LEGACY: u8 = 1;
const _BRIDGE_REQUEST_FRAME_TYPE: u8 = 1; // legacy single-frame request
const BRIDGE_RESPONSE_FRAME_TYPE: u8 = 2; // legacy single-frame response
const _BRIDGE_REQUEST_START_FRAME_TYPE: u8 = 3;
const BRIDGE_REQUEST_CHUNK_FRAME_TYPE: u8 = 4;
const BRIDGE_REQUEST_END_FRAME_TYPE: u8 = 5;
const BRIDGE_RESPONSE_START_FRAME_TYPE: u8 = 6;
const BRIDGE_RESPONSE_CHUNK_FRAME_TYPE: u8 = 7;
const BRIDGE_RESPONSE_END_FRAME_TYPE: u8 = 8;
const BRIDGE_TUNNEL_CHUNK_FRAME_TYPE: u8 = 9;
const BRIDGE_TUNNEL_CLOSE_FRAME_TYPE: u8 = 10;
const BRIDGE_REQUEST_FRAME_TYPE_TOKENIZED: u8 = 11;
const BRIDGE_RESPONSE_FRAME_TYPE_TOKENIZED: u8 = 12;
const BRIDGE_REQUEST_START_FRAME_TYPE_TOKENIZED: u8 = 13;
const BRIDGE_RESPONSE_START_FRAME_TYPE_TOKENIZED: u8 = 14;
const BRIDGE_HEADER_NAME_LITERAL_TOKEN: u16 = 0xFFFF;
const BRIDGE_BACKEND_KIND_TCP: u8 = 0;
const BRIDGE_BACKEND_KIND_UNIX: u8 = 1;

// ---- Benchmark modes --------------------------------------------------------
const BENCHMARK_MODE_NONE: u8 = 0;
const BENCHMARK_MODE_STATIC_OK: u8 = 1;
const BENCHMARK_MODE_STATIC_OK_SERVER_NATIVE_DIRECT_SHAPE: u8 = 2;
const BENCHMARK_STATIC_OK_BODY: &[u8] = br#"{"ok":true,"label":"server_native_direct"}"#;
const BENCHMARK_SERVER_NATIVE_DIRECT_SHAPE_BODY: &[u8] =
    br#"{"ok":true,"label":"server_native_direct"}"#;

/// Max time to wait for direct-callback response frames from Dart.
const DIRECT_REQUEST_TIMEOUT: Duration = Duration::from_secs(30);

/// C callback signature used by direct request mode.
///
/// Rust invokes this callback with:
/// - `request_id`: correlation identifier unique per in-flight request,
/// - `payload`: pointer to encoded bridge frame bytes,
/// - `payload_len`: payload length in bytes.
///
/// Dart must treat `payload` as read-only and copy the bytes before returning.
type DirectRequestCallback = extern "C" fn(request_id: u64, payload: *const u8, payload_len: u64);

#[repr(C)]
/// C-compatible proxy boot configuration consumed by
/// [`server_native_start_proxy_server`].
///
/// All `*const c_char` fields are expected to be valid UTF-8 C strings or
/// null pointers where explicitly optional.
pub struct ServerNativeProxyConfig {
    /// Public bind host (for example `127.0.0.1`, `::1`, `0.0.0.0`).
    pub host: *const c_char,
    /// Public bind port. `0` requests an ephemeral OS-assigned port.
    pub port: u16,
    /// Bridge backend host (used when `backend_kind == BRIDGE_BACKEND_KIND_TCP`).
    pub backend_host: *const c_char,
    /// Bridge backend port (used when `backend_kind == BRIDGE_BACKEND_KIND_TCP`).
    pub backend_port: u16,
    /// Backend kind discriminator:
    /// - [`BRIDGE_BACKEND_KIND_TCP`]
    /// - [`BRIDGE_BACKEND_KIND_UNIX`]
    pub backend_kind: u8,
    /// Unix domain socket path (used when `backend_kind == BRIDGE_BACKEND_KIND_UNIX`).
    pub backend_path: *const c_char,
    /// Optional listen backlog override. `0` uses a default.
    pub backlog: u32,
    /// Whether IPv6 sockets should be v6-only (`0` false, non-zero true).
    pub v6_only: u8,
    /// Whether socket sharing/reuse is enabled (`0` false, non-zero true).
    pub shared: u8,
    /// Whether to request client certificates in TLS mode (`0` false, non-zero true).
    pub request_client_certificate: u8,
    /// Whether HTTP/2 should be enabled (`0` false, non-zero true).
    pub http2: u8,
    /// Whether HTTP/3 should be enabled when TLS is configured (`0` false, non-zero true).
    pub http3: u8,
    /// Optional TLS certificate PEM path.
    pub tls_cert_path: *const c_char,
    /// Optional TLS private key PEM path.
    pub tls_key_path: *const c_char,
    /// Optional private key password for encrypted PKCS#8 keys.
    pub tls_cert_password: *const c_char,
    /// Benchmark behavior selector.
    pub benchmark_mode: u8,
    /// Optional direct request callback pointer.
    pub direct_request_callback: *const c_void,
}

#[derive(Clone)]
struct ProxyState {
    bridge_pool: Arc<BridgePool>,
    benchmark_mode: u8,
    direct_bridge: Option<Arc<DirectRequestBridge>>,
}

#[derive(Clone)]
/// TLS file-path configuration resolved from C ABI input.
struct ProxyTlsConfig {
    cert_path: String,
    key_path: String,
    cert_password: Option<String>,
}

/// Opaque server handle returned to Dart through FFI.
///
/// The pointer returned by [`server_native_start_proxy_server`] must later be
/// passed to [`server_native_stop_proxy_server`] exactly once.
pub struct ProxyServerHandle {
    shutdown_tx: Option<oneshot::Sender<()>>,
    join_handle: Option<thread::JoinHandle<()>>,
    direct_bridge: Option<Arc<DirectRequestBridge>>,
}

/// Registry for in-flight direct-callback requests.
struct DirectRequestBridge {
    callback: DirectRequestCallback,
    next_request_id: AtomicU64,
    pending: Mutex<HashMap<u64, PendingDirectRequest>>,
}

/// Per-request direct-callback state.
struct PendingDirectRequest {
    inflight_payloads: Vec<Vec<u8>>,
    response_tx: mpsc::UnboundedSender<Vec<u8>>,
}

/// Connection pool for bridge sockets between Rust and Dart runtime.
struct BridgePool {
    endpoint: BridgeEndpoint,
    max_idle: usize,
    hot: Mutex<Option<BridgeConnection>>,
    idle: Mutex<Vec<BridgeConnection>>,
}

trait BridgeStream: AsyncRead + AsyncWrite + Unpin + Send {}
impl<T> BridgeStream for T where T: AsyncRead + AsyncWrite + Unpin + Send {}
type BoxBridgeStream = Box<dyn BridgeStream>;

/// One pooled bridge stream plus reusable read buffer.
struct BridgeConnection {
    stream: BoxBridgeStream,
    read_buffer: Vec<u8>,
}

#[derive(Clone)]
/// Bridge backend endpoint (`tcp://` or `unix://`).
enum BridgeEndpoint {
    Tcp(String),
    #[cfg(unix)]
    Unix(PathBuf),
    #[cfg(not(unix))]
    Unix(String),
}

impl BridgePool {
    /// Creates a new bridge connection pool.
    ///
    /// `max_idle` controls how many idle connections are retained in the
    /// secondary idle list (in addition to the single-slot `hot` fast path).
    fn new(endpoint: BridgeEndpoint, max_idle: usize) -> Self {
        Self {
            endpoint,
            max_idle,
            hot: Mutex::new(None),
            idle: Mutex::new(Vec::new()),
        }
    }

    /// Acquires a bridge connection, preferring warm pooled connections.
    ///
    /// Acquisition order:
    /// 1. hot slot
    /// 2. idle vector
    /// 3. establish a new socket
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

    /// Establishes a fresh bridge socket to the configured backend endpoint.
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

    /// Returns a connection to the pool for reuse.
    ///
    /// The read buffer is either:
    /// - reset to a small default capacity if it grew too large, or
    /// - cleared in place for fast reuse.
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

/// Borrowed request view used during request-to-bridge encoding.
struct BridgeRequestRef<'a> {
    method: &'a str,
    scheme: &'a str,
    authority: &'a str,
    path: &'a str,
    query: &'a str,
    protocol: &'a str,
    headers: &'a HeaderMap,
}

/// Decoded single-frame bridge response.
struct BridgeResponse {
    status: u16,
    headers: Vec<(axum::http::header::HeaderName, axum::http::HeaderValue)>,
    body_bytes: Bytes,
}

/// Bridge call result returned to HTTP serving path.
struct BridgeCallResult {
    status: u16,
    headers: Vec<(axum::http::header::HeaderName, axum::http::HeaderValue)>,
    body: Body,
    tunnel_socket: Option<BridgeConnection>,
}

#[no_mangle]
/// Returns the native transport ABI version expected by Dart bindings.
pub extern "C" fn server_native_transport_version() -> i32 {
    1
}

#[no_mangle]
/// Starts the proxy server and returns an opaque handle.
///
/// On success:
/// - writes the effective bound port to `out_port`,
/// - returns a non-null pointer that must be stopped with
///   [`server_native_stop_proxy_server`].
///
/// On failure:
/// - returns null,
/// - emits error details to stderr.
///
/// # Safety
///
/// `config` and `out_port` must be valid non-null pointers for the duration
/// of this call. String pointers inside `config` must either be null (for
/// optional fields) or point to valid NUL-terminated UTF-8 strings.
pub extern "C" fn server_native_start_proxy_server(
    config: *const ServerNativeProxyConfig,
    out_port: *mut u16,
) -> *mut ProxyServerHandle {
    if config.is_null() || out_port.is_null() {
        eprintln!("[server_native] invalid start parameters");
        return null_mut();
    }

    let config = unsafe { &*config };
    let host = match c_string_to_string(config.host) {
        Some(value) if !value.is_empty() => value,
        _ => {
            eprintln!("[server_native] invalid host");
            return null_mut();
        }
    };
    let port = config.port;
    let bridge_endpoint = match config.backend_kind {
        BRIDGE_BACKEND_KIND_TCP => {
            let bridge_host = match c_string_to_string(config.backend_host) {
                Some(value) if !value.is_empty() => value,
                _ => {
                    eprintln!("[server_native] invalid backend_host");
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
                    eprintln!("[server_native] invalid backend_path");
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
            eprintln!("[server_native] invalid backend_kind: {backend_kind}");
            return null_mut();
        }
    };
    let enable_http2 = config.http2 != 0;
    let enable_http3 = config.http3 != 0;
    let backlog = config.backlog;
    let v6_only = config.v6_only != 0;
    let shared = config.shared != 0;
    let request_client_certificate = config.request_client_certificate != 0;
    let benchmark_mode = config.benchmark_mode;
    if benchmark_mode != BENCHMARK_MODE_NONE
        && benchmark_mode != BENCHMARK_MODE_STATIC_OK
        && benchmark_mode != BENCHMARK_MODE_STATIC_OK_SERVER_NATIVE_DIRECT_SHAPE
    {
        eprintln!("[server_native] invalid benchmark_mode: {benchmark_mode}");
        return null_mut();
    }
    let tls_cert_path = c_string_to_string(config.tls_cert_path).filter(|value| !value.is_empty());
    let tls_key_path = c_string_to_string(config.tls_key_path).filter(|value| !value.is_empty());
    let tls_cert_password =
        c_string_to_string(config.tls_cert_password).filter(|value| !value.is_empty());
    let direct_callback = if config.direct_request_callback.is_null() {
        None
    } else {
        Some(unsafe {
            std::mem::transmute::<*const c_void, DirectRequestCallback>(
                config.direct_request_callback,
            )
        })
    };
    let direct_bridge = direct_callback.map(|callback| {
        Arc::new(DirectRequestBridge {
            callback,
            next_request_id: AtomicU64::new(1),
            pending: Mutex::new(HashMap::new()),
        })
    });
    let tls_config = match (tls_cert_path, tls_key_path) {
        (None, None) => None,
        (Some(cert_path), Some(key_path)) => Some(ProxyTlsConfig {
            cert_path,
            key_path,
            cert_password: tls_cert_password,
        }),
        _ => {
            eprintln!(
                "[server_native] invalid tls settings: both tls_cert_path and tls_key_path are required"
            );
            return null_mut();
        }
    };

    let (startup_tx, startup_rx) = std::sync::mpsc::channel::<Result<u16, String>>();
    let (shutdown_tx, shutdown_rx) = oneshot::channel::<()>();

    let runtime_direct_bridge = direct_bridge.clone();
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
                direct_bridge: runtime_direct_bridge,
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
                        enable_http2,
                        enable_http3,
                        request_client_certificate,
                    )
                    .await
                }
                None => {
                    if request_client_certificate {
                        eprintln!(
                            "[server_native] request_client_certificate requires tls cert/key; option ignored"
                        );
                    }
                    if enable_http3 {
                        eprintln!(
                            "[server_native] http3 requested without tls cert/key; running http1{} only",
                            if enable_http2 { "/http2" } else { "" }
                        );
                    }
                    run_plain_proxy(listener, app, shutdown_rx, enable_http2).await
                }
            };

            if let Err(error) = result {
                eprintln!("[server_native] proxy server error: {error}");
            }
        });
    });

    let actual_port = match startup_rx.recv_timeout(Duration::from_secs(10)) {
        Ok(Ok(port)) => port,
        Ok(Err(error)) => {
            eprintln!("[server_native] startup failed: {error}");
            let _ = join_handle.join();
            return null_mut();
        }
        Err(error) => {
            eprintln!("[server_native] startup timeout/error: {error}");
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
        direct_bridge,
    };
    Box::into_raw(Box::new(handle))
}

#[no_mangle]
/// Stops a proxy server previously created by [`server_native_start_proxy_server`].
///
/// This function consumes the handle pointer and must not be called twice with
/// the same pointer.
///
/// # Safety
///
/// `handle` must be either null or a pointer returned by
/// [`server_native_start_proxy_server`] that has not yet been freed.
pub extern "C" fn server_native_stop_proxy_server(handle: *mut ProxyServerHandle) {
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

#[no_mangle]
/// Pushes a direct-callback response frame for a pending request.
///
/// Returns `1` on success, `0` when the request is unknown or arguments are
/// invalid.
///
/// # Safety
///
/// `handle` must be a valid pointer returned by
/// [`server_native_start_proxy_server`]. `response_payload` must reference
/// `response_payload_len` readable bytes for the duration of this call.
pub extern "C" fn server_native_push_direct_response_frame(
    handle: *mut ProxyServerHandle,
    request_id: u64,
    response_payload: *const u8,
    response_payload_len: u64,
) -> u8 {
    if handle.is_null() || response_payload.is_null() {
        return 0;
    }

    let handle_ref = unsafe { &*handle };
    let Some(direct_bridge) = handle_ref.direct_bridge.as_ref() else {
        return 0;
    };

    let Ok(response_payload_len) = usize::try_from(response_payload_len) else {
        return 0;
    };
    let response = unsafe { std::slice::from_raw_parts(response_payload, response_payload_len) };
    let response_tx = {
        let pending = direct_bridge.pending.lock();
        let Some(entry) = pending.get(&request_id) else {
            return 0;
        };
        entry.response_tx.clone()
    };
    if response_tx.send(response.to_vec()).is_err() {
        return 0;
    }
    1
}

#[no_mangle]
/// Compatibility alias for [`server_native_push_direct_response_frame`].
///
/// # Safety
///
/// Same safety contract as [`server_native_push_direct_response_frame`].
pub extern "C" fn server_native_complete_direct_request(
    handle: *mut ProxyServerHandle,
    request_id: u64,
    response_payload: *const u8,
    response_payload_len: u64,
) -> u8 {
    server_native_push_direct_response_frame(
        handle,
        request_id,
        response_payload,
        response_payload_len,
    )
}

/// Resolves bind target and creates a TCP listener with requested options.
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

/// Low-level socket bind helper used by [`bind_tcp_listener`].
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

/// Runs plaintext serving loop over TCP.
///
/// Supports HTTP/1.1 always, and HTTP/2 when `enable_http2` is true.
async fn run_plain_proxy(
    listener: TcpListener,
    app: Router,
    mut shutdown_rx: oneshot::Receiver<()>,
    enable_http2: bool,
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
                        eprintln!("[server_native] plain accept failed: {error}");
                        continue;
                    }
                };
                if let Err(error) = stream.set_nodelay(true) {
                    eprintln!("[server_native] set_nodelay failed: {error}");
                }
                let app = app.clone();
                let enable_http2 = enable_http2;
                connections.spawn(async move {
                    let service = TowerToHyperService::new(app);
                    if enable_http2 {
                        let builder = AutoBuilder::new(TokioExecutor::new());
                        builder
                            .serve_connection_with_upgrades(TokioIo::new(stream), service)
                            .await
                            .map_err(|error| format!("plain connection failed: {error}"))
                    } else {
                        let builder = http1::Builder::new();
                        builder
                            .serve_connection(TokioIo::new(stream), service)
                            .with_upgrades()
                            .await
                            .map_err(|error| format!("plain h1 connection failed: {error}"))
                    }
                });
            }
        }
    }

    while let Some(result) = connections.join_next().await {
        match result {
            Ok(Ok(())) => {}
            Ok(Err(error)) => eprintln!("[server_native] {error}"),
            Err(error) => eprintln!("[server_native] plain task join failed: {error}"),
        }
    }

    Ok(())
}

/// Runs TLS serving loop and optionally HTTP/3 endpoint.
async fn run_tls_proxy(
    listener: TcpListener,
    app: Router,
    mut shutdown_rx: oneshot::Receiver<()>,
    tls_config: ProxyTlsConfig,
    enable_http2: bool,
    enable_http3: bool,
    request_client_certificate: bool,
) -> Result<(), String> {
    ensure_rustls_crypto_provider()?;
    let tls = load_tls_server_config(
        &tls_config.cert_path,
        &tls_config.key_path,
        tls_config.cert_password.as_deref(),
        enable_http2,
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
                    "[server_native] http3 endpoint enabled on https://{}:{}",
                    local_addr.ip(),
                    local_addr.port()
                );
                Some(endpoint)
            }
            Err(error) => {
                eprintln!(
                    "[server_native] http3 setup failed; continuing with http1{} only: {error}",
                    if enable_http2 { "/http2" } else { "" }
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
                            eprintln!("[server_native] tls accept failed: {error}");
                            continue;
                        }
                    };
                    let acceptor = acceptor.clone();
                    let app = app.clone();
                    let enable_http2 = enable_http2;
                    connections.spawn(async move {
                        let tls_stream = acceptor
                            .accept(stream)
                            .await
                            .map_err(|error| format!("tls handshake failed: {error}"))?;
                        let service = TowerToHyperService::new(app);
                        if enable_http2 {
                            let builder = AutoBuilder::new(TokioExecutor::new());
                            builder
                                .serve_connection_with_upgrades(TokioIo::new(tls_stream), service)
                                .await
                                .map_err(|error| format!("tls connection failed: {error}"))
                        } else {
                            let builder = http1::Builder::new();
                            builder
                                .serve_connection(TokioIo::new(tls_stream), service)
                                .with_upgrades()
                                .await
                                .map_err(|error| format!("tls h1 connection failed: {error}"))
                        }
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
                            eprintln!("[server_native] tls accept failed: {error}");
                            continue;
                        }
                    };
                    let acceptor = acceptor.clone();
                    let app = app.clone();
                    let enable_http2 = enable_http2;
                    connections.spawn(async move {
                        let tls_stream = acceptor
                            .accept(stream)
                            .await
                            .map_err(|error| format!("tls handshake failed: {error}"))?;
                        let service = TowerToHyperService::new(app);
                        if enable_http2 {
                            let builder = AutoBuilder::new(TokioExecutor::new());
                            builder
                                .serve_connection_with_upgrades(TokioIo::new(tls_stream), service)
                                .await
                                .map_err(|error| format!("tls connection failed: {error}"))
                        } else {
                            let builder = http1::Builder::new();
                            builder
                                .serve_connection(TokioIo::new(tls_stream), service)
                                .with_upgrades()
                                .await
                                .map_err(|error| format!("tls h1 connection failed: {error}"))
                        }
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
            Ok(Err(error)) => eprintln!("[server_native] {error}"),
            Err(error) => eprintln!("[server_native] tls task join failed: {error}"),
        }
    }

    Ok(())
}

/// Main request handler used by Axum for all incoming HTTP requests.
///
/// It chooses one of three execution modes:
/// - static benchmark response
/// - direct callback mode
/// - bridge socket mode
async fn proxy_request(State(state): State<ProxyState>, request: Request<Body>) -> Response<Body> {
    if state.benchmark_mode == BENCHMARK_MODE_STATIC_OK {
        return benchmark_static_ok_response();
    }
    if state.benchmark_mode == BENCHMARK_MODE_STATIC_OK_SERVER_NATIVE_DIRECT_SHAPE {
        return benchmark_static_response(BENCHMARK_SERVER_NATIVE_DIRECT_SHAPE_BODY);
    }

    let (mut parts, body) = request.into_parts();
    let websocket_upgrade_requested = is_websocket_upgrade(&parts.headers);
    let mut upgrade = if websocket_upgrade_requested {
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

    if let Some(direct_bridge) = state.direct_bridge.as_ref() {
        let request_body_known_empty = body.size_hint().exact() == Some(0);
        let body_stream = body.into_data_stream();
        return match call_direct_bridge_request(
            direct_bridge,
            bridge_request,
            body_stream,
            request_body_known_empty,
            websocket_upgrade_requested,
            upgrade.take(),
        )
        .await
        {
            Ok(response) => response,
            Err(error) => text_response(
                StatusCode::BAD_GATEWAY,
                format!("direct bridge call failed: {error}"),
            ),
        };
    }

    let request_body_known_empty = body.size_hint().exact() == Some(0);
    let body_stream = body.into_data_stream();

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
                eprintln!("[server_native] websocket tunnel error: {error}");
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

/// Convenience benchmark response for native-direct transport baseline.
fn benchmark_static_ok_response() -> Response<Body> {
    benchmark_static_response(BENCHMARK_STATIC_OK_BODY)
}

/// Convenience benchmark response shape that mirrors server_native direct path.
fn benchmark_static_response(body: &'static [u8]) -> Response<Body> {
    let mut response = Response::new(Body::from(body));
    *response.status_mut() = StatusCode::OK;
    response.headers_mut().insert(
        axum::http::header::CONTENT_TYPE,
        axum::http::HeaderValue::from_static("application/json"),
    );
    response
}

/// Forwards a request through the direct callback bridge.
async fn call_direct_bridge_request(
    direct_bridge: &Arc<DirectRequestBridge>,
    request: BridgeRequestRef<'_>,
    mut body_stream: BodyDataStream,
    request_body_known_empty: bool,
    websocket_upgrade_requested: bool,
    upgrade: Option<OnUpgrade>,
) -> Result<Response<Body>, String> {
    let request_id = direct_bridge
        .next_request_id
        .fetch_add(1, Ordering::Relaxed);
    let (response_tx, mut response_rx) = mpsc::unbounded_channel::<Vec<u8>>();

    direct_bridge.pending.lock().insert(
        request_id,
        PendingDirectRequest {
            inflight_payloads: Vec::new(),
            response_tx,
        },
    );

    if let Err(error) = emit_direct_bridge_request(
        direct_bridge,
        request_id,
        &request,
        &mut body_stream,
        request_body_known_empty,
    )
    .await
    {
        remove_pending_direct_request(direct_bridge, request_id);
        return Err(error);
    }

    let first_payload = match time::timeout(DIRECT_REQUEST_TIMEOUT, response_rx.recv()).await {
        Ok(Some(payload)) => payload,
        Ok(None) => {
            remove_pending_direct_request(direct_bridge, request_id);
            return Err("direct bridge callback closed before response".to_string());
        }
        Err(_) => {
            remove_pending_direct_request(direct_bridge, request_id);
            return Err(format!(
                "direct bridge callback timed out after {:?}",
                DIRECT_REQUEST_TIMEOUT
            ));
        }
    };

    let frame_type = match peek_bridge_frame_type(&first_payload) {
        Ok(frame_type) => frame_type,
        Err(error) => {
            remove_pending_direct_request(direct_bridge, request_id);
            return Err(format!("decode response failed: {error}"));
        }
    };

    if is_bridge_response_frame_type(frame_type) {
        let decoded = decode_bridge_response(&first_payload)
            .map_err(|error| format!("decode response failed: {error}"))?;
        remove_pending_direct_request(direct_bridge, request_id);
        let status = StatusCode::from_u16(decoded.status).unwrap_or(StatusCode::BAD_GATEWAY);
        if websocket_upgrade_requested && status == StatusCode::SWITCHING_PROTOCOLS {
            return Err(
                "websocket upgrade failed: direct callback returned single-frame response"
                    .to_string(),
            );
        }
        let mut response = Response::new(Body::from(decoded.body_bytes));
        *response.status_mut() = status;
        for (header_name, header_value) in decoded.headers {
            response.headers_mut().append(header_name, header_value);
        }
        return Ok(response);
    }

    if !is_bridge_response_start_frame_type(frame_type) {
        remove_pending_direct_request(direct_bridge, request_id);
        return Err(format!(
            "decode response failed: invalid bridge response frame type: {frame_type}"
        ));
    }

    let (status_code, headers) = decode_bridge_response_start(&first_payload)
        .map_err(|error| format!("decode response failed: {error}"))?;
    let status = StatusCode::from_u16(status_code).unwrap_or(StatusCode::BAD_GATEWAY);
    if websocket_upgrade_requested && status == StatusCode::SWITCHING_PROTOCOLS {
        let Some(upgrade) = upgrade else {
            remove_pending_direct_request(direct_bridge, request_id);
            return Err("websocket upgrade failed: missing hyper upgrade handle".to_string());
        };
        let direct_bridge = direct_bridge.clone();
        tokio::spawn(async move {
            if let Err(error) =
                run_direct_websocket_tunnel(upgrade, direct_bridge, request_id, response_rx).await
            {
                eprintln!("[server_native] direct websocket tunnel error: {error}");
            }
        });
        let mut response = Response::new(Body::empty());
        *response.status_mut() = status;
        for (header_name, header_value) in headers {
            response.headers_mut().append(header_name, header_value);
        }
        return Ok(response);
    }

    let (tx, rx) = mpsc::channel::<Result<Bytes, String>>(16);
    let direct_bridge = direct_bridge.clone();
    tokio::spawn(async move {
        stream_direct_bridge_response_frames(direct_bridge, request_id, response_rx, tx).await;
    });

    let mut response = Response::new(Body::from_stream(ReceiverStream::new(rx)));
    *response.status_mut() = status;
    for (header_name, header_value) in headers {
        response.headers_mut().append(header_name, header_value);
    }
    Ok(response)
}

/// Removes one pending direct callback request from the registry.
fn remove_pending_direct_request(direct_bridge: &Arc<DirectRequestBridge>, request_id: u64) {
    let _ = direct_bridge.pending.lock().remove(&request_id);
}

/// Emits request start/chunk/end payloads to the direct callback.
async fn emit_direct_bridge_request(
    direct_bridge: &Arc<DirectRequestBridge>,
    request_id: u64,
    request: &BridgeRequestRef<'_>,
    body_stream: &mut BodyDataStream,
    request_body_known_empty: bool,
) -> Result<(), String> {
    if request_body_known_empty {
        if is_websocket_upgrade(request.headers) {
            return emit_direct_streaming_empty_request(direct_bridge, request_id, request);
        }
        return emit_direct_empty_request(direct_bridge, request_id, request);
    }

    let mut first_non_empty_chunk: Option<Bytes> = None;
    while let Some(next_chunk) = body_stream.next().await {
        let chunk =
            next_chunk.map_err(|error| format!("failed to read request body chunk: {error}"))?;
        if chunk.is_empty() {
            continue;
        }
        first_non_empty_chunk = Some(chunk);
        break;
    }

    if first_non_empty_chunk.is_none() {
        if is_websocket_upgrade(request.headers) {
            return emit_direct_streaming_empty_request(direct_bridge, request_id, request);
        }
        return emit_direct_empty_request(direct_bridge, request_id, request);
    }

    let start_payload = encode_bridge_request_start(request)?;
    emit_direct_callback_payload(direct_bridge, request_id, start_payload)?;

    let mut total_body_bytes = 0usize;
    if let Some(first_chunk) = first_non_empty_chunk {
        total_body_bytes = emit_direct_request_chunk(
            direct_bridge,
            request_id,
            first_chunk.as_ref(),
            total_body_bytes,
        )?;
    }

    while let Some(next_chunk) = body_stream.next().await {
        let chunk =
            next_chunk.map_err(|error| format!("failed to read request body chunk: {error}"))?;
        if chunk.is_empty() {
            continue;
        }
        total_body_bytes =
            emit_direct_request_chunk(direct_bridge, request_id, chunk.as_ref(), total_body_bytes)?;
    }

    let end_payload = encode_bridge_request_end();
    emit_direct_callback_payload(direct_bridge, request_id, end_payload)
}

/// Emits an empty-body request payload to direct callback.
fn emit_direct_empty_request(
    direct_bridge: &Arc<DirectRequestBridge>,
    request_id: u64,
    request: &BridgeRequestRef<'_>,
) -> Result<(), String> {
    let payload = encode_bridge_request(request, &[])?;
    emit_direct_callback_payload(direct_bridge, request_id, payload)
}

/// Emits start/end request payloads for empty-body streamed requests.
fn emit_direct_streaming_empty_request(
    direct_bridge: &Arc<DirectRequestBridge>,
    request_id: u64,
    request: &BridgeRequestRef<'_>,
) -> Result<(), String> {
    let start_payload = encode_bridge_request_start(request)?;
    emit_direct_callback_payload(direct_bridge, request_id, start_payload)?;
    let end_payload = encode_bridge_request_end();
    emit_direct_callback_payload(direct_bridge, request_id, end_payload)
}

/// Emits one request chunk payload to direct callback.
fn emit_direct_request_chunk(
    direct_bridge: &Arc<DirectRequestBridge>,
    request_id: u64,
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
        let payload = encode_bridge_request_chunk_payload(frame_chunk)?;
        emit_direct_callback_payload(direct_bridge, request_id, payload)?;
    }

    Ok(total_body_bytes)
}

/// Invokes direct callback with one payload.
fn emit_direct_callback_payload(
    direct_bridge: &Arc<DirectRequestBridge>,
    request_id: u64,
    payload: Vec<u8>,
) -> Result<(), String> {
    let (payload_ptr, payload_len) = {
        let mut pending = direct_bridge.pending.lock();
        let Some(entry) = pending.get_mut(&request_id) else {
            return Err(format!(
                "direct bridge callback missing request id: {request_id}"
            ));
        };
        entry.inflight_payloads.push(payload);
        let payload = entry
            .inflight_payloads
            .last()
            .ok_or_else(|| "direct bridge callback payload queue unexpectedly empty".to_string())?;
        let payload_len = u64::try_from(payload.len())
            .map_err(|_| "direct request payload length does not fit u64".to_string())?;
        (payload.as_ptr(), payload_len)
    };
    (direct_bridge.callback)(request_id, payload_ptr, payload_len);
    Ok(())
}

/// Reads direct-callback response frames and streams them to channel.
async fn stream_direct_bridge_response_frames(
    direct_bridge: Arc<DirectRequestBridge>,
    request_id: u64,
    mut response_rx: mpsc::UnboundedReceiver<Vec<u8>>,
    tx: mpsc::Sender<Result<Bytes, String>>,
) {
    loop {
        let payload = match time::timeout(DIRECT_REQUEST_TIMEOUT, response_rx.recv()).await {
            Ok(Some(payload)) => payload,
            Ok(None) => {
                let _ = tx
                    .send(Err(
                        "direct bridge callback closed before response end".to_string()
                    ))
                    .await;
                break;
            }
            Err(_) => {
                let _ = tx
                    .send(Err(format!(
                        "direct bridge callback timed out after {:?}",
                        DIRECT_REQUEST_TIMEOUT
                    )))
                    .await;
                break;
            }
        };

        let frame_type = match peek_bridge_frame_type(&payload) {
            Ok(frame_type) => frame_type,
            Err(error) => {
                let _ = tx
                    .send(Err(format!("decode response failed: {error}")))
                    .await;
                break;
            }
        };

        if frame_type == BRIDGE_RESPONSE_CHUNK_FRAME_TYPE {
            match decode_bridge_response_chunk(&payload) {
                Ok(chunk) => {
                    if !chunk.is_empty() && tx.send(Ok(chunk)).await.is_err() {
                        break;
                    }
                }
                Err(error) => {
                    let _ = tx
                        .send(Err(format!("decode response failed: {error}")))
                        .await;
                    break;
                }
            }
            continue;
        }

        if frame_type == BRIDGE_RESPONSE_END_FRAME_TYPE {
            if let Err(error) = decode_bridge_response_end(&payload) {
                let _ = tx
                    .send(Err(format!("decode response failed: {error}")))
                    .await;
            }
            break;
        }

        let _ = tx
            .send(Err(format!(
                "decode response failed: unexpected bridge frame type: {frame_type}"
            )))
            .await;
        break;
    }

    remove_pending_direct_request(&direct_bridge, request_id);
}

/// Tunnels upgraded websocket bytes between frontend connection and
/// direct-callback bridge frames.
async fn run_direct_websocket_tunnel(
    upgrade: OnUpgrade,
    direct_bridge: Arc<DirectRequestBridge>,
    request_id: u64,
    mut response_rx: mpsc::UnboundedReceiver<Vec<u8>>,
) -> Result<(), String> {
    let upgraded = upgrade
        .await
        .map_err(|error| format!("frontend upgrade failed: {error}"))?;
    let upgraded = TokioIo::new(upgraded);
    let (mut frontend_reader, mut frontend_writer) = tokio::io::split(upgraded);

    let callback_bridge = direct_bridge.clone();
    let frontend_to_callback = tokio::spawn(async move {
        let mut buffer = vec![0_u8; BRIDGE_BODY_CHUNK_BYTES];
        loop {
            let read = frontend_reader
                .read(&mut buffer)
                .await
                .map_err(|error| format!("read upgraded frontend stream failed: {error}"))?;
            if read == 0 {
                emit_direct_tunnel_close(&callback_bridge, request_id)?;
                return Ok::<(), String>(());
            }
            emit_direct_tunnel_chunk(&callback_bridge, request_id, &buffer[..read])?;
        }
    });

    let callback_to_frontend = tokio::spawn(async move {
        loop {
            let payload = match time::timeout(DIRECT_REQUEST_TIMEOUT, response_rx.recv()).await {
                Ok(Some(payload)) => payload,
                Ok(None) => return Ok::<(), String>(()),
                Err(_) => {
                    return Err(format!(
                        "direct bridge callback timed out after {:?}",
                        DIRECT_REQUEST_TIMEOUT
                    ));
                }
            };
            let frame_type = peek_bridge_frame_type(&payload)?;
            if frame_type == BRIDGE_RESPONSE_END_FRAME_TYPE {
                decode_bridge_response_end(&payload)
                    .map_err(|error| format!("decode response failed: {error}"))?;
                continue;
            }
            if frame_type == BRIDGE_TUNNEL_CHUNK_FRAME_TYPE {
                let chunk = decode_bridge_tunnel_chunk(&payload)
                    .map_err(|error| format!("decode response failed: {error}"))?;
                if !chunk.is_empty() {
                    frontend_writer.write_all(&chunk).await.map_err(|error| {
                        format!("write upgraded frontend stream failed: {error}")
                    })?;
                }
                continue;
            }
            if frame_type == BRIDGE_TUNNEL_CLOSE_FRAME_TYPE {
                decode_bridge_tunnel_close(&payload)
                    .map_err(|error| format!("decode response failed: {error}"))?;
                return Ok(());
            }
            return Err(format!(
                "decode response failed: unexpected bridge tunnel frame type: {frame_type}"
            ));
        }
    });

    let (frontend_result, callback_result) =
        tokio::join!(frontend_to_callback, callback_to_frontend);
    remove_pending_direct_request(&direct_bridge, request_id);

    match frontend_result {
        Ok(Ok(())) => {}
        Ok(Err(error)) => return Err(error),
        Err(error) => {
            return Err(format!(
                "frontend-to-direct-callback tunnel task failed: {error}"
            ));
        }
    }

    match callback_result {
        Ok(Ok(())) => {}
        Ok(Err(error)) => return Err(error),
        Err(error) => {
            return Err(format!(
                "direct-callback-to-frontend tunnel task failed: {error}"
            ));
        }
    }

    Ok(())
}

/// Emits one tunnel chunk payload to direct callback.
fn emit_direct_tunnel_chunk(
    direct_bridge: &Arc<DirectRequestBridge>,
    request_id: u64,
    chunk: &[u8],
) -> Result<(), String> {
    for frame_chunk in chunk.chunks(BRIDGE_BODY_CHUNK_BYTES) {
        let payload = encode_bridge_tunnel_chunk_payload(frame_chunk)?;
        emit_direct_callback_payload(direct_bridge, request_id, payload)?;
    }
    Ok(())
}

/// Emits tunnel-close payload to direct callback.
fn emit_direct_tunnel_close(
    direct_bridge: &Arc<DirectRequestBridge>,
    request_id: u64,
) -> Result<(), String> {
    let payload = encode_bridge_tunnel_close_payload();
    emit_direct_callback_payload(direct_bridge, request_id, payload)
}

/// Calls Dart through the bridge socket and decodes the response.
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

/// Retry path used when the peer closed after a potentially empty-body request.
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

/// Writes one HTTP request to the bridge socket in either single-frame or
/// streaming frame mode.
///
/// Behavior:
/// - empty body: emits one single-frame request payload,
/// - non-empty body: emits start + chunk(s) + end frames.
///
/// `request_body_empty` is updated to indicate whether at least one non-empty
/// request body chunk was observed.
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

/// Writes an empty-body request as a single bridge frame.
async fn write_bridge_empty_request(
    socket: &mut dyn BridgeStream,
    request: &BridgeRequestRef<'_>,
) -> Result<(), String> {
    let payload = encode_bridge_request(request, &[])?;
    write_bridge_frame(socket, &payload).await
}

/// Writes one logical request-body chunk sequence to the bridge socket.
///
/// The input chunk may be further split into transport-sized bridge chunks
/// (`BRIDGE_BODY_CHUNK_BYTES`) before write.
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

/// Converts nullable C string pointer into owned UTF-8 Rust string.
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
