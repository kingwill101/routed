/// Encodes bridge request start frame for streaming request bodies.
fn encode_bridge_request_start(request: &BridgeRequestRef<'_>) -> Result<Vec<u8>, String> {
    let mut writer = BridgeByteWriter::new();
    writer.reserve(256 + request.headers.len() * 32);
    writer.put_u8(BRIDGE_PROTOCOL_VERSION);
    writer.put_u8(BRIDGE_REQUEST_START_FRAME_TYPE_TOKENIZED);
    writer.put_string(request.method)?;
    writer.put_string(request.scheme)?;
    writer.put_string(request.authority)?;
    writer.put_string(request.path)?;
    writer.put_string(request.query)?;
    writer.put_string(request.protocol)?;
    encode_bridge_request_headers(&mut writer, request)?;
    Ok(writer.into_inner())
}

/// Encodes legacy/single-frame bridge request payload.
fn encode_bridge_request(
    request: &BridgeRequestRef<'_>,
    body_bytes: &[u8],
) -> Result<Vec<u8>, String> {
    let mut writer = BridgeByteWriter::new();
    writer.reserve(256 + request.headers.len() * 32 + body_bytes.len());
    writer.put_u8(BRIDGE_PROTOCOL_VERSION);
    writer.put_u8(BRIDGE_REQUEST_FRAME_TYPE_TOKENIZED);
    writer.put_string(request.method)?;
    writer.put_string(request.scheme)?;
    writer.put_string(request.authority)?;
    writer.put_string(request.path)?;
    writer.put_string(request.query)?;
    writer.put_string(request.protocol)?;
    encode_bridge_request_headers(&mut writer, request)?;
    writer.put_bytes(body_bytes)?;
    Ok(writer.into_inner())
}

/// Encodes request headers into bridge wire format.
fn encode_bridge_request_headers(
    writer: &mut BridgeByteWriter,
    request: &BridgeRequestRef<'_>,
) -> Result<(), String> {
    if request.headers.is_empty() {
        writer.put_u32(0);
        return Ok(());
    }

    let count_pos = writer.reserve_u32();
    let mut count: u32 = 0;
    for (name, value) in request.headers.iter() {
        let Ok(value) = value.to_str() else {
            continue;
        };
        count = count
            .checked_add(1)
            .ok_or_else(|| "bridge request has too many headers".to_string())?;
        write_bridge_header_name(writer, name.as_str())?;
        writer.put_string(value)?;
    }
    writer.patch_u32(count_pos, count);
    Ok(())
}

/// Encodes request end frame for streaming request bodies.
fn encode_bridge_request_end() -> Vec<u8> {
    vec![BRIDGE_PROTOCOL_VERSION, BRIDGE_REQUEST_END_FRAME_TYPE]
}

/// Writes a tokenized header name when available, else literal form.
fn write_bridge_header_name(writer: &mut BridgeByteWriter, name: &str) -> Result<(), String> {
    if let Some(token) = bridge_header_name_token(name) {
        writer.put_u16(token);
        return Ok(());
    }
    writer.put_u16(BRIDGE_HEADER_NAME_LITERAL_TOKEN);
    writer.put_string(name)
}

/// Maps lowercase header names to compact bridge tokens.
fn bridge_header_name_token(name: &str) -> Option<u16> {
    // Header names are normalized lowercase by hyper/axum in hot paths.
    let token = match name {
        "host" => 0,
        "connection" => 1,
        "user-agent" => 2,
        "accept" => 3,
        "accept-encoding" => 4,
        "accept-language" => 5,
        "content-type" => 6,
        "content-length" => 7,
        "transfer-encoding" => 8,
        "cookie" => 9,
        "set-cookie" => 10,
        "cache-control" => 11,
        "pragma" => 12,
        "upgrade" => 13,
        "authorization" => 14,
        "origin" => 15,
        "referer" => 16,
        "location" => 17,
        "server" => 18,
        "date" => 19,
        "x-forwarded-for" => 20,
        "x-forwarded-proto" => 21,
        "x-forwarded-host" => 22,
        "x-forwarded-port" => 23,
        "x-request-id" => 24,
        "sec-websocket-key" => 25,
        "sec-websocket-version" => 26,
        "sec-websocket-protocol" => 27,
        "sec-websocket-extensions" => 28,
        _ => return None,
    };
    Some(token)
}

