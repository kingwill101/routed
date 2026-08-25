use crate::*;

/// Appends header value bytes to [output], rewriting unsupported bytes.
///
/// Returns `true` when any byte was rewritten.
pub(crate) fn append_rewritten_header_value(output: &mut Vec<u8>, value: &[u8]) -> bool {
    let mut rewritten = false;
    for byte in value {
        if is_invalid_http1_header_value_byte(*byte) {
            rewritten = true;
            // `"` is legal at the HTTP header level but invalid for cookie
            // value validators. This preserves lazy header-validation behavior:
            // - request passes when header is untouched,
            // - typed cookie parsing still throws `Invalid cookie value`.
            output.push(b'"');
            continue;
        }
        output.push(*byte);
    }
    rewritten
}

/// Returns whether request head carries an invalid transfer-encoding header.
pub(crate) fn request_has_invalid_transfer_encoding(request_head: &[u8]) -> bool {
    let Some(first_line_end) = find_crlf(request_head) else {
        return false;
    };
    let mut line_start = first_line_end + 2;
    while line_start < request_head.len() {
        let remaining = &request_head[line_start..];
        let Some(relative_line_end) = find_crlf(remaining) else {
            break;
        };
        let line_end = line_start + relative_line_end;
        if line_end == line_start {
            break;
        }
        let line = &request_head[line_start..line_end];
        line_start = line_end + 2;
        let Some(colon_index) = line.iter().position(|byte| *byte == b':') else {
            continue;
        };
        let (name, value_with_colon) = line.split_at(colon_index);
        if !name.eq_ignore_ascii_case(TRANSFER_ENCODING_HEADER.as_bytes()) {
            continue;
        }
        let value_bytes = value_with_colon.get(1..).unwrap_or_default();
        let Ok(value) = std::str::from_utf8(value_bytes) else {
            return true;
        };
        if !transfer_encoding_is_chunked_final(value.trim()) {
            return true;
        }
    }
    false
}

/// Returns whether one host header value cannot be parsed as HTTP authority.
pub(crate) fn host_header_value_is_invalid(value: &[u8]) -> bool {
    let Ok(value) = std::str::from_utf8(value) else {
        return true;
    };
    // HTTP allows optional whitespace around header values.
    let trimmed = value.trim();
    if trimmed.is_empty() {
        return true;
    }
    trimmed.parse::<axum::http::uri::Authority>().is_err()
}

/// Returns whether transfer-encoding should be rewritten before Hyper parsing.
///
/// Rules:
/// - invalid transfer-encoding values are rewritten for lenient parsing;
/// - `GET`/`HEAD` with transfer-encoding and no prefetched body bytes are
///   rewritten to avoid hanging waiting for absent chunk framing.
pub(crate) fn request_should_rewrite_transfer_encoding(
    request_head: &[u8],
    has_prefetched_body_bytes: bool,
) -> bool {
    if request_has_invalid_transfer_encoding(request_head) {
        return true;
    }
    if !has_prefetched_body_bytes
        && request_method_is_get_or_head(request_head)
        && !request_has_content_length_header(request_head)
    {
        return true;
    }
    false
}

/// Returns whether request head contains a header named [name].
pub(crate) fn request_has_header(request_head: &[u8], name: &str) -> bool {
    let needle = format!("{name}:");
    contains_ascii_case_insensitive(request_head, needle.as_bytes())
}

/// Returns whether a header value contains token [token] (ASCII case-folded).
pub(crate) fn header_value_contains_token(value: &str, token: &str) -> bool {
    for candidate in value.split(',') {
        if candidate.trim().eq_ignore_ascii_case(token) {
            return true;
        }
    }
    false
}

/// Returns whether request head has `connection: ...upgrade...`.
pub(crate) fn request_connection_has_upgrade_token(request_head: &[u8]) -> bool {
    let Some(first_line_end) = find_crlf(request_head) else {
        return false;
    };
    let mut line_start = first_line_end + 2;
    while line_start < request_head.len() {
        let remaining = &request_head[line_start..];
        let Some(relative_line_end) = find_crlf(remaining) else {
            break;
        };
        let line_end = line_start + relative_line_end;
        if line_end == line_start {
            break;
        }
        let line = &request_head[line_start..line_end];
        line_start = line_end + 2;
        let Some(colon_index) = line.iter().position(|byte| *byte == b':') else {
            continue;
        };
        let (name, value_with_colon) = line.split_at(colon_index);
        if !name.eq_ignore_ascii_case(CONNECTION_HEADER.as_bytes()) {
            continue;
        }
        let value = value_with_colon.get(1..).unwrap_or_default();
        let Ok(value) = std::str::from_utf8(value) else {
            continue;
        };
        if header_value_contains_token(value, "upgrade") {
            return true;
        }
    }
    false
}

/// Returns whether request is an HTTP upgrade request.
pub(crate) fn request_is_upgrade(request_head: &[u8]) -> bool {
    request_has_header(request_head, "upgrade")
        && request_connection_has_upgrade_token(request_head)
}

/// Returns whether request connection headers should be rewritten before Hyper
/// parsing.
///
/// Hyper strips headers listed in `Connection` tokens. dart:io exposes those
/// headers as received, so for non-upgrade requests we rewrite `Connection`
/// into an internal header and restore it post-parse.
pub(crate) fn request_should_rewrite_connection_header(request_head: &[u8]) -> bool {
    request_has_header(request_head, CONNECTION_HEADER) && !request_is_upgrade(request_head)
}
