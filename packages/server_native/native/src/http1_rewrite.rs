use crate::*;

/// Rewrites transfer-encoding headers to an internal header name.
#[cfg(test)]
pub(crate) fn rewrite_transfer_encoding_headers(request_head: &[u8]) -> Vec<u8> {
    rewrite_request_head_for_hyper(request_head, true, false)
        .unwrap_or_else(|| request_head.to_vec())
}

/// Rewrites request-head headers so Hyper can parse inputs that dart:io accepts.
///
/// Current rewrites:
/// - optional transfer-encoding header name rewrite (for TE compatibility),
/// - percent-encoding of unsupported control bytes in header values.
///
/// Returns `None` when no rewrite was needed.
pub(crate) fn rewrite_request_head_for_hyper(
    request_head: &[u8],
    rewrite_transfer_encoding: bool,
    rewrite_connection_header: bool,
) -> Option<Vec<u8>> {
    let mut output = Vec::with_capacity(request_head.len());
    let first_line_end = find_crlf(request_head)?;
    output.extend_from_slice(&request_head[..first_line_end + 2]);
    let mut rewritten = false;

    let mut line_start = first_line_end + 2;
    while line_start < request_head.len() {
        let remaining = &request_head[line_start..];
        let Some(relative_line_end) = find_crlf(remaining) else {
            output.extend_from_slice(remaining);
            break;
        };
        let line_end = line_start + relative_line_end;
        if line_end == line_start {
            output.extend_from_slice(b"\r\n");
            break;
        }
        let line = &request_head[line_start..line_end];
        line_start = line_end + 2;
        let Some(colon_index) = line.iter().position(|byte| *byte == b':') else {
            output.extend_from_slice(line);
            output.extend_from_slice(b"\r\n");
            continue;
        };
        let (name, value) = line.split_at(colon_index);
        let value = value.get(1..).unwrap_or_default();
        let invalid_host = name.eq_ignore_ascii_case(HOST_HEADER.as_bytes())
            && host_header_value_is_invalid(value);
        if rewrite_transfer_encoding
            && name.eq_ignore_ascii_case(TRANSFER_ENCODING_HEADER.as_bytes())
        {
            rewritten = true;
            output.extend_from_slice(SANITIZED_TRANSFER_ENCODING_HEADER.as_bytes());
        } else if rewrite_connection_header
            && name.eq_ignore_ascii_case(CONNECTION_HEADER.as_bytes())
        {
            rewritten = true;
            output.extend_from_slice(SANITIZED_CONNECTION_HEADER.as_bytes());
            output.push(b':');
            if value.iter().all(|byte| byte.is_ascii_whitespace()) {
                // Hyper drops all-whitespace header values in lenient mode.
                // Use a sentinel token so the header survives parsing, then
                // bridge encoding maps it back to an empty connection value.
                output.extend_from_slice(EMPTY_CONNECTION_SENTINEL.as_bytes());
            } else if append_rewritten_header_value(&mut output, value) {
                rewritten = true;
            }
            output.extend_from_slice(b"\r\n");
            continue;
        } else if invalid_host {
            rewritten = true;
            // Preserve original host for Dart-side semantics while giving Hyper
            // a parseable host value.
            output.extend_from_slice(SANITIZED_HOST_HEADER.as_bytes());
        } else {
            output.extend_from_slice(name);
        }
        output.push(b':');
        if append_rewritten_header_value(&mut output, value) {
            rewritten = true;
        }
        output.extend_from_slice(b"\r\n");
        if invalid_host {
            output.extend_from_slice(HOST_HEADER.as_bytes());
            output.extend_from_slice(b":127.0.0.1\r\n");
        }
    }
    if rewritten {
        Some(output)
    } else {
        None
    }
}

