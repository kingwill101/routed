use crate::*;

/// Reads direct-callback response frames and streams them to channel.
pub(crate) async fn stream_direct_bridge_response_frames(
    direct_bridge: Arc<DirectRequestBridge>,
    request_id: u64,
    mut response_rx: mpsc::UnboundedReceiver<Vec<u8>>,
    tx: mpsc::Sender<Result<Bytes, String>>,
) {
    loop {
        let payload = match time::timeout(DIRECT_REQUEST_TIMEOUT, response_rx.recv()).await {
            Ok(Some(payload)) => payload,
            Ok(None) => {
                let _ = tx
                    .send(Err(
                        "direct bridge callback closed before response end".to_string()
                    ))
                    .await;
                break;
            }
            Err(_) => {
                let _ = tx
                    .send(Err(format!(
                        "direct bridge callback timed out after {:?}",
                        DIRECT_REQUEST_TIMEOUT
                    )))
                    .await;
                break;
            }
        };

        let frame_type = match peek_bridge_frame_type(&payload) {
            Ok(frame_type) => frame_type,
            Err(error) => {
                let _ = tx
                    .send(Err(format!("decode response failed: {error}")))
                    .await;
                break;
            }
        };

        if frame_type == BRIDGE_RESPONSE_CHUNK_FRAME_TYPE {
            match decode_bridge_response_chunk(&payload) {
                Ok(chunk) => {
                    if !chunk.is_empty() && tx.send(Ok(chunk)).await.is_err() {
                        break;
                    }
                }
                Err(error) => {
                    let _ = tx
                        .send(Err(format!("decode response failed: {error}")))
                        .await;
                    break;
                }
            }
            continue;
        }

        if frame_type == BRIDGE_RESPONSE_END_FRAME_TYPE {
            if let Err(error) = decode_bridge_response_end(&payload) {
                let _ = tx
                    .send(Err(format!("decode response failed: {error}")))
                    .await;
            }
            break;
        }

        let _ = tx
            .send(Err(format!(
                "decode response failed: unexpected bridge frame type: {frame_type}"
            )))
            .await;
        break;
    }

    remove_pending_direct_request(&direct_bridge, request_id);
}

/// Tunnels upgraded websocket bytes between frontend connection and
/// direct-callback bridge frames.
pub(crate) async fn run_direct_websocket_tunnel(
    upgrade: OnUpgrade,
    direct_bridge: Arc<DirectRequestBridge>,
    request_id: u64,
    mut response_rx: mpsc::UnboundedReceiver<Vec<u8>>,
) -> Result<(), String> {
    let upgraded = upgrade
        .await
        .map_err(|error| format!("frontend upgrade failed: {error}"))?;
    let upgraded = TokioIo::new(upgraded);
    let (mut frontend_reader, mut frontend_writer) = tokio::io::split(upgraded);

    let callback_bridge = direct_bridge.clone();
    let frontend_to_callback = tokio::spawn(async move {
        let mut buffer = vec![0_u8; BRIDGE_BODY_CHUNK_BYTES];
        loop {
            let read = frontend_reader
                .read(&mut buffer)
                .await
                .map_err(|error| format!("read upgraded frontend stream failed: {error}"))?;
            if read == 0 {
                emit_direct_tunnel_close(&callback_bridge, request_id)?;
                return Ok::<(), String>(());
            }
            emit_direct_tunnel_chunk(&callback_bridge, request_id, &buffer[..read])?;
        }
    });

    let response_bridge = direct_bridge.clone();
    let callback_to_frontend = tokio::spawn(async move {
        loop {
            let payload = match time::timeout(DIRECT_REQUEST_TIMEOUT, response_rx.recv()).await {
                Ok(Some(payload)) => payload,
                Ok(None) => {
                    if response_bridge.stopped.load(Ordering::Acquire) {
                        let _ = write_websocket_close_frame(
                            &mut frontend_writer,
                            WEBSOCKET_CLOSE_GOING_AWAY,
                        )
                        .await;
                    }
                    return Ok::<(), String>(());
                }
                Err(_) => {
                    if response_bridge.stopped.load(Ordering::Acquire) {
                        let _ = write_websocket_close_frame(
                            &mut frontend_writer,
                            WEBSOCKET_CLOSE_GOING_AWAY,
                        )
                        .await;
                        return Ok::<(), String>(());
                    }
                    return Err(format!(
                        "direct bridge callback timed out after {:?}",
                        DIRECT_REQUEST_TIMEOUT
                    ));
                }
            };
            let frame_type = peek_bridge_frame_type(&payload)?;
            if frame_type == BRIDGE_RESPONSE_END_FRAME_TYPE {
                decode_bridge_response_end(&payload)
                    .map_err(|error| format!("decode response failed: {error}"))?;
                continue;
            }
            if frame_type == BRIDGE_TUNNEL_CHUNK_FRAME_TYPE {
                let chunk = decode_bridge_tunnel_chunk(&payload)
                    .map_err(|error| format!("decode response failed: {error}"))?;
                if !chunk.is_empty() {
                    frontend_writer.write_all(&chunk).await.map_err(|error| {
                        format!("write upgraded frontend stream failed: {error}")
                    })?;
                }
                continue;
            }
            if frame_type == BRIDGE_TUNNEL_CLOSE_FRAME_TYPE {
                decode_bridge_tunnel_close(&payload)
                    .map_err(|error| format!("decode response failed: {error}"))?;
                return Ok(());
            }
            return Err(format!(
                "decode response failed: unexpected bridge tunnel frame type: {frame_type}"
            ));
        }
    });

    let (frontend_result, callback_result) =
        tokio::join!(frontend_to_callback, callback_to_frontend);
    remove_pending_direct_request(&direct_bridge, request_id);

    match frontend_result {
        Ok(Ok(())) => {}
        Ok(Err(error)) => return Err(error),
        Err(error) => {
            return Err(format!(
                "frontend-to-direct-callback tunnel task failed: {error}"
            ));
        }
    }

    match callback_result {
        Ok(Ok(())) => {}
        Ok(Err(error)) => return Err(error),
        Err(error) => {
            return Err(format!(
                "direct-callback-to-frontend tunnel task failed: {error}"
            ));
        }
    }

    Ok(())
}

/// Emits one tunnel chunk payload to direct callback.
pub(crate) fn emit_direct_tunnel_chunk(
    direct_bridge: &Arc<DirectRequestBridge>,
    request_id: u64,
    chunk: &[u8],
) -> Result<(), String> {
    for frame_chunk in chunk.chunks(BRIDGE_BODY_CHUNK_BYTES) {
        let payload = encode_bridge_tunnel_chunk_payload(frame_chunk)?;
        emit_direct_callback_payload(direct_bridge, request_id, payload)?;
    }
    Ok(())
}

/// Emits tunnel-close payload to direct callback.
pub(crate) fn emit_direct_tunnel_close(
    direct_bridge: &Arc<DirectRequestBridge>,
    request_id: u64,
) -> Result<(), String> {
    let payload = encode_bridge_tunnel_close_payload();
    emit_direct_callback_payload(direct_bridge, request_id, payload)
}
