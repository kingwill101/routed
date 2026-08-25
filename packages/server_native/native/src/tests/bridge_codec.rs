#[test]
fn encode_bridge_request_splits_connection_header_tokens() {
    let mut headers = HeaderMap::new();
    headers.append(
        CONNECTION,
        HeaderValue::from_static("my-connection-header1, my-connection-header2, close"),
    );
    let request = BridgeRequestRef {
        method: "GET",
        scheme: "http",
        authority: "127.0.0.1:8080",
        path: "/",
        query: "",
        protocol: "1.1",
        headers: &headers,
    };
    let payload = encode_bridge_request_start(&request).expect("encode request start frame");

    let mut reader = BridgeByteReader::new(&payload);
    assert_eq!(
        reader.get_u8().expect("protocol version"),
        BRIDGE_PROTOCOL_VERSION
    );
    assert_eq!(
        reader.get_u8().expect("frame type"),
        BRIDGE_REQUEST_START_FRAME_TYPE_TOKENIZED
    );
    assert_eq!(
        reader
            .get_bytes()
            .and_then(|bytes| std::str::from_utf8(bytes).map_err(|e| e.to_string()))
            .expect("method"),
        "GET"
    );
    assert_eq!(
        reader
            .get_bytes()
            .and_then(|bytes| std::str::from_utf8(bytes).map_err(|e| e.to_string()))
            .expect("scheme"),
        "http"
    );
    assert_eq!(
        reader
            .get_bytes()
            .and_then(|bytes| std::str::from_utf8(bytes).map_err(|e| e.to_string()))
            .expect("authority"),
        "127.0.0.1:8080"
    );
    assert_eq!(
        reader
            .get_bytes()
            .and_then(|bytes| std::str::from_utf8(bytes).map_err(|e| e.to_string()))
            .expect("path"),
        "/"
    );
    assert_eq!(
        reader
            .get_bytes()
            .and_then(|bytes| std::str::from_utf8(bytes).map_err(|e| e.to_string()))
            .expect("query"),
        ""
    );
    assert_eq!(
        reader
            .get_bytes()
            .and_then(|bytes| std::str::from_utf8(bytes).map_err(|e| e.to_string()))
            .expect("protocol"),
        "1.1"
    );

    assert_eq!(reader.get_u32().expect("header count"), 3);
    for expected in ["my-connection-header1", "my-connection-header2", "close"] {
        assert_eq!(reader.get_u16().expect("header token"), 1);
        assert_eq!(
            reader
                .get_bytes()
                .and_then(|bytes| std::str::from_utf8(bytes).map_err(|e| e.to_string()))
                .expect("header value"),
            expected
        );
    }
    reader.ensure_done().expect("no trailing payload bytes");
}

#[test]
fn encode_bridge_request_prefers_sanitized_connection_header() {
    let mut headers = HeaderMap::new();
    headers.append(CONNECTION, HeaderValue::from_static("close"));
    headers.append(
        HeaderName::from_static(SANITIZED_CONNECTION_HEADER),
        HeaderValue::from_static("my-connection-header1, my-connection-header2, close"),
    );
    let request = BridgeRequestRef {
        method: "GET",
        scheme: "http",
        authority: "127.0.0.1:8080",
        path: "/",
        query: "",
        protocol: "1.1",
        headers: &headers,
    };
    let payload = encode_bridge_request_start(&request).expect("encode request start frame");
    let mut reader = BridgeByteReader::new(&payload);
    let _ = reader.get_u8().expect("protocol version");
    let _ = reader.get_u8().expect("frame type");
    for _ in 0..6 {
        let _ = reader.get_bytes().expect("request field");
    }
    assert_eq!(reader.get_u32().expect("header count"), 3);
    for expected in ["my-connection-header1", "my-connection-header2", "close"] {
        assert_eq!(reader.get_u16().expect("header token"), 1);
        assert_eq!(
            reader
                .get_bytes()
                .and_then(|bytes| std::str::from_utf8(bytes).map_err(|e| e.to_string()))
                .expect("header value"),
            expected
        );
    }
}

#[test]
fn encode_bridge_request_preserves_empty_connection_header_value() {
    let mut headers = HeaderMap::new();
    headers.append(CONNECTION, HeaderValue::from_static(""));
    let request = BridgeRequestRef {
        method: "GET",
        scheme: "http",
        authority: "127.0.0.1:8080",
        path: "/",
        query: "",
        protocol: "1.1",
        headers: &headers,
    };
    let payload = encode_bridge_request_start(&request).expect("encode request start frame");

    let mut reader = BridgeByteReader::new(&payload);
    let _ = reader.get_u8().expect("protocol version");
    let _ = reader.get_u8().expect("frame type");
    for _ in 0..6 {
        let _ = reader.get_bytes().expect("request field");
    }
    assert_eq!(reader.get_u32().expect("header count"), 1);
    assert_eq!(reader.get_u16().expect("header token"), 1);
    assert_eq!(
        reader
            .get_bytes()
            .and_then(|bytes| std::str::from_utf8(bytes).map_err(|e| e.to_string()))
            .expect("header value"),
        ""
    );
    reader.ensure_done().expect("no trailing payload bytes");
}

#[test]
fn encode_bridge_request_preserves_empty_sanitized_connection_header_value() {
    let mut headers = HeaderMap::new();
    headers.append(CONNECTION, HeaderValue::from_static("close"));
    headers.append(
        HeaderName::from_static(SANITIZED_CONNECTION_HEADER),
        HeaderValue::from_static(""),
    );
    let request = BridgeRequestRef {
        method: "GET",
        scheme: "http",
        authority: "127.0.0.1:8080",
        path: "/",
        query: "",
        protocol: "1.1",
        headers: &headers,
    };
    let payload = encode_bridge_request_start(&request).expect("encode request start frame");
    let mut reader = BridgeByteReader::new(&payload);
    let _ = reader.get_u8().expect("protocol version");
    let _ = reader.get_u8().expect("frame type");
    for _ in 0..6 {
        let _ = reader.get_bytes().expect("request field");
    }
    assert_eq!(reader.get_u32().expect("header count"), 1);
    assert_eq!(reader.get_u16().expect("header token"), 1);
    assert_eq!(
        reader
            .get_bytes()
            .and_then(|bytes| std::str::from_utf8(bytes).map_err(|e| e.to_string()))
            .expect("header value"),
        ""
    );
    reader.ensure_done().expect("no trailing payload bytes");
}

#[test]
fn bridge_response_preserves_http1_connection_tokens() {
    let transfer_encoding = HeaderName::from_static("transfer-encoding");
    let connection = HeaderName::from_static("connection");
    let custom = HeaderName::from_static("x-custom");

    assert!(!should_forward_bridge_response_header(
        &transfer_encoding,
        StatusCode::OK,
        "1.1"
    ));
    assert!(should_forward_bridge_response_header(
        &connection,
        StatusCode::OK,
        "1.1"
    ));
    assert!(should_forward_bridge_response_header(
        &custom,
        StatusCode::OK,
        "1.1"
    ));
    assert!(should_forward_bridge_response_header(
        &transfer_encoding,
        StatusCode::SWITCHING_PROTOCOLS,
        "1.1"
    ));
}

#[test]
fn bridge_response_filters_connection_headers_for_http2() {
    let connection = HeaderName::from_static("connection");
    assert!(!should_forward_bridge_response_header(
        &connection,
        StatusCode::OK,
        "2.0"
    ));
}
use super::*;
use axum::http::{
    header::{HeaderName, HeaderValue, CONNECTION},
    StatusCode,
};