/// Encodes one request body chunk payload.
fn encode_bridge_request_chunk_payload(chunk: &[u8]) -> Result<Vec<u8>, String> {
    let mut writer = BridgeByteWriter::new();
    writer.reserve(6 + chunk.len());
    writer.put_u8(BRIDGE_PROTOCOL_VERSION);
    writer.put_u8(BRIDGE_REQUEST_CHUNK_FRAME_TYPE);
    writer.put_bytes(chunk)?;
    Ok(writer.into_inner())
}

/// Writes one request-body chunk frame.
async fn write_bridge_request_chunk_frame(
    socket: &mut dyn BridgeStream,
    chunk: &[u8],
) -> Result<(), String> {
    write_bridge_chunk_frame_with_type(socket, BRIDGE_REQUEST_CHUNK_FRAME_TYPE, chunk).await
}

/// Writes one tunnel chunk frame.
async fn write_bridge_tunnel_chunk_frame<S: AsyncWrite + Unpin + ?Sized>(
    socket: &mut S,
    chunk: &[u8],
) -> Result<(), String> {
    write_bridge_chunk_frame_with_type(socket, BRIDGE_TUNNEL_CHUNK_FRAME_TYPE, chunk).await
}

/// Generic chunk frame writer used by request and tunnel paths.
async fn write_bridge_chunk_frame_with_type<S: AsyncWrite + Unpin + ?Sized>(
    socket: &mut S,
    frame_type: u8,
    chunk: &[u8],
) -> Result<(), String> {
    let chunk_len = u32::try_from(chunk.len())
        .map_err(|_| "bridge chunk length does not fit u32".to_string())?;
    let payload_len = 6usize
        .checked_add(chunk.len())
        .ok_or_else(|| "bridge frame length overflow".to_string())?;
    if payload_len > MAX_BRIDGE_FRAME_BYTES {
        return Err(format!("bridge frame too large: {payload_len}"));
    }
    let payload_len = u32::try_from(payload_len)
        .map_err(|_| "bridge frame length does not fit u32".to_string())?;

    let header = payload_len.to_be_bytes();
    let mut prefix = [0_u8; 6];
    prefix[0] = BRIDGE_PROTOCOL_VERSION;
    prefix[1] = frame_type;
    prefix[2..6].copy_from_slice(&chunk_len.to_be_bytes());
    if payload_len as usize <= BRIDGE_COALESCE_WRITE_THRESHOLD_BYTES {
        let mut out = Vec::with_capacity(10 + chunk.len());
        out.extend_from_slice(&header);
        out.extend_from_slice(&prefix);
        if !chunk.is_empty() {
            out.extend_from_slice(chunk);
        }
        socket
            .write_all(&out)
            .await
            .map_err(|error| format!("write frame payload failed: {error}"))?;
        return Ok(());
    }
    if chunk.is_empty() {
        write_all_vectored(socket, &[&header, &prefix])
            .await
            .map_err(|error| format!("write frame payload failed: {error}"))?;
        return Ok(());
    }

    write_all_vectored(socket, &[&header, &prefix, chunk])
        .await
        .map_err(|error| format!("write frame payload failed: {error}"))?;
    Ok(())
}

