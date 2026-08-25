use std::time::Duration;

// ---- Transport and protocol limits -----------------------------------------
//
// These constants define hard safety limits for inbound/outbound bridge and
// HTTP body handling. They are used to:
// - bound per-request memory growth,
// - avoid oversized frame allocations, and
// - keep backpressure behavior predictable across Rust <-> Dart.
pub(crate) const MAX_PROXY_BODY_BYTES: usize = 32 * 1024 * 1024;
pub(crate) const MAX_BRIDGE_FRAME_BYTES: usize = 64 * 1024 * 1024;
pub(crate) const BRIDGE_BODY_CHUNK_BYTES: usize = 64 * 1024;
pub(crate) const BRIDGE_COALESCE_WRITE_THRESHOLD_BYTES: usize = 4 * 1024;

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
pub(crate) const BRIDGE_PROTOCOL_VERSION: u8 = 1;
pub(crate) const BRIDGE_PROTOCOL_VERSION_LEGACY: u8 = 1;
pub(crate) const _BRIDGE_REQUEST_FRAME_TYPE: u8 = 1; // legacy single-frame request
pub(crate) const BRIDGE_RESPONSE_FRAME_TYPE: u8 = 2; // legacy single-frame response
pub(crate) const _BRIDGE_REQUEST_START_FRAME_TYPE: u8 = 3;
pub(crate) const BRIDGE_REQUEST_CHUNK_FRAME_TYPE: u8 = 4;
pub(crate) const BRIDGE_REQUEST_END_FRAME_TYPE: u8 = 5;
pub(crate) const BRIDGE_RESPONSE_START_FRAME_TYPE: u8 = 6;
pub(crate) const BRIDGE_RESPONSE_CHUNK_FRAME_TYPE: u8 = 7;
pub(crate) const BRIDGE_RESPONSE_END_FRAME_TYPE: u8 = 8;
pub(crate) const BRIDGE_TUNNEL_CHUNK_FRAME_TYPE: u8 = 9;
pub(crate) const BRIDGE_TUNNEL_CLOSE_FRAME_TYPE: u8 = 10;
pub(crate) const BRIDGE_REQUEST_FRAME_TYPE_TOKENIZED: u8 = 11;
pub(crate) const BRIDGE_RESPONSE_FRAME_TYPE_TOKENIZED: u8 = 12;
pub(crate) const BRIDGE_REQUEST_START_FRAME_TYPE_TOKENIZED: u8 = 13;
pub(crate) const BRIDGE_RESPONSE_START_FRAME_TYPE_TOKENIZED: u8 = 14;
pub(crate) const BRIDGE_HEADER_NAME_LITERAL_TOKEN: u16 = 0xFFFF;
pub(crate) const BRIDGE_BACKEND_KIND_TCP: u8 = 0;
pub(crate) const BRIDGE_BACKEND_KIND_UNIX: u8 = 1;

// ---- Benchmark modes --------------------------------------------------------
pub(crate) const BENCHMARK_MODE_NONE: u8 = 0;
pub(crate) const BENCHMARK_MODE_STATIC_OK: u8 = 1;
pub(crate) const BENCHMARK_MODE_STATIC_OK_SERVER_NATIVE_DIRECT_SHAPE: u8 = 2;
pub(crate) const BENCHMARK_STATIC_OK_BODY: &[u8] = br#"{"ok":true,"label":"server_native_direct"}"#;
pub(crate) const BENCHMARK_SERVER_NATIVE_DIRECT_SHAPE_BODY: &[u8] =
    br#"{"ok":true,"label":"server_native_direct"}"#;
pub(crate) const MESSAGE_CANCELLED: &str = "cancelled";
pub(crate) const MESSAGE_CANCELED: &str = "canceled";
pub(crate) const MESSAGE_BRIDGE_STOPPING: &str = "bridge is stopping";
pub(crate) const MESSAGE_CONNECTION_CLOSED: &str = "connection closed";
pub(crate) const MESSAGE_CHANNEL_CLOSED: &str = "channel closed";
pub(crate) const LOG_WEBSOCKET_TUNNEL_ERROR_PREFIX: &str =
    "[server_native] websocket tunnel error: ";
pub(crate) const LOG_DIRECT_WEBSOCKET_TUNNEL_ERROR_PREFIX: &str =
    "[server_native] direct websocket tunnel error: ";
pub(crate) const TRANSFER_ENCODING_HEADER: &str = "transfer-encoding";
pub(crate) const SANITIZED_TRANSFER_ENCODING_HEADER: &str = "x-server-native-transfer-encoding";
pub(crate) const CONNECTION_HEADER: &str = "connection";
pub(crate) const SANITIZED_CONNECTION_HEADER: &str = "x-server-native-connection";
pub(crate) const EMPTY_CONNECTION_SENTINEL: &str = "__server_native_empty_connection__";
pub(crate) const HOST_HEADER: &str = "host";
pub(crate) const SANITIZED_HOST_HEADER: &str = "x-server-native-host";
pub(crate) const BAD_REQUEST_RESPONSE_BYTES: &[u8] = b"HTTP/1.1 400 Bad Request\r\n\
content-type: text/plain; charset=utf-8\r\n\
content-length: 11\r\n\
connection: close\r\n\
\r\n\
Bad Request";

/// Max time to wait for direct-callback response frames from Dart.
pub(crate) const DIRECT_REQUEST_TIMEOUT: Duration = Duration::from_secs(30);
/// Grace window for upgraded tunnel tasks to flush a close frame on shutdown.
pub(crate) const SHUTDOWN_TUNNEL_GRACE: Duration = Duration::from_millis(50);

/// WebSocket close code used when a native proxy is shutting down.
pub(crate) const WEBSOCKET_CLOSE_GOING_AWAY: u16 = 1001;
/// C callback signature used by direct request mode.
///
/// Rust invokes this callback with:
/// - `request_id`: correlation identifier unique per in-flight request,
/// - `payload`: pointer to encoded bridge frame bytes,
/// - `payload_len`: payload length in bytes.
///
/// Dart must treat `payload` as read-only and copy the bytes before returning.
pub(crate) type DirectRequestCallback =
    extern "C" fn(request_id: u64, payload: *const u8, payload_len: u64);
