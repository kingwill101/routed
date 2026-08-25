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

use std::collections::{HashMap, VecDeque};
use std::ffi::{c_char, c_void, CStr};
use std::fs::File;
use std::io::{self, BufReader, ErrorKind, IoSlice};
use std::net::SocketAddr;
use std::path::PathBuf;
use std::pin::Pin;
use std::ptr::null_mut;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;
use std::task::{Context, Poll};
use std::thread;
use std::time::Duration;

use axum::body::{Body, BodyDataStream, Bytes};
use axum::extract::State;
use axum::http::{HeaderMap, Request, Response, StatusCode, Version};
use axum::routing::any;
use axum::Router;
use hyper::server::conn::http1;
use hyper::upgrade::OnUpgrade;
use hyper_util::rt::{TokioExecutor, TokioIo};
use hyper_util::server::conn::auto::Builder as AutoBuilder;
use hyper_util::service::TowerToHyperService;
use parking_lot::{Condvar, Mutex};
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

mod constants;
pub(crate) use constants::*;

mod types;
pub(crate) use types::{
    BoxBridgeStream, BridgeCallResult, BridgeConnection, BridgeEndpoint, BridgePool,
    BridgeRequestRef, BridgeResponse, BridgeStream, DirectCallbackState, DirectRequestBridge,
    PendingDirectRequest, ProxyState, ProxyTlsConfig, QueuedDirectPayload,
};
pub use types::{ProxyServerHandle, ServerNativeProxyConfig};

mod prefixed_io;
pub(crate) use prefixed_io::*;

mod tls_support;
pub(crate) use tls_support::*;

mod bridge_encode;
pub(crate) use bridge_encode::*;
mod bridge_response_stream;
pub(crate) use bridge_response_stream::*;
mod bridge_response_decode;
pub(crate) use bridge_response_decode::*;
mod bridge_io;
pub(crate) use bridge_io::*;
mod bridge_codec;
pub(crate) use bridge_codec::*;

mod ffi_start;
#[cfg(test)]
pub(crate) use ffi_start::proxy_runtime_worker_threads;
pub use ffi_start::{server_native_start_proxy_server, server_native_transport_version};

mod ffi_direct;
#[cfg(test)]
pub(crate) use ffi_direct::stop_direct_bridge;
pub use ffi_direct::{
    server_native_complete_direct_request, server_native_free_direct_request_payload,
    server_native_poll_direct_request_frame, server_native_push_direct_response_frame,
    server_native_stop_proxy_server,
};

mod proxy_listener;
pub(crate) use proxy_listener::*;
mod http1_scan;
pub(crate) use http1_scan::*;
mod http1_headers;
pub(crate) use http1_headers::*;
mod http1_rewrite;
pub(crate) use http1_rewrite::*;
mod tls_proxy;
pub(crate) use tls_proxy::*;
mod proxy_request;
pub(crate) use proxy_request::*;
mod direct_request;
pub(crate) use direct_request::*;
mod direct_tunnel;
pub(crate) use direct_tunnel::*;
mod bridge_call;
pub(crate) use bridge_call::*;
mod ffi_helpers;
pub(crate) use ffi_helpers::*;

#[cfg(test)]
mod tests;