/// Reads/sanitizes one prefetched HTTP/1 request head before Hyper parsing.
pub(crate) async fn maybe_prepare_http1_prefixed_stream(
    stream: TcpStream,
) -> Result<Option<PrefixedIo<TcpStream>>, String> {
    let mut stream = stream;
    let mut prefix = Vec::<u8>::with_capacity(4096);
    let mut read_buffer = [0_u8; 2048];
    let mut idle_timeouts = 0_u8;
    while prefix.len() < 16384 {
        let read =
            match time::timeout(Duration::from_millis(5), stream.read(&mut read_buffer)).await {
                Ok(Ok(read)) => read,
                Ok(Err(error)) => {
                    return Err(format!("read request head failed: {error}"));
                }
                Err(_) => {
                    idle_timeouts = idle_timeouts.saturating_add(1);
                    if find_headers_terminator(&prefix).is_some() {
                        break;
                    }
                    // Give new connections enough time to deliver the first
                    // request head so transfer-encoding sanitization can run.
                    // Once any bytes are prefetched, keep the previous tighter
                    // timeout to avoid stalling on slowloris-style peers.
                    let max_idle_timeouts = 200;
                    if idle_timeouts >= max_idle_timeouts {
                        break;
                    }
                    continue;
                }
            };
        idle_timeouts = 0;
        if read == 0 {
            break;
        }
        prefix.extend_from_slice(&read_buffer[..read]);
        if find_headers_terminator(&prefix).is_some() {
            break;
        }
    }
    if prefix.is_empty() {
        return Ok(Some(PrefixedIo::new(stream, Vec::new())));
    }
    let Some(headers_end) = find_headers_terminator(&prefix) else {
        return Ok(Some(PrefixedIo::new(stream, prefix)));
    };
    let header_len = headers_end + 4;
    if prefix.len() == header_len {
        let request_head = &prefix[..header_len];
        let probe_for_immediate_chunk_body =
            contains_ascii_case_insensitive(request_head, b"transfer-encoding:")
                && request_method_is_get_or_head(request_head)
                && !request_has_content_length_header(request_head);
        if probe_for_immediate_chunk_body {
            // Some clients send empty chunk framing (`0\r\n\r\n`) for
            // GET/HEAD + chunked. Probe briefly so we do not rewrite TE in that
            // case and leave framing bytes as a phantom next request.
            let mut probe_timeouts = 0_u8;
            while prefix.len() == header_len && probe_timeouts < 6 {
                match time::timeout(Duration::from_millis(5), stream.read(&mut read_buffer)).await {
                    Ok(Ok(0)) => break,
                    Ok(Ok(read)) => {
                        prefix.extend_from_slice(&read_buffer[..read]);
                        break;
                    }
                    Ok(Err(error)) => {
                        return Err(format!("read request body probe failed: {error}"));
                    }
                    Err(_) => {
                        probe_timeouts = probe_timeouts.saturating_add(1);
                    }
                }
            }
        }
    }
    let request_head = &prefix[..header_len];
    if let Some(first_line_end) = find_crlf(request_head) {
        if request_target_contains_fragment(&request_head[..first_line_end]) {
            write_bad_request_and_drain(&mut stream).await?;
            return Ok(None);
        }
    }
    let rewrite_transfer_encoding =
        contains_ascii_case_insensitive(request_head, b"transfer-encoding:")
            && request_should_rewrite_transfer_encoding(request_head, header_len < prefix.len());
    let rewrite_connection_header = request_should_rewrite_connection_header(request_head);
    let rewrite_invalid_value_bytes =
        request_head_contains_invalid_header_value_bytes(request_head);
    if !rewrite_transfer_encoding && !rewrite_connection_header && !rewrite_invalid_value_bytes {
        return Ok(Some(PrefixedIo::new(stream, prefix)));
    }
    let Some(mut sanitized) = rewrite_request_head_for_hyper(
        request_head,
        rewrite_transfer_encoding,
        rewrite_connection_header,
    ) else {
        return Ok(Some(PrefixedIo::new(stream, prefix)));
    };
    if header_len < prefix.len() {
        sanitized.extend_from_slice(&prefix[header_len..]);
    }
    Ok(Some(PrefixedIo::new(stream, sanitized)))
}