/// Decodes bridge response sequence into HTTP response body/headers.
///
/// Supports:
/// - single-frame responses,
/// - streaming start/chunk/end responses,
/// - optional websocket tunnel detach semantics.
async fn decode_bridge_response_stream(
    mut connection: BridgeConnection,
    bridge_pool: Arc<BridgePool>,
    websocket_upgrade_requested: bool,
) -> Result<BridgeCallResult, String> {
    let first_frame_type = peek_bridge_frame_type(&connection.read_buffer)?;
    if is_bridge_response_frame_type(first_frame_type) {
        let legacy_response = decode_bridge_response(&connection.read_buffer)
            .map_err(|error| format!("decode response failed: {error}"))?;
        if websocket_upgrade_requested
            && legacy_response.status == StatusCode::SWITCHING_PROTOCOLS.as_u16()
        {
            return Ok(BridgeCallResult {
                status: legacy_response.status,
                headers: legacy_response.headers,
                body: Body::empty(),
                tunnel_socket: Some(connection),
            });
        }
        bridge_pool.release(connection);
        return Ok(BridgeCallResult {
            status: legacy_response.status,
            headers: legacy_response.headers,
            body: Body::from(legacy_response.body_bytes),
            tunnel_socket: None,
        });
    }
    if !is_bridge_response_start_frame_type(first_frame_type) {
        return Err(format!(
            "decode response failed: invalid bridge response frame type: {first_frame_type}"
        ));
    }

    let (status, headers) = decode_bridge_response_start(&connection.read_buffer)
        .map_err(|error| format!("decode response failed: {error}"))?;

    if !read_bridge_frame_reuse(&mut *connection.stream, &mut connection.read_buffer).await? {
        return Err(
            "decode response failed: bridge closed connection before response end".to_string(),
        );
    }
    let next_frame_type = peek_bridge_frame_type(&connection.read_buffer)
        .map_err(|error| format!("decode response failed: {error}"))?;

    if next_frame_type == BRIDGE_RESPONSE_END_FRAME_TYPE {
        decode_bridge_response_end(&connection.read_buffer)
            .map_err(|error| format!("decode response failed: {error}"))?;
        if websocket_upgrade_requested && status == StatusCode::SWITCHING_PROTOCOLS.as_u16() {
            return Ok(BridgeCallResult {
                status,
                headers,
                body: Body::empty(),
                tunnel_socket: Some(connection),
            });
        }
        bridge_pool.release(connection);
        return Ok(BridgeCallResult {
            status,
            headers,
            body: Body::empty(),
            tunnel_socket: None,
        });
    }
    if next_frame_type != BRIDGE_RESPONSE_CHUNK_FRAME_TYPE {
        return Err(format!(
            "decode response failed: unexpected bridge response frame type: {next_frame_type}"
        ));
    }

    let first_chunk = decode_bridge_response_chunk(&connection.read_buffer)
        .map_err(|error| format!("decode response failed: {error}"))?;

    let (tx, rx) = mpsc::channel::<Result<Bytes, io::Error>>(8);
    if !first_chunk.is_empty() {
        tx.send(Ok(first_chunk))
            .await
            .map_err(|_| "decode response failed: response body stream closed".to_string())?;
    }

    tokio::spawn(async move {
        stream_bridge_response_chunks(connection, tx, bridge_pool).await;
    });

    Ok(BridgeCallResult {
        status,
        headers,
        body: Body::from_stream(ReceiverStream::new(rx)),
        tunnel_socket: None,
    })
}

/// Streams bridge response chunks into an HTTP response body channel.
async fn stream_bridge_response_chunks(
    mut connection: BridgeConnection,
    tx: mpsc::Sender<Result<Bytes, io::Error>>,
    bridge_pool: Arc<BridgePool>,
) {
    let mut total_body_bytes = 0usize;
    loop {
        match read_bridge_frame_reuse(&mut *connection.stream, &mut connection.read_buffer).await {
            Ok(true) => {}
            Ok(false) => {
                let _ = tx
                    .send(Err(io::Error::new(
                        ErrorKind::UnexpectedEof,
                        "bridge closed connection before response end",
                    )))
                    .await;
                return;
            }
            Err(error) => {
                let _ = tx.send(Err(io::Error::new(ErrorKind::Other, error))).await;
                return;
            }
        }

        let frame_type = match peek_bridge_frame_type(&connection.read_buffer) {
            Ok(frame_type) => frame_type,
            Err(error) => {
                let _ = tx
                    .send(Err(io::Error::new(ErrorKind::InvalidData, error)))
                    .await;
                return;
            }
        };

        if frame_type == BRIDGE_RESPONSE_CHUNK_FRAME_TYPE {
            let chunk = match decode_bridge_response_chunk(&connection.read_buffer) {
                Ok(chunk) => chunk,
                Err(error) => {
                    let _ = tx
                        .send(Err(io::Error::new(ErrorKind::InvalidData, error)))
                        .await;
                    return;
                }
            };
            if chunk.is_empty() {
                continue;
            }
            total_body_bytes = match total_body_bytes.checked_add(chunk.len()) {
                Some(value) => value,
                None => {
                    let _ = tx
                        .send(Err(io::Error::new(
                            ErrorKind::InvalidData,
                            "bridge response body length overflow",
                        )))
                        .await;
                    return;
                }
            };
            if total_body_bytes > MAX_PROXY_BODY_BYTES {
                let _ = tx
                    .send(Err(io::Error::new(
                        ErrorKind::InvalidData,
                        format!("bridge response body too large: {total_body_bytes}"),
                    )))
                    .await;
                return;
            }
            if tx.send(Ok(chunk)).await.is_err() {
                return;
            }
            continue;
        }

        if frame_type == BRIDGE_RESPONSE_END_FRAME_TYPE {
            if let Err(error) = decode_bridge_response_end(&connection.read_buffer) {
                let _ = tx
                    .send(Err(io::Error::new(ErrorKind::InvalidData, error)))
                    .await;
                return;
            }
            bridge_pool.release(connection);
            return;
        }

        let _ = tx
            .send(Err(io::Error::new(
                ErrorKind::InvalidData,
                format!("unexpected bridge response frame type: {frame_type}"),
            )))
            .await;
        return;
    }
}

