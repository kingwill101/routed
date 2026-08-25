use crate::*;

/// Main request handler used by Axum for all incoming HTTP requests.
///
/// It chooses one of three execution modes:
/// - static benchmark response
/// - direct callback mode
/// - bridge socket mode
pub(crate) async fn proxy_request(
    State(state): State<ProxyState>,
    request: Request<Body>,
) -> Response<Body> {
    if state.benchmark_mode == BENCHMARK_MODE_STATIC_OK {
        return benchmark_static_ok_response();
    }
    if state.benchmark_mode == BENCHMARK_MODE_STATIC_OK_SERVER_NATIVE_DIRECT_SHAPE {
        return benchmark_static_response(BENCHMARK_SERVER_NATIVE_DIRECT_SHAPE_BODY);
    }

    let (mut parts, body) = request.into_parts();
    restore_sanitized_compat_headers(&mut parts.headers);
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

    let request_protocol = http_version_to_protocol(parts.version);
    let bridge_request = BridgeRequestRef {
        method: parts.method.as_str(),
        scheme,
        authority,
        path,
        query,
        protocol: request_protocol,
        headers: &parts.headers,
    };

    if let Some(direct_bridge) = state.direct_bridge.as_ref() {
        let request_body_known_empty = false;
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

    let request_body_known_empty = false;
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
                if !is_expected_shutdown_tunnel_error(&error.to_string()) {
                    eprintln!("{LOG_WEBSOCKET_TUNNEL_ERROR_PREFIX}{error}");
                }
            }
        });
    }

    let mut response = Response::new(bridge_result.body);
    *response.status_mut() = status;
    append_bridge_response_headers(
        response.headers_mut(),
        status,
        request_protocol,
        bridge_result.headers,
    );
    response
}

/// Restores rewritten compatibility headers before request bridging.
pub(crate) fn restore_sanitized_compat_headers(headers: &mut HeaderMap) {
    let sanitized_name =
        axum::http::header::HeaderName::from_static(SANITIZED_TRANSFER_ENCODING_HEADER);
    let transfer_encoding_name =
        axum::http::header::HeaderName::from_static(TRANSFER_ENCODING_HEADER);
    let values = headers
        .get_all(&sanitized_name)
        .iter()
        .cloned()
        .collect::<Vec<_>>();
    if !values.is_empty() {
        headers.remove(&sanitized_name);
        for value in values {
            headers.append(transfer_encoding_name.clone(), value);
        }
    }

    // Keep `x-server-native-connection` in-request so Hyper does not apply
    // hop-by-hop connection stripping/overrides from the original value.
    // Bridge encoding remaps this sanitized header back to `connection` for
    // Dart-side HttpRequest compatibility.

    let sanitized_host_name = axum::http::header::HeaderName::from_static(SANITIZED_HOST_HEADER);
    let host_name = axum::http::header::HeaderName::from_static(HOST_HEADER);
    let host_values = headers
        .get_all(&sanitized_host_name)
        .iter()
        .cloned()
        .collect::<Vec<_>>();
    if !host_values.is_empty() {
        headers.remove(&sanitized_host_name);
        headers.remove(&host_name);
        for value in host_values {
            headers.append(host_name.clone(), value);
        }
    }
}

/// Convenience benchmark response for native-direct transport baseline.
pub(crate) fn benchmark_static_ok_response() -> Response<Body> {
    benchmark_static_response(BENCHMARK_STATIC_OK_BODY)
}

/// Convenience benchmark response shape that mirrors server_native direct path.
pub(crate) fn benchmark_static_response(body: &'static [u8]) -> Response<Body> {
    let mut response = Response::new(Body::from(body));
    *response.status_mut() = StatusCode::OK;
    response.headers_mut().insert(
        axum::http::header::CONTENT_TYPE,
        axum::http::HeaderValue::from_static("application/json"),
    );
    response
}

/// Appends decoded bridge response headers while filtering hop-by-hop headers
/// that Hyper manages internally for non-upgrade responses.
pub(crate) fn append_bridge_response_headers(
    target: &mut axum::http::HeaderMap,
    status: StatusCode,
    request_protocol: &str,
    headers: Vec<(axum::http::header::HeaderName, axum::http::HeaderValue)>,
) {
    let request_is_http1 = request_protocol == "1.0" || request_protocol == "1.1";
    for (header_name, header_value) in headers {
        if should_forward_bridge_response_header(&header_name, status, request_protocol) {
            if request_is_http1 && header_name.as_str() == CONNECTION_HEADER {
                if let Ok(connection_value) = header_value.to_str() {
                    for token in connection_value.split(',') {
                        let token = token.trim();
                        if token.is_empty() {
                            continue;
                        }
                        if let Ok(value) = axum::http::HeaderValue::from_str(token) {
                            target.append(header_name.clone(), value);
                        }
                    }
                    continue;
                }
            }
            target.append(header_name, header_value);
        }
    }
}

/// Ensures HTTP body framing headers are explicit for fixed-size responses.
///
/// Hyper can infer framing in many cases, but callback-driven bridge responses
/// are safest when `Content-Length` is explicit for body-bearing statuses.
pub(crate) fn ensure_content_length_header(
    headers: &mut axum::http::HeaderMap,
    status: StatusCode,
    body_len: usize,
) {
    if status.is_informational()
        || status == StatusCode::NO_CONTENT
        || status == StatusCode::NOT_MODIFIED
        || status == StatusCode::SWITCHING_PROTOCOLS
    {
        return;
    }
    if headers.contains_key(axum::http::header::CONTENT_LENGTH)
        || headers.contains_key(axum::http::header::TRANSFER_ENCODING)
    {
        return;
    }
    if let Ok(value) = axum::http::HeaderValue::from_str(&body_len.to_string()) {
        headers.insert(axum::http::header::CONTENT_LENGTH, value);
    }
}

/// Returns whether a response header should be forwarded to Hyper.
pub(crate) fn should_forward_bridge_response_header(
    header_name: &axum::http::header::HeaderName,
    status: StatusCode,
    request_protocol: &str,
) -> bool {
    if status == StatusCode::SWITCHING_PROTOCOLS {
        return true;
    }
    let request_is_http1 = request_protocol == "1.0" || request_protocol == "1.1";
    match header_name.as_str() {
        "transfer-encoding" => false,
        "connection" | "keep-alive" | "upgrade" | "proxy-connection" => request_is_http1,
        _ => true,
    }
}
