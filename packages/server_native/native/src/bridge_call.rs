use crate::*;

/// Calls Dart through the bridge socket and decodes the response.
pub(crate) async fn call_bridge(
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
pub(crate) async fn call_bridge_retry_empty_body(
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
pub(crate) async fn write_bridge_request(
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
pub(crate) async fn write_bridge_empty_request(
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
pub(crate) async fn write_bridge_request_body_chunk(
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