/// Tunnels upgraded websocket bytes between frontend connection and bridge.
async fn run_websocket_tunnel(
    upgrade: OnUpgrade,
    bridge_socket: BoxBridgeStream,
) -> Result<(), String> {
    let upgraded = upgrade
        .await
        .map_err(|error| format!("frontend upgrade failed: {error}"))?;
    let upgraded = TokioIo::new(upgraded);
    let (mut frontend_reader, mut frontend_writer) = tokio::io::split(upgraded);
    let (mut bridge_reader, mut bridge_writer) = tokio::io::split(bridge_socket);

    let frontend_to_bridge = tokio::spawn(async move {
        let mut buffer = vec![0_u8; BRIDGE_BODY_CHUNK_BYTES];
        loop {
            let read = frontend_reader
                .read(&mut buffer)
                .await
                .map_err(|error| format!("read upgraded frontend stream failed: {error}"))?;
            if read == 0 {
                write_bridge_tunnel_close_frame(&mut bridge_writer).await?;
                return Ok::<(), String>(());
            }
            write_bridge_tunnel_chunk_frame(&mut bridge_writer, &buffer[..read]).await?;
        }
    });

    let bridge_to_frontend = tokio::spawn(async move {
        loop {
            let payload = match read_bridge_frame(&mut bridge_reader).await? {
                Some(payload) => payload,
                None => return Ok::<(), String>(()),
            };
            let frame_type = peek_bridge_frame_type(&payload)?;
            if frame_type == BRIDGE_TUNNEL_CHUNK_FRAME_TYPE {
                let chunk = decode_bridge_tunnel_chunk(&payload)?;
                if !chunk.is_empty() {
                    frontend_writer.write_all(&chunk).await.map_err(|error| {
                        format!("write upgraded frontend stream failed: {error}")
                    })?;
                }
                continue;
            }
            if frame_type == BRIDGE_TUNNEL_CLOSE_FRAME_TYPE {
                decode_bridge_tunnel_close(&payload)?;
                return Ok(());
            }
            return Err(format!("unexpected bridge tunnel frame type: {frame_type}"));
        }
    });

    let (frontend_result, bridge_result) = tokio::join!(frontend_to_bridge, bridge_to_frontend);

    match frontend_result {
        Ok(Ok(())) => {}
        Ok(Err(error)) => return Err(error),
        Err(error) => return Err(format!("frontend-to-bridge tunnel task failed: {error}")),
    }

    match bridge_result {
        Ok(Ok(())) => {}
        Ok(Err(error)) => return Err(error),
        Err(error) => return Err(format!("bridge-to-frontend tunnel task failed: {error}")),
    }

    Ok(())
}

/// Decodes single-frame bridge response payload.
fn decode_bridge_response(payload: &[u8]) -> Result<BridgeResponse, String> {
    let mut reader = BridgeByteReader::new(payload);
    let version = reader.get_u8()?;
    if !is_supported_bridge_protocol_version(version) {
        return Err(format!("unsupported bridge protocol version: {version}"));
    }
    let frame_type = reader.get_u8()?;
    if !is_bridge_response_frame_type(frame_type) {
        return Err(format!("invalid bridge response frame type: {frame_type}"));
    }
    let tokenized_names = is_bridge_response_frame_type_tokenized(frame_type);

    let status = reader.get_u16()?;
    let header_count = reader.get_u32()? as usize;
    let mut headers = Vec::with_capacity(header_count);
    for _ in 0..header_count {
        let header_name = decode_bridge_response_header_name(&mut reader, tokenized_names)?;
        let value = reader.get_bytes()?;
        let Some(header_name) = header_name else {
            continue;
        };
        let Ok(header_value) = axum::http::HeaderValue::from_bytes(value) else {
            continue;
        };
        headers.push((header_name, header_value));
    }
    let body = reader.get_bytes()?;
    reader.ensure_done()?;
    let body_bytes = Bytes::copy_from_slice(body);

    Ok(BridgeResponse {
        status,
        headers,
        body_bytes,
    })
}

/// Decodes response-start frame and extracted headers.
fn decode_bridge_response_start(
    payload: &[u8],
) -> Result<
    (
        u16,
        Vec<(axum::http::header::HeaderName, axum::http::HeaderValue)>,
    ),
    String,
