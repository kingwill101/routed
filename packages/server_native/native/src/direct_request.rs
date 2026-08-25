use crate::*;

/// Forwards a request through the direct callback bridge.
pub(crate) async fn call_direct_bridge_request(
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

    direct_bridge
        .pending
        .lock()
        .insert(request_id, PendingDirectRequest { response_tx });

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
        let body_len = decoded.body_bytes.len();
        let mut response = Response::new(Body::from(decoded.body_bytes));
        *response.status_mut() = status;
        append_bridge_response_headers(
            response.headers_mut(),
            status,
            request.protocol,
            decoded.headers,
        );
        ensure_content_length_header(response.headers_mut(), status, body_len);
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
                if !is_expected_shutdown_tunnel_error(&error.to_string()) {
                    eprintln!("{LOG_DIRECT_WEBSOCKET_TUNNEL_ERROR_PREFIX}{error}");
                }
            }
        });
        let mut response = Response::new(Body::empty());
        *response.status_mut() = status;
        append_bridge_response_headers(response.headers_mut(), status, request.protocol, headers);
        return Ok(response);
    }

    let (tx, rx) = mpsc::channel::<Result<Bytes, String>>(16);
    let direct_bridge = direct_bridge.clone();
    tokio::spawn(async move {
        stream_direct_bridge_response_frames(direct_bridge, request_id, response_rx, tx).await;
    });

    let mut response = Response::new(Body::from_stream(ReceiverStream::new(rx)));
    *response.status_mut() = status;
    append_bridge_response_headers(response.headers_mut(), status, request.protocol, headers);
    Ok(response)
}

/// Removes one pending direct callback request from the registry.
pub(crate) fn remove_pending_direct_request(
    direct_bridge: &Arc<DirectRequestBridge>,
    request_id: u64,
) {
    let _ = direct_bridge.pending.lock().remove(&request_id);
}

/// Emits request start/chunk/end payloads to the direct callback.
pub(crate) async fn emit_direct_bridge_request(
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

    let start_payload = encode_bridge_request_start(request)?;
    emit_direct_callback_payload(direct_bridge, request_id, start_payload)?;

    let mut total_body_bytes = 0usize;
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
pub(crate) fn emit_direct_empty_request(
    direct_bridge: &Arc<DirectRequestBridge>,
    request_id: u64,
    request: &BridgeRequestRef<'_>,
) -> Result<(), String> {
    let payload = encode_bridge_request(request, &[])?;
    emit_direct_callback_payload(direct_bridge, request_id, payload)
}

/// Emits start/end request payloads for empty-body streamed requests.
pub(crate) fn emit_direct_streaming_empty_request(
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
pub(crate) fn emit_direct_request_chunk(
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
pub(crate) fn emit_direct_callback_payload(
    direct_bridge: &Arc<DirectRequestBridge>,
    request_id: u64,
    payload: Vec<u8>,
) -> Result<(), String> {
    if direct_bridge.stopped.load(Ordering::Acquire) {
        return Err("direct bridge is stopping".to_string());
    }
    {
        let pending = direct_bridge.pending.lock();
        if !pending.contains_key(&request_id) {
            return Err(format!(
                "direct bridge callback missing request id: {request_id}"
            ));
        }
    }

    let mut queued = direct_bridge.queued_payloads.lock();
    let should_wake = queued.is_empty();
    queued.push_back(QueuedDirectPayload {
        request_id,
        payload,
    });
    direct_bridge.queued_payloads_cv.notify_one();
    drop(queued);

    if should_wake {
        let callback = {
            let mut callback_state = direct_bridge.callback_state.lock();
            if callback_state.stopping {
                None
            } else if let Some(callback) = callback_state.callback {
                callback_state.in_flight += 1;
                Some(callback)
            } else {
                None
            }
        };

        if let Some(callback) = callback {
            // In callback mode we still enqueue payloads and only use callback
            // as a wake-up signal. This avoids passing raw pointers through the
            // async isolate listener boundary in Dart.
            callback(request_id, std::ptr::null(), 0);

            let mut callback_state = direct_bridge.callback_state.lock();
            callback_state.in_flight = callback_state.in_flight.saturating_sub(1);
            if callback_state.stopping && callback_state.in_flight == 0 {
                direct_bridge.callback_state_cv.notify_all();
            }
        }
    }
    Ok(())
}
