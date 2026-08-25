#[test]
fn transfer_encoding_requires_chunked_as_final_token() {
    assert!(transfer_encoding_is_chunked_final("chunked"));
    assert!(transfer_encoding_is_chunked_final("gzip, chunked"));
    assert!(transfer_encoding_is_chunked_final(
        "gzip , deflate , chunked"
    ));
    assert!(!transfer_encoding_is_chunked_final(""));
    assert!(!transfer_encoding_is_chunked_final("gzip"));
    assert!(!transfer_encoding_is_chunked_final("chunked, gzip"));
}

#[test]
fn shared_proxy_runtime_uses_single_worker_thread() {
    assert_eq!(proxy_runtime_worker_threads(true), 1);
}

#[test]
fn non_shared_proxy_runtime_clamps_worker_threads() {
    let worker_threads = proxy_runtime_worker_threads(false);
    assert!((2..=16).contains(&worker_threads));
}

#[test]
fn request_detects_invalid_transfer_encoding_values() {
    let valid = b"GET / HTTP/1.1\r\nHost: example.test\r\nTransfer-Encoding: gzip, chunked\r\n\r\n";
    assert!(!request_has_invalid_transfer_encoding(valid));

    let invalid_order =
        b"GET / HTTP/1.1\r\nHost: example.test\r\nTransfer-Encoding: chunked, gzip\r\n\r\n";
    assert!(request_has_invalid_transfer_encoding(invalid_order));

    let invalid_utf8 =
        b"GET / HTTP/1.1\r\nHost: example.test\r\nTransfer-Encoding: \xFFchunked\r\n\r\n";
    assert!(request_has_invalid_transfer_encoding(invalid_utf8));
}

#[test]
fn request_rewrite_transfer_encoding_for_lenient_get_head_without_body() {
    let valid_get =
        b"GET / HTTP/1.1\r\nHost: example.test\r\nTransfer-Encoding: gzip, chunked\r\n\r\n";
    assert!(request_should_rewrite_transfer_encoding(valid_get, false));
    assert!(!request_should_rewrite_transfer_encoding(valid_get, true));

    let valid_head =
        b"HEAD / HTTP/1.1\r\nHost: example.test\r\nTransfer-Encoding: gzip, chunked\r\n\r\n";
    assert!(request_should_rewrite_transfer_encoding(valid_head, false));
    assert!(!request_should_rewrite_transfer_encoding(valid_head, true));

    let valid_post =
        b"POST / HTTP/1.1\r\nHost: example.test\r\nTransfer-Encoding: gzip, chunked\r\n\r\n";
    assert!(!request_should_rewrite_transfer_encoding(valid_post, false));

    let invalid_post =
        b"POST / HTTP/1.1\r\nHost: example.test\r\nTransfer-Encoding: chunked, gzip\r\n\r\n";
    assert!(request_should_rewrite_transfer_encoding(
        invalid_post,
        false
    ));
}

#[test]
fn request_head_detects_invalid_header_value_bytes() {
    let valid = b"GET / HTTP/1.1\r\nHost: example.test\r\nCookie: sessionId=abc123\r\n\r\n";
    assert!(!request_head_contains_invalid_header_value_bytes(valid));

    let invalid = b"GET / HTTP/1.1\r\nHost: example.test\r\nCookie: sessionId=abc\x7F123\r\n\r\n";
    assert!(request_head_contains_invalid_header_value_bytes(invalid));
}

#[test]
fn rewrite_transfer_encoding_headers_rewrites_all_variants() {
    let request_head = b"GET /upload HTTP/1.1\r\n\
Host: example.test\r\n\
Transfer-Encoding: gzip\r\n\
X-One: 1\r\n\
transfer-encoding: chunked\r\n\
\r\n";

    let sanitized = rewrite_transfer_encoding_headers(request_head);
    let sanitized_text = String::from_utf8(sanitized).expect("sanitized request should be utf8");
    for line in sanitized_text.lines() {
        assert!(!line.to_ascii_lowercase().starts_with("transfer-encoding:"));
    }
    assert!(sanitized_text
        .to_ascii_lowercase()
        .contains("x-server-native-transfer-encoding: gzip"));
    assert!(sanitized_text
        .to_ascii_lowercase()
        .contains("x-server-native-transfer-encoding: chunked"));
    assert!(sanitized_text.contains("Host: example.test\r\n"));
    assert!(sanitized_text.contains("X-One: 1\r\n"));
    assert!(sanitized_text.ends_with("\r\n\r\n"));
}

#[test]
fn rewrite_request_head_for_hyper_escapes_invalid_header_value_bytes() {
    let request_head = b"GET / HTTP/1.1\r\n\
Host: example.test\r\n\
Cookie: sessionId=abc123; userId=42\x7F\r\n\
\r\n";

    let sanitized = rewrite_request_head_for_hyper(request_head, false, false)
        .expect("invalid cookie value should trigger rewrite");
    let sanitized_text = String::from_utf8(sanitized).expect("sanitized request should be utf8");
    assert!(sanitized_text.contains("Cookie: sessionId=abc123; userId=42\"\r\n"));
    assert!(sanitized_text.ends_with("\r\n\r\n"));
}

#[test]
fn rewrite_request_head_for_hyper_rewrites_connection_for_non_upgrade() {
    let request_head = b"GET / HTTP/1.1\r\n\
Host: example.test\r\n\
Connection: my-connection-header1, my-connection-header2, close\r\n\
My-Connection-Header1: some-value1\r\n\
My-Connection-Header2: some-value2\r\n\
\r\n";

    let sanitized = rewrite_request_head_for_hyper(request_head, false, true)
        .expect("connection rewrite should trigger");
    let sanitized_text = String::from_utf8(sanitized).expect("sanitized request should be utf8");
    assert!(sanitized_text.to_ascii_lowercase().contains(
        "x-server-native-connection: my-connection-header1, my-connection-header2, close"
    ));
    assert!(!sanitized_text
        .to_ascii_lowercase()
        .contains("connection:close"));
    assert!(sanitized_text.contains("My-Connection-Header1: some-value1\r\n"));
    assert!(sanitized_text.contains("My-Connection-Header2: some-value2\r\n"));
}

#[test]
fn rewrite_request_head_for_hyper_preserves_empty_connection_value() {
    let request_head = b"GET / HTTP/1.1\r\n\
Host: example.test\r\n\
Connection: \r\n\
\r\n";

    let sanitized = rewrite_request_head_for_hyper(request_head, false, true)
        .expect("connection rewrite should trigger");
    let sanitized_text = String::from_utf8(sanitized).expect("sanitized request should be utf8");
    assert!(sanitized_text.contains(&format!(
        "{SANITIZED_CONNECTION_HEADER}:{EMPTY_CONNECTION_SENTINEL}\r\n"
    )));
}

#[test]
fn request_should_not_rewrite_connection_for_upgrade() {
    let request_head = b"GET /ws HTTP/1.1\r\n\
Host: example.test\r\n\
Connection: Upgrade\r\n\
Upgrade: websocket\r\n\
\r\n";
    assert!(!request_should_rewrite_connection_header(request_head));
}

#[test]
fn request_should_rewrite_connection_for_non_upgrade() {
    let request_head = b"GET / HTTP/1.1\r\n\
Host: example.test\r\n\
Connection: my-connection-header1, my-connection-header2, close\r\n\
My-Connection-Header1: some-value1\r\n\
My-Connection-Header2: some-value2\r\n\
\r\n";
    assert!(request_should_rewrite_connection_header(request_head));
}
use super::*;