> {
    let mut reader = BridgeByteReader::new(payload);
    let version = reader.get_u8()?;
    if !is_supported_bridge_protocol_version(version) {
        return Err(format!("unsupported bridge protocol version: {version}"));
    }
    let frame_type = reader.get_u8()?;
    if !is_bridge_response_start_frame_type(frame_type) {
        return Err(format!(
            "invalid bridge response start frame type: {frame_type}"
        ));
    }
    let tokenized_names = is_bridge_response_start_frame_type_tokenized(frame_type);
    let status = reader.get_u16()?;
    let header_count = reader.get_u32()? as usize;
    let mut headers = Vec::with_capacity(header_count);
    for _ in 0..header_count {
        let header_name = decode_bridge_response_header_name(&mut reader, tokenized_names)?;
        let value = reader.get_bytes()?;
        let Some(header_name) = header_name else {
            continue;
        };
        let Ok(header_value) = axum::http::HeaderValue::from_bytes(value) else {
            continue;
        };
        headers.push((header_name, header_value));
    }
    reader.ensure_done()?;
    Ok((status, headers))
}

/// Decodes one response chunk frame payload.
fn decode_bridge_response_chunk(payload: &[u8]) -> Result<Bytes, String> {
    let mut reader = BridgeByteReader::new(payload);
    let version = reader.get_u8()?;
    if !is_supported_bridge_protocol_version(version) {
        return Err(format!("unsupported bridge protocol version: {version}"));
    }
    let frame_type = reader.get_u8()?;
    if frame_type != BRIDGE_RESPONSE_CHUNK_FRAME_TYPE {
        return Err(format!(
            "invalid bridge response chunk frame type: {frame_type}"
        ));
    }
    let chunk = reader.get_bytes()?;
    reader.ensure_done()?;
    Ok(Bytes::copy_from_slice(chunk))
}

/// Validates and decodes response end frame.
fn decode_bridge_response_end(payload: &[u8]) -> Result<(), String> {
    let mut reader = BridgeByteReader::new(payload);
    let version = reader.get_u8()?;
    if !is_supported_bridge_protocol_version(version) {
        return Err(format!("unsupported bridge protocol version: {version}"));
    }
    let frame_type = reader.get_u8()?;
    if frame_type != BRIDGE_RESPONSE_END_FRAME_TYPE {
        return Err(format!(
            "invalid bridge response end frame type: {frame_type}"
        ));
    }
    reader.ensure_done()
}

/// Decodes one tunnel chunk frame.
fn decode_bridge_tunnel_chunk(payload: &[u8]) -> Result<Bytes, String> {
    let mut reader = BridgeByteReader::new(payload);
    let version = reader.get_u8()?;
    if !is_supported_bridge_protocol_version(version) {
        return Err(format!("unsupported bridge protocol version: {version}"));
    }
    let frame_type = reader.get_u8()?;
    if frame_type != BRIDGE_TUNNEL_CHUNK_FRAME_TYPE {
        return Err(format!(
            "invalid bridge tunnel chunk frame type: {frame_type}"
        ));
    }
    let chunk = reader.get_bytes()?;
    reader.ensure_done()?;
    Ok(Bytes::copy_from_slice(chunk))
}

/// Validates and decodes tunnel close frame.
fn decode_bridge_tunnel_close(payload: &[u8]) -> Result<(), String> {
    let mut reader = BridgeByteReader::new(payload);
    let version = reader.get_u8()?;
    if !is_supported_bridge_protocol_version(version) {
        return Err(format!("unsupported bridge protocol version: {version}"));
    }
    let frame_type = reader.get_u8()?;
    if frame_type != BRIDGE_TUNNEL_CLOSE_FRAME_TYPE {
        return Err(format!(
            "invalid bridge tunnel close frame type: {frame_type}"
        ));
    }
    reader.ensure_done()
}

/// Peeks frame type after protocol version validation.
fn peek_bridge_frame_type(payload: &[u8]) -> Result<u8, String> {
    if payload.len() < 2 {
        return Err("truncated bridge payload".to_string());
    }
    let version = payload[0];
    if !is_supported_bridge_protocol_version(version) {
        return Err(format!("unsupported bridge protocol version: {version}"));
    }
    Ok(payload[1])
}

/// Returns true when version is accepted by current runtime.
fn is_supported_bridge_protocol_version(version: u8) -> bool {
    version == BRIDGE_PROTOCOL_VERSION || version == BRIDGE_PROTOCOL_VERSION_LEGACY
}

/// Maps tokenized/literal response frame type acceptance.
fn is_bridge_response_frame_type(frame_type: u8) -> bool {
    frame_type == BRIDGE_RESPONSE_FRAME_TYPE || frame_type == BRIDGE_RESPONSE_FRAME_TYPE_TOKENIZED
}

