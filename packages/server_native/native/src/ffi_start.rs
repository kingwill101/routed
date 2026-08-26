use crate::*;

#[no_mangle]
/// Returns the native transport ABI version expected by Dart bindings.
pub extern "C" fn server_native_transport_version() -> i32 {
    1
}

/// Chooses Tokio worker thread count for one proxy runtime.
///
/// Shared listeners are typically booted once per Dart isolate via
/// `shared: true`, so keeping each runtime to a single worker avoids
/// multiplying the machine core count across every isolate.
pub(crate) fn proxy_runtime_worker_threads(shared: bool) -> usize {
    if shared {
        return 1;
    }

    std::thread::available_parallelism()
        .map(|value| value.get())
        .unwrap_or(2)
        .clamp(2, 16)
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
pub unsafe extern "C" fn server_native_start_proxy_server(
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
    let direct_polling_mode = direct_callback.is_none()
        && matches!(&bridge_endpoint, BridgeEndpoint::Tcp(addr) if addr == "127.0.0.1:9");
    let direct_bridge = if direct_callback.is_some() || direct_polling_mode {
        Some(Arc::new(DirectRequestBridge {
            callback_state: Mutex::new(DirectCallbackState {
                callback: direct_callback,
                stopping: false,
                in_flight: 0,
            }),
            callback_state_cv: Condvar::new(),
            next_request_id: AtomicU64::new(1),
            stopped: AtomicBool::new(false),
            pending: Mutex::new(HashMap::new()),
            queued_payloads: Mutex::new(VecDeque::new()),
            queued_payloads_cv: Condvar::new(),
        }))
    } else {
        None
    };
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
        let worker_threads = proxy_runtime_worker_threads(shared);
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
            let app = Router::new()
                .fallback(any(router_proxy_request))
                .with_state(state.clone());
            let _ = startup_tx.send(Ok(actual_port));

            let result = match tls_config {
                Some(tls_config) => {
                    run_tls_proxy(
                        listener,
                        app,
                        state,
                        shutdown_rx,
                        TlsProxyOptions {
                            tls_config,
                            enable_http2,
                            enable_http3,
                            request_client_certificate,
                        },
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
                    run_plain_proxy(listener, state, shutdown_rx, enable_http2).await
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
