# routed_ffi Bridge Protocol

Last updated: February 18, 2026

This document defines the binary request/response bridge protocol between:

- Rust front transport (`packages/routed_ffi/native/src/lib.rs`)
- Dart bridge runtime (`packages/routed_ffi/lib/src/server_boot.dart`)

## Framing

The socket stream is message-framed:

1. `u32` big-endian payload length
2. payload bytes

Limits:

- max frame payload: `64 * 1024 * 1024` bytes (64 MiB)

## Payload Header

Every payload begins with:

1. `u8` protocol version
2. `u8` frame type

Current frame types:

- protocol version: `1`
- `1`: legacy single-frame request
- `2`: legacy single-frame response
- `3`: request start
- `4`: request chunk
- `5`: request end
- `6`: response start
- `7`: response chunk
- `8`: response end
- `9`: upgraded tunnel chunk
- `10`: upgraded tunnel close
- `11`: tokenized single-frame request
- `12`: tokenized single-frame response
- `13`: tokenized request start
- `14`: tokenized response start

## Field Encoding

- `string`: `u32` big-endian byte length + UTF-8 bytes
- `bytes`: `u32` big-endian length + raw bytes
- `u16`: big-endian
- `u32`: big-endian

For tokenized request/response frame types (`11`, `12`, `13`, `14`), header
name fields are encoded as:

1. `header_name_token: u16`
2. if token is `65535` (`0xFFFF`), `header_name_literal: string`

Token table:

`host`, `connection`, `user-agent`, `accept`, `accept-encoding`,
`accept-language`, `content-type`, `content-length`, `transfer-encoding`,
`cookie`, `set-cookie`, `cache-control`, `pragma`, `upgrade`,
`authorization`, `origin`, `referer`, `location`, `server`, `date`,
`x-forwarded-for`, `x-forwarded-proto`, `x-forwarded-host`,
`x-forwarded-port`, `x-request-id`, `sec-websocket-key`,
`sec-websocket-version`, `sec-websocket-protocol`,
`sec-websocket-extensions`

## Preferred Exchange (Chunked Framing)

Current default exchange sequence:

1. request start (`3`)
2. zero or more request chunk (`4`)
3. request end (`5`)
4. response start (`6`)
5. zero or more response chunk (`7`)
6. response end (`8`)

This framing keeps request/response metadata separate from body chunks and
supports large payload transfer without JSON/base64 overhead.

## Request Start Payload (frame type `3` or `13`)

Order:

1. `method: string`
2. `scheme: string`
3. `authority: string`
4. `path: string`
5. `query: string`
6. `protocol: string`
7. `headers_count: u32`
8. repeated `headers_count` times:
   - type `3`: `header_name: string`
   - type `13`: `header_name_token: u16` (+ optional literal string if token is `65535`)
   - `header_value: string`
Default normalization on Dart decode:

- empty method -> `GET`
- empty scheme -> `http`
- empty authority -> `127.0.0.1`
- empty path -> `/`
- empty protocol -> `1.1`

## Request Chunk Payload (frame type `4`)

Order:

1. `body_chunk: bytes`

## Request End Payload (frame type `5`)

No additional fields beyond payload header.

## Response Start Payload (frame type `6` or `14`)

Order:

1. `status: u16`
2. `headers_count: u32`
3. repeated `headers_count` times:
   - type `6`: `header_name: string`
   - type `14`: `header_name_token: u16` (+ optional literal string if token is `65535`)
   - `header_value: string`
## Response Chunk Payload (frame type `7`)

Order:

1. `body_chunk: bytes`

## Response End Payload (frame type `8`)

No additional fields beyond payload header.

## Upgraded Tunnel Frames

When Dart detaches the response socket (for example via
`WebSocketTransformer.upgrade`), the bridge switches to tunnel mode on the same
bridge connection after the HTTP response handshake is sent.

### Tunnel Chunk Payload (frame type `9`)

Order:

1. `chunk: bytes`

These frames carry raw upgraded-protocol bytes bidirectionally between Rust and
Dart.

### Tunnel Close Payload (frame type `10`)

No additional fields beyond payload header.

## Legacy Single-Frame Compatibility

For compatibility with older bridge peers, these frames are still accepted:

- request (`1`): request metadata + full body in one payload
- response (`2`): status + headers + full body in one payload
- tokenized request (`11`): request metadata + full body in one payload
- tokenized response (`12`): status + headers + full body in one payload

## Error Semantics

- malformed request payload at Dart bridge -> `400` response frame with text body
- bridge transport failure at Rust proxy -> `502` client response
- invalid response payload from bridge at Rust proxy -> `502` client response

## Versioning Rules

- additive, backward-compatible changes should use a new frame type under the same protocol version when possible
- incompatible wire changes must increment protocol version
- unknown version or frame type must be treated as decode failure
