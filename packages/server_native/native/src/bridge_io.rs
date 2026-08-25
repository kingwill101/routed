use crate::*;

/// Writes one length-prefixed bridge frame.
pub(crate) async fn write_bridge_frame<S: AsyncWrite + Unpin + ?Sized>(
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
pub(crate) async fn write_bridge_tunnel_close_frame<S: AsyncWrite + Unpin + ?Sized>(
    socket: &mut S,
) -> Result<(), String> {
    let payload = [BRIDGE_PROTOCOL_VERSION, BRIDGE_TUNNEL_CLOSE_FRAME_TYPE];
    write_bridge_frame(socket, &payload).await
}

/// Writes a sequence of byte slices using vectored IO when possible.
pub(crate) async fn write_all_vectored<S: AsyncWrite + Unpin + ?Sized>(
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
pub(crate) async fn read_bridge_frame<S: AsyncRead + Unpin + ?Sized>(
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
pub(crate) async fn read_bridge_frame_reuse<S: AsyncRead + Unpin + ?Sized>(
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
