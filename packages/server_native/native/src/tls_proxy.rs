use crate::*;

pub(crate) async fn run_tls_proxy(
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
                            let mut builder = http1::Builder::new();
                            builder.half_close(true);
                            builder.ignore_invalid_headers(true);
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
                            let mut builder = http1::Builder::new();
                            builder.half_close(true);
                            builder.ignore_invalid_headers(true);
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
                    eprintln!("[server_native] tls task join failed: {error}");
                }
            }
        }
    }
    Ok(())
}
