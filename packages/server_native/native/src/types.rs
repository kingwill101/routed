use crate::*;

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
pub(crate) struct ProxyState {
    pub(crate) bridge_pool: Arc<BridgePool>,
    pub(crate) benchmark_mode: u8,
    pub(crate) direct_bridge: Option<Arc<DirectRequestBridge>>,
}

#[derive(Clone)]
/// TLS file-path configuration resolved from C ABI input.
pub(crate) struct ProxyTlsConfig {
    pub(crate) cert_path: String,
    pub(crate) key_path: String,
    pub(crate) cert_password: Option<String>,
}

/// Opaque server handle returned to Dart through FFI.
///
/// The pointer returned by [`server_native_start_proxy_server`] must later be
/// passed to [`server_native_stop_proxy_server`] exactly once.
pub struct ProxyServerHandle {
    pub(crate) shutdown_tx: Option<oneshot::Sender<()>>,
    pub(crate) join_handle: Option<thread::JoinHandle<()>>,
    pub(crate) direct_bridge: Option<Arc<DirectRequestBridge>>,
}

/// Registry for in-flight direct-callback requests.
pub(crate) struct DirectRequestBridge {
    pub(crate) callback_state: Mutex<DirectCallbackState>,
    pub(crate) callback_state_cv: Condvar,
    pub(crate) next_request_id: AtomicU64,
    pub(crate) stopped: AtomicBool,
    pub(crate) pending: Mutex<HashMap<u64, PendingDirectRequest>>,
    pub(crate) queued_payloads: Mutex<VecDeque<QueuedDirectPayload>>,
    pub(crate) queued_payloads_cv: Condvar,
}

/// Lifecycle state for the direct wake callback exposed to Dart.
pub(crate) struct DirectCallbackState {
    pub(crate) callback: Option<DirectRequestCallback>,
    pub(crate) stopping: bool,
    pub(crate) in_flight: usize,
}

/// Per-request direct-callback state.
pub(crate) struct PendingDirectRequest {
    pub(crate) response_tx: mpsc::UnboundedSender<Vec<u8>>,
}

/// Queued direct-request payload awaiting Dart polling.
pub(crate) struct QueuedDirectPayload {
    pub(crate) request_id: u64,
    pub(crate) payload: Vec<u8>,
}

/// Connection pool for bridge sockets between Rust and Dart runtime.
pub(crate) struct BridgePool {
    pub(crate) endpoint: BridgeEndpoint,
    pub(crate) max_idle: usize,
    pub(crate) hot: Mutex<Option<BridgeConnection>>,
    pub(crate) idle: Mutex<Vec<BridgeConnection>>,
}

pub(crate) trait BridgeStream: AsyncRead + AsyncWrite + Unpin + Send {}
impl<T> BridgeStream for T where T: AsyncRead + AsyncWrite + Unpin + Send {}
pub(crate) type BoxBridgeStream = Box<dyn BridgeStream>;

/// One pooled bridge stream plus reusable read buffer.
pub(crate) struct BridgeConnection {
    pub(crate) stream: BoxBridgeStream,
    pub(crate) read_buffer: Vec<u8>,
}

#[derive(Clone)]
/// Bridge backend endpoint (`tcp://` or `unix://`).
pub(crate) enum BridgeEndpoint {
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
    pub(crate) fn new(endpoint: BridgeEndpoint, max_idle: usize) -> Self {
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
    pub(crate) async fn acquire(&self) -> Result<BridgeConnection, String> {
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
    pub(crate) async fn connect_new(&self) -> Result<BridgeConnection, String> {
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
    pub(crate) fn release(&self, mut connection: BridgeConnection) {
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
pub(crate) struct BridgeRequestRef<'a> {
    pub(crate) method: &'a str,
    pub(crate) scheme: &'a str,
    pub(crate) authority: &'a str,
    pub(crate) path: &'a str,
    pub(crate) query: &'a str,
    pub(crate) protocol: &'a str,
    pub(crate) headers: &'a HeaderMap,
}

/// Decoded single-frame bridge response.
pub(crate) struct BridgeResponse {
    pub(crate) status: u16,
    pub(crate) headers: Vec<(axum::http::header::HeaderName, axum::http::HeaderValue)>,
    pub(crate) body_bytes: Bytes,
}

/// Bridge call result returned to HTTP serving path.
pub(crate) struct BridgeCallResult {
    pub(crate) status: u16,
    pub(crate) headers: Vec<(axum::http::header::HeaderName, axum::http::HeaderValue)>,
    pub(crate) body: Body,
    pub(crate) tunnel_socket: Option<BridgeConnection>,
}
