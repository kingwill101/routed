use crate::*;

// Bridge protocol codec used between Rust transport runtime and Dart runtime.
//
// This module handles:
// - request encoding (single-frame and streaming),
// - response decoding (single-frame and streaming),
// - websocket tunnel frame relay,
// - compact tokenized header-name mapping.
//
// Frame envelope:
// - outer prefix: `u32` big-endian payload length
// - payload: `{version: u8, frame_type: u8, ...frame-specific fields...}`
//
// Most fields in frame payloads are length-prefixed bytes (`u32 + bytes`).
// Tokenized header formats replace common header names with `u16` IDs to
// reduce frame size and UTF-8 parsing overhead.

/// Encodes bridge request start frame for streaming request bodies.
pub(crate) fn encode_bridge_request_start(
    request: &BridgeRequestRef<'_>,
) -> Result<Vec<u8>, String> {
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
pub(crate) fn encode_bridge_request(
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
pub(crate) fn encode_bridge_request_headers(
    writer: &mut BridgeByteWriter,
    request: &BridgeRequestRef<'_>,
) -> Result<(), String> {
    if request.headers.is_empty() {
        writer.put_u32(0);
        return Ok(());
    }

    let count_pos = writer.reserve_u32();
    let mut count: u32 = 0;
    let has_sanitized_connection_header = request.headers.contains_key(SANITIZED_CONNECTION_HEADER);
    for (name, value) in request.headers.iter() {
        if has_sanitized_connection_header && name.as_str() == CONNECTION_HEADER {
            // Ignore Hyper framing connection header when the original value
            // has been preserved in the sanitized compatibility header.
            continue;
        }
        let header_name = if name.as_str() == SANITIZED_CONNECTION_HEADER {
            CONNECTION_HEADER
        } else {
            name.as_str()
        };
        let Ok(value) = value.to_str() else {
            continue;
        };
        if header_name == CONNECTION_HEADER {
            let mut emitted_connection_token = false;
            for token in value.split(',') {
                let token = token.trim();
                if token.is_empty() {
                    continue;
                }
                if token.eq_ignore_ascii_case(EMPTY_CONNECTION_SENTINEL) {
                    continue;
                }
                count = count
                    .checked_add(1)
                    .ok_or_else(|| "bridge request has too many headers".to_string())?;
                write_bridge_header_name(writer, header_name)?;
                writer.put_string(token)?;
                emitted_connection_token = true;
            }
            if !emitted_connection_token {
                // Preserve syntactically-empty `connection:` values so Dart
                // header validators can surface the same invalid-header errors
                // as `dart:io` instead of observing the header as absent.
                count = count
                    .checked_add(1)
                    .ok_or_else(|| "bridge request has too many headers".to_string())?;
                write_bridge_header_name(writer, header_name)?;
                writer.put_string("")?;
            }
            continue;
        }
        count = count
            .checked_add(1)
            .ok_or_else(|| "bridge request has too many headers".to_string())?;
        write_bridge_header_name(writer, header_name)?;
        writer.put_string(value)?;
    }
    writer.patch_u32(count_pos, count);
    Ok(())
}

/// Encodes request end frame for streaming request bodies.
pub(crate) fn encode_bridge_request_end() -> Vec<u8> {
    vec![BRIDGE_PROTOCOL_VERSION, BRIDGE_REQUEST_END_FRAME_TYPE]
}

/// Writes a tokenized header name when available, else literal form.
pub(crate) fn write_bridge_header_name(
    writer: &mut BridgeByteWriter,
    name: &str,
) -> Result<(), String> {
    if let Some(token) = bridge_header_name_token(name) {
        writer.put_u16(token);
        return Ok(());
    }
    writer.put_u16(BRIDGE_HEADER_NAME_LITERAL_TOKEN);
    writer.put_string(name)
}

/// Maps lowercase header names to compact bridge tokens.
pub(crate) fn bridge_header_name_token(name: &str) -> Option<u16> {
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
pub(crate) fn encode_bridge_request_chunk_payload(chunk: &[u8]) -> Result<Vec<u8>, String> {
    let mut writer = BridgeByteWriter::new();
    writer.reserve(6 + chunk.len());
    writer.put_u8(BRIDGE_PROTOCOL_VERSION);
    writer.put_u8(BRIDGE_REQUEST_CHUNK_FRAME_TYPE);
    writer.put_bytes(chunk)?;
    Ok(writer.into_inner())
}

/// Encodes one tunnel chunk payload.
pub(crate) fn encode_bridge_tunnel_chunk_payload(chunk: &[u8]) -> Result<Vec<u8>, String> {
    let mut writer = BridgeByteWriter::new();
    writer.reserve(6 + chunk.len());
    writer.put_u8(BRIDGE_PROTOCOL_VERSION);
    writer.put_u8(BRIDGE_TUNNEL_CHUNK_FRAME_TYPE);
    writer.put_bytes(chunk)?;
    Ok(writer.into_inner())
}

/// Encodes a tunnel-close payload.
pub(crate) fn encode_bridge_tunnel_close_payload() -> Vec<u8> {
    vec![BRIDGE_PROTOCOL_VERSION, BRIDGE_TUNNEL_CLOSE_FRAME_TYPE]
}

/// Writes one request-body chunk frame.
pub(crate) async fn write_bridge_request_chunk_frame(
    socket: &mut dyn BridgeStream,
    chunk: &[u8],
) -> Result<(), String> {
    write_bridge_chunk_frame_with_type(socket, BRIDGE_REQUEST_CHUNK_FRAME_TYPE, chunk).await
}

/// Writes one tunnel chunk frame.
pub(crate) async fn write_bridge_tunnel_chunk_frame<S: AsyncWrite + Unpin + ?Sized>(
    socket: &mut S,
    chunk: &[u8],
) -> Result<(), String> {
    write_bridge_chunk_frame_with_type(socket, BRIDGE_TUNNEL_CHUNK_FRAME_TYPE, chunk).await
}

/// Generic chunk frame writer used by request and tunnel paths.
pub(crate) async fn write_bridge_chunk_frame_with_type<S: AsyncWrite + Unpin + ?Sized>(
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
