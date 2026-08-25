use crate::*;

/// Async I/O wrapper that replays a prefetched/sanitized prefix before
/// reading from the underlying transport stream.
pub(crate) struct PrefixedIo<S> {
    inner: S,
    prefix: Vec<u8>,
    prefix_offset: usize,
}

impl<S> PrefixedIo<S> {
    pub(crate) fn new(inner: S, prefix: Vec<u8>) -> Self {
        Self {
            inner,
            prefix,
            prefix_offset: 0,
        }
    }
}

impl<S> AsyncRead for PrefixedIo<S>
where
    S: AsyncRead + Unpin,
{
    fn poll_read(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &mut tokio::io::ReadBuf<'_>,
    ) -> Poll<io::Result<()>> {
        if self.prefix_offset < self.prefix.len() && buf.remaining() > 0 {
            let available = &self.prefix[self.prefix_offset..];
            let to_copy = available.len().min(buf.remaining());
            buf.put_slice(&available[..to_copy]);
            self.prefix_offset += to_copy;
            return Poll::Ready(Ok(()));
        }
        Pin::new(&mut self.inner).poll_read(cx, buf)
    }
}

impl<S> AsyncWrite for PrefixedIo<S>
where
    S: AsyncWrite + Unpin,
{
    fn poll_write(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        src: &[u8],
    ) -> Poll<Result<usize, io::Error>> {
        Pin::new(&mut self.inner).poll_write(cx, src)
    }

    fn poll_flush(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Result<(), io::Error>> {
        Pin::new(&mut self.inner).poll_flush(cx)
    }

    fn poll_shutdown(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
    ) -> Poll<Result<(), io::Error>> {
        Pin::new(&mut self.inner).poll_shutdown(cx)
    }
}

/// Returns true when an error message indicates expected cancellation during
/// shutdown (e.g. aborted keep-alive connection tasks).
pub(crate) fn is_cancellation_message(message: &str) -> bool {
    let lower = message.to_lowercase();
    lower.contains(MESSAGE_CANCELLED) || lower.contains(MESSAGE_CANCELED)
}

/// Returns true for expected websocket tunnel errors during shutdown.
pub(crate) fn is_expected_shutdown_tunnel_error(message: &str) -> bool {
    let lower = message.to_lowercase();
    is_cancellation_message(message)
        || lower.contains(MESSAGE_BRIDGE_STOPPING)
        || lower.contains(MESSAGE_CONNECTION_CLOSED)
        || lower.contains(MESSAGE_CHANNEL_CLOSED)
}

/// Writes an unmasked WebSocket close frame to an upgraded client stream.
pub(crate) async fn write_websocket_close_frame(
    writer: &mut (impl AsyncWrite + Unpin),
    code: u16,
) -> Result<(), String> {
    let payload = [0x88_u8, 0x02_u8, (code >> 8) as u8, (code & 0xff) as u8];
    writer
        .write_all(&payload)
        .await
        .map_err(|error| format!("write websocket close frame failed: {error}"))?;
    writer
        .shutdown()
        .await
        .map_err(|error| format!("shutdown upgraded frontend stream failed: {error}"))?;
    Ok(())
}
