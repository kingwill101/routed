use crate::*;

/// Decodes single-frame bridge response payload.
pub(crate) fn decode_bridge_response(payload: &[u8]) -> Result<BridgeResponse, String> {
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
pub(crate) fn decode_bridge_response_start(
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
pub(crate) fn decode_bridge_response_chunk(payload: &[u8]) -> Result<Bytes, String> {
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
pub(crate) fn decode_bridge_response_end(payload: &[u8]) -> Result<(), String> {
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
pub(crate) fn decode_bridge_tunnel_chunk(payload: &[u8]) -> Result<Bytes, String> {
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
pub(crate) fn decode_bridge_tunnel_close(payload: &[u8]) -> Result<(), String> {
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
pub(crate) fn peek_bridge_frame_type(payload: &[u8]) -> Result<u8, String> {
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
pub(crate) fn is_supported_bridge_protocol_version(version: u8) -> bool {
    version == BRIDGE_PROTOCOL_VERSION || version == BRIDGE_PROTOCOL_VERSION_LEGACY
}

/// Maps tokenized/literal response frame type acceptance.
pub(crate) fn is_bridge_response_frame_type(frame_type: u8) -> bool {
    frame_type == BRIDGE_RESPONSE_FRAME_TYPE || frame_type == BRIDGE_RESPONSE_FRAME_TYPE_TOKENIZED
}

/// Returns whether frame type is tokenized single-frame response.
pub(crate) fn is_bridge_response_frame_type_tokenized(frame_type: u8) -> bool {
    frame_type == BRIDGE_RESPONSE_FRAME_TYPE_TOKENIZED
}

/// Returns whether frame type is response-start (literal or tokenized).
pub(crate) fn is_bridge_response_start_frame_type(frame_type: u8) -> bool {
    frame_type == BRIDGE_RESPONSE_START_FRAME_TYPE
        || frame_type == BRIDGE_RESPONSE_START_FRAME_TYPE_TOKENIZED
}

/// Returns whether response-start uses tokenized header names.
pub(crate) fn is_bridge_response_start_frame_type_tokenized(frame_type: u8) -> bool {
    frame_type == BRIDGE_RESPONSE_START_FRAME_TYPE_TOKENIZED
}

/// Decodes response header name from either literal or tokenized encoding.
pub(crate) fn decode_bridge_response_header_name(
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
pub(crate) fn bridge_header_name_from_token_header_name(
    token: u16,
) -> Option<axum::http::header::HeaderName> {
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