/// Returns whether frame type is tokenized single-frame response.
fn is_bridge_response_frame_type_tokenized(frame_type: u8) -> bool {
    frame_type == BRIDGE_RESPONSE_FRAME_TYPE_TOKENIZED
}

/// Returns whether frame type is response-start (literal or tokenized).
fn is_bridge_response_start_frame_type(frame_type: u8) -> bool {
    frame_type == BRIDGE_RESPONSE_START_FRAME_TYPE
        || frame_type == BRIDGE_RESPONSE_START_FRAME_TYPE_TOKENIZED
}

/// Returns whether response-start uses tokenized header names.
fn is_bridge_response_start_frame_type_tokenized(frame_type: u8) -> bool {
    frame_type == BRIDGE_RESPONSE_START_FRAME_TYPE_TOKENIZED
}

/// Decodes response header name from either literal or tokenized encoding.
fn decode_bridge_response_header_name(
    reader: &mut BridgeByteReader<'_>,
    tokenized: bool,
) -> Result<Option<axum::http::header::HeaderName>, String> {
    if !tokenized {
        let name = reader.get_bytes()?;
        return Ok(axum::http::header::HeaderName::from_bytes(name).ok());
    }

    let token = reader.get_u16()?;
    if token == BRIDGE_HEADER_NAME_LITERAL_TOKEN {
        let name = reader.get_bytes()?;
        return Ok(axum::http::header::HeaderName::from_bytes(name).ok());
    }

    let name = bridge_header_name_from_token_header_name(token)
        .ok_or_else(|| format!("invalid bridge header name token: {token}"))?;
    Ok(Some(name))
}

/// Maps header-name tokens to canonical header names.
fn bridge_header_name_from_token_header_name(token: u16) -> Option<axum::http::header::HeaderName> {
    use axum::http::header;

    match token {
        0 => Some(header::HOST),
        1 => Some(header::CONNECTION),
        2 => Some(header::USER_AGENT),
        3 => Some(header::ACCEPT),
        4 => Some(header::ACCEPT_ENCODING),
        5 => Some(header::ACCEPT_LANGUAGE),
        6 => Some(header::CONTENT_TYPE),
        7 => Some(header::CONTENT_LENGTH),
        8 => Some(header::TRANSFER_ENCODING),
        9 => Some(header::COOKIE),
        10 => Some(header::SET_COOKIE),
        11 => Some(header::CACHE_CONTROL),
        12 => Some(header::PRAGMA),
        13 => Some(header::UPGRADE),
        14 => Some(header::AUTHORIZATION),
        15 => Some(header::ORIGIN),
        16 => Some(header::REFERER),
        17 => Some(header::LOCATION),
        18 => Some(header::SERVER),
        19 => Some(header::DATE),
        20 => Some(axum::http::header::HeaderName::from_static(
            "x-forwarded-for",
        )),
        21 => Some(axum::http::header::HeaderName::from_static(
            "x-forwarded-proto",
        )),
        22 => Some(axum::http::header::HeaderName::from_static(
            "x-forwarded-host",
        )),
        23 => Some(axum::http::header::HeaderName::from_static(
            "x-forwarded-port",
        )),
        24 => Some(axum::http::header::HeaderName::from_static("x-request-id")),
        25 => Some(axum::http::header::HeaderName::from_static(
            "sec-websocket-key",
        )),
        26 => Some(axum::http::header::HeaderName::from_static(
            "sec-websocket-version",
        )),
        27 => Some(axum::http::header::HeaderName::from_static(
            "sec-websocket-protocol",
        )),
        28 => Some(axum::http::header::HeaderName::from_static(
            "sec-websocket-extensions",
        )),
        _ => None,
    }
}

/// Writes one length-prefixed bridge frame.
async fn write_bridge_frame<S: AsyncWrite + Unpin + ?Sized>(
    socket: &mut S,
    payload: &[u8],
) -> Result<(), String> {
    if payload.len() > MAX_BRIDGE_FRAME_BYTES {
        return Err(format!("bridge frame too large: {}", payload.len()));
    }
    let payload_len = u32::try_from(payload.len())
        .map_err(|_| "bridge frame length does not fit u32".to_string())?;
    let header = payload_len.to_be_bytes();
    if payload.is_empty() {
        socket
            .write_all(&header)
            .await
            .map_err(|error| format!("write frame header failed: {error}"))?;
        return Ok(());
    }
    if payload.len() <= BRIDGE_COALESCE_WRITE_THRESHOLD_BYTES {
        let mut out = Vec::with_capacity(4 + payload.len());
        out.extend_from_slice(&header);
        out.extend_from_slice(payload);
        socket
            .write_all(&out)
            .await
            .map_err(|error| format!("write frame payload failed: {error}"))?;
        return Ok(());
    }
    write_all_vectored(socket, &[&header, payload])
        .await
        .map_err(|error| format!("write frame payload failed: {error}"))?;
    Ok(())
}

