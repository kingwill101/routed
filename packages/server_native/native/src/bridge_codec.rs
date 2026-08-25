use crate::*;

/// Minimal binary writer used by bridge payload codec.
pub(crate) struct BridgeByteWriter {
    bytes: Vec<u8>,
}

impl BridgeByteWriter {
    /// Creates a new empty bridge payload writer.
    pub(crate) fn new() -> Self {
        Self { bytes: Vec::new() }
    }

    /// Reserves additional payload capacity.
    pub(crate) fn reserve(&mut self, additional: usize) {
        self.bytes.reserve(additional);
    }

    /// Appends a placeholder `u32` and returns its position for patching.
    pub(crate) fn reserve_u32(&mut self) -> usize {
        let pos = self.bytes.len();
        self.bytes.extend_from_slice(&0_u32.to_be_bytes());
        pos
    }

    /// Overwrites a previously reserved `u32` at `pos`.
    pub(crate) fn patch_u32(&mut self, pos: usize, value: u32) {
        self.bytes[pos..pos + 4].copy_from_slice(&value.to_be_bytes());
    }

    /// Finalizes and returns encoded bytes.
    pub(crate) fn into_inner(self) -> Vec<u8> {
        self.bytes
    }

    /// Writes one byte.
    pub(crate) fn put_u8(&mut self, value: u8) {
        self.bytes.push(value);
    }

    /// Writes one big-endian `u16`.
    pub(crate) fn put_u16(&mut self, value: u16) {
        self.bytes.extend_from_slice(&value.to_be_bytes());
    }

    /// Writes one big-endian `u32`.
    pub(crate) fn put_u32(&mut self, value: u32) {
        self.bytes.extend_from_slice(&value.to_be_bytes());
    }

    /// Writes UTF-8 bytes as a length-prefixed field.
    pub(crate) fn put_string(&mut self, value: &str) -> Result<(), String> {
        self.put_bytes(value.as_bytes())
    }

    /// Writes arbitrary bytes as a length-prefixed field.
    pub(crate) fn put_bytes(&mut self, bytes: &[u8]) -> Result<(), String> {
        let len = u32::try_from(bytes.len())
            .map_err(|_| "bridge field length does not fit u32".to_string())?;
        self.put_u32(len);
        self.bytes.extend_from_slice(bytes);
        Ok(())
    }
}

/// Minimal binary reader used by bridge payload codec.
pub(crate) struct BridgeByteReader<'a> {
    bytes: &'a [u8],
    offset: usize,
}

impl<'a> BridgeByteReader<'a> {
    /// Creates a reader over a full bridge payload slice.
    pub(crate) fn new(bytes: &'a [u8]) -> Self {
        Self { bytes, offset: 0 }
    }

    /// Reads one `u8`.
    pub(crate) fn get_u8(&mut self) -> Result<u8, String> {
        let bytes = self.get_exact(1)?;
        Ok(bytes[0])
    }

    /// Reads one big-endian `u16`.
    pub(crate) fn get_u16(&mut self) -> Result<u16, String> {
        let bytes = self.get_exact(2)?;
        Ok(u16::from_be_bytes([bytes[0], bytes[1]]))
    }

    /// Reads one big-endian `u32`.
    pub(crate) fn get_u32(&mut self) -> Result<u32, String> {
        let bytes = self.get_exact(4)?;
        Ok(u32::from_be_bytes([bytes[0], bytes[1], bytes[2], bytes[3]]))
    }

    /// Reads one length-prefixed byte field.
    pub(crate) fn get_bytes(&mut self) -> Result<&'a [u8], String> {
        let (start, length) = self.get_bytes_range()?;
        Ok(&self.bytes[start..start + length])
    }

    /// Reads a length prefix and advances the cursor over its field.
    pub(crate) fn get_bytes_range(&mut self) -> Result<(usize, usize), String> {
        let length = self.get_u32()? as usize;
        if self.offset + length > self.bytes.len() {
            return Err("truncated bridge payload".to_string());
        }
        let start = self.offset;
        self.offset += length;
        Ok((start, length))
    }

    /// Ensures all payload bytes have been consumed.
    pub(crate) fn ensure_done(&self) -> Result<(), String> {
        if self.offset == self.bytes.len() {
            return Ok(());
        }
        Err(format!(
            "unexpected trailing bridge payload bytes: {}",
            self.bytes.len() - self.offset
        ))
    }

    /// Reads exactly `len` bytes from the current cursor.
    pub(crate) fn get_exact(&mut self, len: usize) -> Result<&'a [u8], String> {
        if self.offset + len > self.bytes.len() {
            return Err("truncated bridge payload".to_string());
        }
        let start = self.offset;
        self.offset += len;
        Ok(&self.bytes[start..start + len])
    }
}

/// Maps HTTP versions to bridge protocol strings consumed by Dart.
pub(crate) fn http_version_to_protocol(version: Version) -> &'static str {
    match version {
        Version::HTTP_09 => "0.9",
        Version::HTTP_10 => "1.0",
        Version::HTTP_11 => "1.1",
        Version::HTTP_2 => "2",
        Version::HTTP_3 => "3",
        _ => "1.1",
    }
}

/// Splits `path?query` into `(path, query)` without allocations.
pub(crate) fn split_path_and_query_ref(path_and_query: &str) -> (&str, &str) {
    match path_and_query.split_once('?') {
        Some((path, query)) => (path, query),
        None => (path_and_query, ""),
    }
}

/// Returns true when request headers indicate websocket upgrade.
pub(crate) fn is_websocket_upgrade(headers: &axum::http::HeaderMap) -> bool {
    let has_upgrade = headers.get_all("connection").iter().any(|value| {
        value
            .to_str()
            .ok()
            .map(|value| {
                value
                    .split(',')
                    .any(|token| token.trim().eq_ignore_ascii_case("upgrade"))
            })
            .unwrap_or(false)
    });
    let websocket_upgrade = headers.get_all("upgrade").iter().any(|value| {
        value
            .to_str()
            .ok()
            .map(|value| value.trim().eq_ignore_ascii_case("websocket"))
            .unwrap_or(false)
    });
    has_upgrade && websocket_upgrade
}

/// Creates plain-text error response used for bridge/proxy failures.
pub(crate) fn text_response(status: StatusCode, message: impl Into<String>) -> Response<Body> {
    let mut response = Response::new(Body::from(message.into()));
    *response.status_mut() = status;
    response
}
