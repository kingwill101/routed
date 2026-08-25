use crate::*;

/// Decodes bridge response sequence into HTTP response body/headers.
///
/// Supports:
/// - single-frame responses,
/// - streaming start/chunk/end responses,
/// - optional websocket tunnel detach semantics.
pub(crate) async fn decode_bridge_response_stream(
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
pub(crate) async fn stream_bridge_response_chunks(
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
                let _ = tx.send(Err(io::Error::other(error))).await;
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
pub(crate) async fn run_websocket_tunnel(
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