/// Writes tunnel close frame.
async fn write_bridge_tunnel_close_frame<S: AsyncWrite + Unpin + ?Sized>(
    socket: &mut S,
) -> Result<(), String> {
    let payload = [BRIDGE_PROTOCOL_VERSION, BRIDGE_TUNNEL_CLOSE_FRAME_TYPE];
    write_bridge_frame(socket, &payload).await
}

/// Writes a sequence of byte slices using vectored IO when possible.
async fn write_all_vectored<S: AsyncWrite + Unpin + ?Sized>(
    socket: &mut S,
    buffers: &[&[u8]],
) -> io::Result<()> {
    let mut index = 0usize;
    let mut offset = 0usize;

    while index < buffers.len() {
        while index < buffers.len() && offset == buffers[index].len() {
            index += 1;
            offset = 0;
        }
        if index >= buffers.len() {
            break;
        }

        let remaining_buffers = buffers.len() - index;
        let written = if remaining_buffers <= 3 {
            let mut io_slices = [IoSlice::new(&[]), IoSlice::new(&[]), IoSlice::new(&[])];
            io_slices[0] = IoSlice::new(&buffers[index][offset..]);
            let mut slice_len = 1usize;
            if remaining_buffers >= 2 {
                io_slices[1] = IoSlice::new(buffers[index + 1]);
                slice_len = 2;
            }
            if remaining_buffers >= 3 {
                io_slices[2] = IoSlice::new(buffers[index + 2]);
                slice_len = 3;
            }
            socket.write_vectored(&io_slices[..slice_len]).await?
        } else {
            let mut io_slices = Vec::with_capacity(remaining_buffers);
            io_slices.push(IoSlice::new(&buffers[index][offset..]));
            for buffer in &buffers[(index + 1)..] {
                io_slices.push(IoSlice::new(buffer));
            }
            socket.write_vectored(&io_slices).await?
        };
        if written == 0 {
            return Err(io::Error::new(
                ErrorKind::WriteZero,
                "failed to write bridge frame bytes",
            ));
        }

        let mut remaining = written;
        while index < buffers.len() && remaining > 0 {
            let available = buffers[index].len() - offset;
            if remaining < available {
                offset += remaining;
                remaining = 0;
            } else {
                remaining -= available;
                index += 1;
                offset = 0;
            }
        }
    }

    Ok(())
}

/// Reads one length-prefixed bridge frame into a fresh buffer.
async fn read_bridge_frame<S: AsyncRead + Unpin + ?Sized>(
    socket: &mut S,
) -> Result<Option<Vec<u8>>, String> {
    let mut payload = Vec::new();
    let has_frame = read_bridge_frame_reuse(socket, &mut payload).await?;
    if !has_frame {
        return Ok(None);
    }
    Ok(Some(payload))
}

/// Reads one length-prefixed bridge frame into a reused buffer.
async fn read_bridge_frame_reuse<S: AsyncRead + Unpin + ?Sized>(
    socket: &mut S,
    payload: &mut Vec<u8>,
) -> Result<bool, String> {
    let mut header = [0_u8; 4];
    let mut read = 0;
    while read < header.len() {
        let n = socket
            .read(&mut header[read..])
            .await
            .map_err(|error| format!("read frame header failed: {error}"))?;
        if n == 0 {
            if read == 0 {
                return Ok(false);
            }
            return Err("bridge closed connection while reading frame header".to_string());
        }
        read += n;
    }

    let payload_len = u32::from_be_bytes(header) as usize;
    if payload_len > MAX_BRIDGE_FRAME_BYTES {
        return Err(format!("bridge frame too large: {payload_len}"));
    }

    payload.resize(payload_len, 0);
    let mut read = 0;
    while read < payload_len {
        let n = socket
            .read(&mut payload[read..payload_len])
            .await
            .map_err(|error| format!("read frame payload failed: {error}"))?;
        if n == 0 {
            return Err("bridge stream ended before response payload".to_string());
        }
        read += n;
    }

    Ok(true)
}

/// Minimal binary writer used by bridge payload codec.
struct BridgeByteWriter {
    bytes: Vec<u8>,
}

impl BridgeByteWriter {
    fn new() -> Self {
        Self { bytes: Vec::new() }
    }

    fn reserve(&mut self, additional: usize) {
        self.bytes.reserve(additional);
    }

