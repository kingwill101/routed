use crate::*;

pub(crate) async fn write_bad_request_and_drain(stream: &mut TcpStream) -> Result<(), String> {
    if let Err(error) = stream.write_all(BAD_REQUEST_RESPONSE_BYTES).await {
        return Err(format!("write bad request response failed: {error}"));
    }
    let _ = stream.flush().await;
    let mut drain_buffer = [0_u8; 1024];
    loop {
        match time::timeout(Duration::from_millis(25), stream.read(&mut drain_buffer)).await {
            Ok(Ok(0)) => break,
            Ok(Ok(_)) => continue,
            Ok(Err(_)) | Err(_) => break,
        }
    }
    Ok(())
}

/// Returns the index of the first CRLF line terminator, if present.
pub(crate) fn find_crlf(bytes: &[u8]) -> Option<usize> {
    if bytes.len() < 2 {
        return None;
    }
    (0..(bytes.len() - 1)).find(|&index| bytes[index] == b'\r' && bytes[index + 1] == b'\n')
}

/// Returns the index of the first HTTP header terminator (`\r\n\r\n`).
pub(crate) fn find_headers_terminator(bytes: &[u8]) -> Option<usize> {
    if bytes.len() < 4 {
        return None;
    }
    (0..(bytes.len() - 3)).find(|&index| {
        bytes[index] == b'\r'
            && bytes[index + 1] == b'\n'
            && bytes[index + 2] == b'\r'
            && bytes[index + 3] == b'\n'
    })
}

/// Returns `true` when the HTTP/1 request-line target contains a `#` fragment.
pub(crate) fn request_target_contains_fragment(request_line: &[u8]) -> bool {
    let Some(first_space) = request_line.iter().position(|byte| *byte == b' ') else {
        return false;
    };
    let after_method = first_space + 1;
    if after_method >= request_line.len() {
        return false;
    }
    let Some(relative_second_space) = request_line[after_method..]
        .iter()
        .position(|byte| *byte == b' ')
    else {
        return false;
    };
    let second_space = after_method + relative_second_space;
    if second_space <= after_method {
        return false;
    }
    request_line[after_method..second_space].contains(&b'#')
}

/// Returns whether `haystack` contains `needle` using ASCII case folding.
pub(crate) fn contains_ascii_case_insensitive(haystack: &[u8], needle: &[u8]) -> bool {
    if needle.is_empty() {
        return true;
    }
    if haystack.len() < needle.len() {
        return false;
    }
    haystack.windows(needle.len()).any(|window| {
        window
            .iter()
            .zip(needle.iter())
            .all(|(a, b)| a.eq_ignore_ascii_case(b))
    })
}

/// Returns whether transfer-encoding tokens end in `chunked`.
pub(crate) fn transfer_encoding_is_chunked_final(value: &str) -> bool {
    let mut saw_token = false;
    let mut last_token = "";
    for token in value.split(',') {
        let token = token.trim();
        if token.is_empty() {
            continue;
        }
        saw_token = true;
        last_token = token;
    }
    saw_token && last_token.eq_ignore_ascii_case("chunked")
}

/// Returns `true` when request method is `GET` or `HEAD`.
pub(crate) fn request_method_is_get_or_head(request_head: &[u8]) -> bool {
    let Some(first_line_end) = find_crlf(request_head) else {
        return false;
    };
    let request_line = &request_head[..first_line_end];
    let Some(method_end) = request_line.iter().position(|byte| *byte == b' ') else {
        return false;
    };
    let method = &request_line[..method_end];
    method.eq_ignore_ascii_case(b"GET") || method.eq_ignore_ascii_case(b"HEAD")
}

/// Returns whether request head includes a `content-length` header.
pub(crate) fn request_has_content_length_header(request_head: &[u8]) -> bool {
    contains_ascii_case_insensitive(request_head, b"content-length:")
}

/// Returns whether an HTTP/1 header value byte is unsupported by Hyper's h1
/// parser and should be rewritten before parsing.
pub(crate) fn is_invalid_http1_header_value_byte(byte: u8) -> bool {
    byte == 0x7f || (byte < 0x20 && byte != b'\t')
}

/// Returns whether request head contains unsupported HTTP/1 header value bytes.
pub(crate) fn request_head_contains_invalid_header_value_bytes(request_head: &[u8]) -> bool {
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
        let value = line.get(colon_index + 1..).unwrap_or_default();
        if value
            .iter()
            .any(|byte| is_invalid_http1_header_value_byte(*byte))
        {
            return true;
        }
    }
    false
}
