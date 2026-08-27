use crate::*;

/// Resolves bind target and creates a TCP listener with requested options.
pub(crate) async fn bind_tcp_listener(
    host: &str,
    port: u16,
    backlog: u32,
    v6_only: bool,
    shared: bool,
) -> Result<TcpListener, String> {
    let resolved = tokio::net::lookup_host((host, port))
        .await
        .map_err(|error| format!("resolve {host}:{port} failed: {error}"))?;
    let mut last_error: Option<String> = None;

    for addr in resolved {
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
pub(crate) fn bind_tcp_listener_addr(
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
pub(crate) async fn run_plain_proxy(
    listener: TcpListener,
    state: ProxyState,
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
                let state = state.clone();
                connections.spawn(async move {
                    let stream = stream;
                    let local_addr = stream.local_addr().ok();
                    let peer_addr = stream.peer_addr().ok();
                    let Some(stream) = maybe_prepare_http1_prefixed_stream(stream).await? else {
                        return Ok(());
                    };
                    let service = hyper::service::service_fn(
                        move |request: Request<hyper::body::Incoming>| {
                        let state = state.clone();
                        async move {
                            proxy_request(State(state), request.map(Body::new)).await
                        }
                    });
                    if enable_http2 {
                        let builder = AutoBuilder::new(TokioExecutor::new());
                        builder
                            .serve_connection_with_upgrades(TokioIo::new(stream), service)
                            .await
                            .map_err(|error| {
                                format!(
                                    "plain connection failed (local={local_addr:?} peer={peer_addr:?}): {error}"
                                )
                            })
                    } else {
                        let mut builder = http1::Builder::new();
                        builder.half_close(true);
                        builder.ignore_invalid_headers(true);
                        builder
                            .serve_connection(TokioIo::new(stream), service)
                            .with_upgrades()
                            .await
                            .map_err(|error| {
                                format!(
                                    "plain h1 connection failed (local={local_addr:?} peer={peer_addr:?}): {error}"
                                )
                            })
                    }
                });
            }
        }
    }

    time::sleep(SHUTDOWN_TUNNEL_GRACE).await;

    // Force-close all active per-connection tasks on shutdown so the FFI stop
    // path cannot hang behind idle keep-alive sockets.
    connections.abort_all();
    while let Some(result) = connections.join_next().await {
        match result {
            Ok(Ok(())) => {}
            Ok(Err(error)) => {
                if !is_cancellation_message(&error) {
                    eprintln!("[server_native] {error}");
                }
            }
            Err(error) => {
                if !error.is_cancelled() && !is_cancellation_message(&error.to_string()) {
                    eprintln!("[server_native] plain task join failed: {error}");
                }
            }
        }
    }
    Ok(())
}