    fn reserve_u32(&mut self) -> usize {
        let pos = self.bytes.len();
        self.bytes.extend_from_slice(&0_u32.to_be_bytes());
        pos
    }

    fn patch_u32(&mut self, pos: usize, value: u32) {
        self.bytes[pos..pos + 4].copy_from_slice(&value.to_be_bytes());
    }

    fn into_inner(self) -> Vec<u8> {
        self.bytes
    }

    fn put_u8(&mut self, value: u8) {
        self.bytes.push(value);
    }

    fn put_u16(&mut self, value: u16) {
        self.bytes.extend_from_slice(&value.to_be_bytes());
    }

    fn put_u32(&mut self, value: u32) {
        self.bytes.extend_from_slice(&value.to_be_bytes());
    }

    fn put_string(&mut self, value: &str) -> Result<(), String> {
        self.put_bytes(value.as_bytes())
    }

    fn put_bytes(&mut self, bytes: &[u8]) -> Result<(), String> {
        let len = u32::try_from(bytes.len())
            .map_err(|_| "bridge field length does not fit u32".to_string())?;
        self.put_u32(len);
        self.bytes.extend_from_slice(bytes);
        Ok(())
    }
}

/// Minimal binary reader used by bridge payload codec.
struct BridgeByteReader<'a> {
    bytes: &'a [u8],
    offset: usize,
}

impl<'a> BridgeByteReader<'a> {
    fn new(bytes: &'a [u8]) -> Self {
        Self { bytes, offset: 0 }
    }

    fn get_u8(&mut self) -> Result<u8, String> {
        let bytes = self.get_exact(1)?;
        Ok(bytes[0])
    }

    fn get_u16(&mut self) -> Result<u16, String> {
        let bytes = self.get_exact(2)?;
        Ok(u16::from_be_bytes([bytes[0], bytes[1]]))
    }

    fn get_u32(&mut self) -> Result<u32, String> {
        let bytes = self.get_exact(4)?;
        Ok(u32::from_be_bytes([bytes[0], bytes[1], bytes[2], bytes[3]]))
    }

    fn get_bytes(&mut self) -> Result<&'a [u8], String> {
        let (start, length) = self.get_bytes_range()?;
        Ok(&self.bytes[start..start + length])
    }

    fn get_bytes_range(&mut self) -> Result<(usize, usize), String> {
        let length = self.get_u32()? as usize;
        if self.offset + length > self.bytes.len() {
            return Err("truncated bridge payload".to_string());
        }
        let start = self.offset;
        self.offset += length;
        Ok((start, length))
    }

    fn ensure_done(&self) -> Result<(), String> {
        if self.offset == self.bytes.len() {
            return Ok(());
        }
        Err(format!(
            "unexpected trailing bridge payload bytes: {}",
            self.bytes.len() - self.offset
        ))
    }

    fn get_exact(&mut self, len: usize) -> Result<&'a [u8], String> {
        if self.offset + len > self.bytes.len() {
            return Err("truncated bridge payload".to_string());
        }
        let start = self.offset;
        self.offset += len;
        Ok(&self.bytes[start..start + len])
    }
}

/// Maps HTTP versions to bridge protocol strings consumed by Dart.
fn http_version_to_protocol(version: Version) -> &'static str {
    match version {
        Version::HTTP_09 => "0.9",
        Version::HTTP_10 => "1.0",
        Version::HTTP_11 => "1.1",
        Version::HTTP_2 => "2",
        Version::HTTP_3 => "3",
        _ => "1.1",
    }
}

/// Splits `path?query` into `(path, query)` without allocations.
fn split_path_and_query_ref(path_and_query: &str) -> (&str, &str) {
    match path_and_query.split_once('?') {
        Some((path, query)) => (path, query),
        None => (path_and_query, ""),
    }
}

/// Returns true when request headers indicate websocket upgrade.
fn is_websocket_upgrade(headers: &axum::http::HeaderMap) -> bool {
    let has_upgrade = headers
        .get("connection")
        .and_then(|value| value.to_str().ok())
        .map(|value| value.to_ascii_lowercase().contains("upgrade"))
        .unwrap_or(false);
    let websocket_upgrade = headers
        .get("upgrade")
        .and_then(|value| value.to_str().ok())
        .map(|value| value.eq_ignore_ascii_case("websocket"))
        .unwrap_or(false);
    has_upgrade && websocket_upgrade
}

/// Creates plain-text error response used for bridge/proxy failures.
fn text_response(status: StatusCode, message: impl Into<String>) -> Response<Body> {
    let mut response = Response::new(Body::from(message.into()));
    *response.status_mut() = status;
    response
}
