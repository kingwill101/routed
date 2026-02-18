Below are concrete, code-informed ways to close the gap between:

* **`routed_ffi_native_direct`**: Rust proxy returns a static response (no bridge).
* **`routed_ffi_direct`**: Rust proxy **serializes request → kernel socket hop → Dart decodes + constructs request wrappers → handler → Dart encodes response → kernel hop → Rust decodes → builds hyper response**.

In your current benchmark handler, Dart ignores the request and returns constant bytes — so most of the measured gap is **bridge overhead** (string/header work + per-request async scheduling + socket round-trip), not “business logic”.

---

## 1) Top 10 optimizations (ranked by impact vs risk)

Ranked primarily by **impact-to-risk ratio** (high impact, low risk first). “Impact” is relative to the *gap* between `routed_ffi_direct` and `routed_ffi_native_direct`.

| Rank | Optimization                                                                                                                                        | Expected impact                  | Risk         | Where it applies / why it matters                                                                                                                                                                                                                                                                   |
| ---: | --------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------- | ------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
|    1 | **Rust: eliminate per-request `String` allocations on the request encode path** (encode directly from `Request<Body>` parts into the bridge buffer) | **Very High**                    | **Low**      | In `proxy_request`, you currently allocate `String`s for method/scheme/authority/path/query/protocol and for every header name/value (`to_string()`), then re-copy them into `Vec<u8>` in `encode_bridge_request`. You can encode from borrowed `&str`/`&[u8]` immediately and skip most heap work. |
|    2 | **Dart: remove “async-with-no-await” + avoid awaiting bridge writes** (make writer methods synchronous)                                             | **High**                         | **Low**      | `_BridgeSocketWriter.writeFrame/writeResponseFrame/writeChunkFrame` are `async` but contain no `await`. Every `await writer.write…()` forces a microtask hop per request/part. Make them `void` and call directly, especially in `_handleBridgeSocket`’s hot loop.                                  |
|    3 | **Dart: make `FfiDirectRequest` lazy (no eager `Uri` build, no eager header materialization)**                                                      | **High** (esp. your benchmark)   | **Low–Med**  | `_toDirectRequest` calls `frame.headers` (materializes `List<MapEntry<…>>`) and `FfiDirectRequest` eagerly builds `Uri`. In your benchmark the handler ignores the request, so all of that is pure overhead. Provide a request view over `BridgeRequestFrame` (lazy URI + lazy header access).      |
|    4 | **Rust: avoid allocating `Vec<u8>` per frame read; reuse a buffer per bridge socket**                                                               | **Med–High**                     | **Low–Med**  | `read_bridge_frame` allocates `vec![0; payload_len]` every time. Reuse a `BytesMut`/`Vec<u8>` stored alongside the socket (or in the pool) and `resize`/`clear` + `read_exact`. Reduces allocator pressure & cache churn.                                                                           |
|    5 | **Rust: optimize response header decode to avoid `String` allocations** (parse directly into `HeaderName/HeaderValue` from payload slices)          | **Med–High**                     | **Med**      | `decode_bridge_response` does `get_string()?.to_string()` for every header field, then converts again into `HeaderName/HeaderValue`. For common cases, you can slice bytes from the payload and create header values from bytes, reducing copies/UTF-8 work.                                        |
|    6 | **Rust: replace `write_all_vectored`’s per-call `Vec<IoSlice>` allocation with a fixed small array / smallvec**                                     | **Medium**                       | **Low**      | `write_all_vectored` builds a new `Vec<IoSlice>` inside a loop. For your usage it’s almost always 2 or 3 slices. A fixed `[IoSlice; 3]` (with a length) removes heap traffic in the hottest write path.                                                                                             |
|    7 | **Rust: faster empty-body detection using size hints / end-of-stream checks**                                                                       | **Medium** (GET-heavy workloads) | **Low**      | `write_bridge_request` polls the body stream to find the first non-empty chunk even when bodies are empty. If `Body::size_hint().exact() == Some(0)` or equivalent, skip polling and send the legacy empty-body frame immediately.                                                                  |
|    8 | **Protocol v2: tokenise method/scheme/protocol + header names** (static table)                                                                      | **Med–High**                     | **Med**      | Header names repeat across requests (host, accept, user-agent…). Encoding/decoding them as strings is wasted work. A small shared dictionary (or HPACK/QPACK static table indices) lets both sides map integers → static strings (no allocations).                                                  |
|    9 | **Dart: multi-isolate bridge workers** (N isolates, N bridge endpoints; Rust load-balances)                                                         | **High** on multi-core           | **Med–High** | Dart decode/encode is CPU work and a single isolate is single-core. Multiple isolates can parallelize bridge overhead. Requires careful engine/handler strategy (per-isolate handler or routing partitioning).                                                                                      |
|   10 | **Replace kernel socket bridge with in-process transport** (Dart Native Ports + `ExternalTypedData`, or shared-memory ring buffers + eventfd)       | **Very High**                    | **High**     | Biggest step-change: remove kernel crossings and enable zero-copy buffers. More complex lifecycle and backpressure, but it’s the only way to get “close” to Rust-only mode for trivial handlers.                                                                                                    |

---

## 2) What to profile first (Rust + Dart)

The fastest way to close the gap is to confirm **where the time goes per request**. Given your code, likely hotspots are: (a) Rust header/string building, (b) Dart decode + wrapper allocation, (c) async scheduling hops, (d) kernel I/O + copies.

### Rust side: profile these first

**A. Wall-time breakdown inside `proxy_request`**
Add `tracing` spans or lightweight timestamping around:

1. **Request extraction**

* `path_and_query` handling
* authority extraction from `Host`
* header iteration (`for (name, value) in parts.headers.iter()`)

2. **Bridge request encode**

* time in `encode_bridge_request` / `encode_bridge_request_start`

3. **Bridge write**

* time in `write_bridge_frame` + `write_all_vectored`
* count syscalls if you can (or infer from `write_vectored` loops)

4. **Waiting for Dart**

* time from “wrote request” → “first response frame read”

5. **Bridge read + decode**

* time in `read_bridge_frame`
* time in `decode_bridge_response(_start/_chunk/_end)`

6. **Response build**

* converting bridge headers → `HeaderName/HeaderValue`
* constructing `Response<Body>`

**B. Allocation profiling**
You want to know if you’re allocator-bound. Tools/approaches:

* Linux: `perf` + `heaptrack`/`jemalloc` stats (if applicable)
* Flamegraph: look for `to_string`, `alloc`, `memcpy`, UTF-8 validation, `Vec::extend_from_slice`
* Count allocations indirectly by tracking:

  * number of headers
  * bytes per frame
  * number of new `Vec`/`String` creations in the hot path (you can instrument counters)

**C. syscall/context-switch pressure**
If you can run on Linux:

* `perf stat` focusing on context switches, syscalls, cycles/instructions
* High context switches strongly indicate the socket hop dominates.

### Dart side: profile these first

**A. CPU profile hotspots (Dart DevTools)**
Focus on time spent in:

* `_SocketFrameReader.readFrame` / `_readExactOrNull`
* `BridgeRequestFrame.decodePayload` and `_BridgeFrameReader.readString`
* `_toDirectRequest` and anything that materializes headers / creates `Uri`
* `BridgeResponseFrame.encodePayloadPrefixWithoutBody` and `_BridgeFrameWriter.writeString`

**B. GC / allocation pressure**
Turn on allocation profiling / watch GC frequency. Likely contributors:

* per-request `List<String>.filled(...)` for headers
* per-request `String` creation for header names/values
* `List<MapEntry<...>>.generate(...)` in `_materializeHeaders`
* `Uri(...)` construction in `FfiDirectRequest`

**C. Microtask churn due to `await`**
This is subtle but important in your current code:

* Any `await` of a “completed future” still schedules continuations.
* Your `_BridgeSocketWriter` methods are `async` with no `await`, and are awaited in hot loops.
  This can show up as lots of time in scheduler / microtask dispatch.

**D. “Bridge-only” microbenchmark**
Before changing protocol, measure the bridge overhead alone:

* handler returns a cached response
* strip request wrapping work (or make it lazy)
* compare requests/sec vs current to isolate overhead sources

---

## 3) Protocol / transport changes to consider

You asked specifically about packed frames, header tokenization, binary formats, ring buffers, shared memory, batching, multiplexing. Here’s a practical menu, from least invasive to most.

### 3.1 Packed frames (reduce per-request writes & parsing overhead)

**Today**

* Frame = `[u32 len][payload]`
* Response writes are effectively 3 “adds” in Dart: header, prefix, body.

**Change**

* Pack `[u32 len + payload-prefix]` into a single small buffer on Dart side (header+prefix contiguous), then add body.
* On Rust side, for small payloads, consider copying `[len][payload]` into one contiguous buffer and `write_all` once (often faster than vectored + loop), while keeping vectored for large bodies.

**Why it helps**
Fewer write calls + fewer partial-write loops + better cache locality.

### 3.2 Header tokenization (big win for repeated header names)

**Goal**
Stop encoding/decoding `"host"`, `"accept"`, `"user-agent"`, `"content-type"` as fresh strings every request.

**Protocol v2 idea**

* For each header entry:

  * `name_tag: u16` where:

    * `0..N-1` = static dictionary index
    * `0xFFFF` = literal string follows
  * `value` stays literal bytes (or can also be tokenized for common values)

**Implementation detail**
Keep v1 and v2 side-by-side:

* byte 0 is version (`1` today)
* introduce version `2` with tokenized headers
* allow fallback to v1 for compatibility/tests

**Dictionary source**

* simplest: your own small table of ~32–128 common header names
* more advanced: reuse HPACK/QPACK static table indices (but heavier to implement)

### 3.3 Binary formats: do you need protobuf/flatbuffers?

You already have a custom binary format that is “close to metal”.
Switching to protobuf/flatbuffers rarely beats:

* fixed layout
* varints only where helpful
* avoiding allocations and string conversions

If you do change format, do it because you want:

* schema evolution
* codegen
* better correctness tooling
  —not because you expect raw speed.

### 3.4 Multiplexing (multiple in-flight requests per bridge connection)

**Today**

* One request at a time per bridge socket.
* Concurrency requires many sockets and pool churn.

**Change**
Add a **stream/request ID** to every frame:

* request start: includes `stream_id`
* response start/chunk/end: includes `stream_id`

Then:

* Rust can send multiple requests without waiting
* Dart can process concurrently (still single isolate unless you add isolates)
* Responses can be interleaved on one connection

**Why it helps**

* fewer sockets → less accept/connect overhead
* less mutex churn in the pool
* enables batching on the wire

**Complexity**
Higher: you need routing of response frames back to waiting callers + backpressure.

### 3.5 Batching

Once you have multiplexing, batching becomes natural:

* Rust writes a batch of request frames in one syscall when under load
* Dart reads a chunk and processes multiple frames per read

This helps throughput more than latency.

### 3.6 Ring buffers + shared memory (zero-copy, no kernel network stack)

Since Rust and Dart are in the **same process**, sockets are an expensive IPC choice.

Two realistic in-process designs:

#### Option A: Dart Native Ports + `ExternalTypedData` (often the sweet spot)

* Rust posts messages to a Dart port (via `Dart_PostCObject`)
* The payload is an `ExternalTypedData` view over Rust-allocated memory
* Dart replies similarly (or uses a completion port with request IDs)

**Pros**

* avoids kernel crossings
* can be near-zero-copy
* less “systems” complexity than full shared memory rings

**Cons**

* async-by-nature; you’ll build an RPC layer with request IDs + oneshots

#### Option B: Shared-memory ring buffers + eventfd/condvar

* Two rings: requests and responses
* Fixed-size slots or variable-size blocks with a free list
* Atomics for head/tail
* eventfd (Linux) or a pipe for wakeups; otherwise call into Rust to block/wake

**Pros**

* highest potential throughput
* predictable allocations

**Cons**

* highest complexity and portability effort

---

## 4) Migration plan (low-risk first)

This is structured so you can land improvements incrementally, keep compatibility, and measure each step.

### Phase 0 — Instrumentation baseline (do this first)

* Add timing spans in Rust (`proxy_request` → encode → write → wait → read → decode → build response).
* Add Dart timeline events around frame read/decode and response encode/write.
* Record:

  * req/s
  * p50/p95 latency
  * CPU usage per core
  * GC frequency (Dart)
  * context switches (if available)

### Phase 1 — “No-regrets” low-risk code changes

1. **Rust request path: remove `to_string()` allocations**

   * Encode directly from borrowed values into the bridge writer.
   * Avoid building `BridgeRequest { String… }` if it’s just an intermediate container.
   * Pre-`reserve()` encoder buffer (estimate from header count + avg lengths).

2. **Dart bridge write path: make it synchronous**

   * Change `_BridgeSocketWriter.write*` to non-`async`.
   * Stop `await`ing writes in hot loops (write + continue).
   * This alone can materially reduce microtask churn.

3. **Dart direct request: laziness**

   * Replace `FfiDirectRequest(headers: frame.headers, uri: …)` with a view:

     * store `BridgeRequestFrame` + body stream
     * compute `Uri` only when accessed
     * provide `header(name)` that iterates `frame.headerNameAt(i)/headerValueAt(i)` without allocating `MapEntry` list

4. **Rust frame I/O buffer reuse**

   * Reuse the payload buffer for `read_bridge_frame`.
   * Consider storing a reusable buffer with each pooled socket.

### Phase 2 — Medium risk, meaningful wins

5. **Rust response decode: reduce allocations**

   * Avoid `String` creation where you can.
   * If feasible, build `HeaderValue` from bytes directly (and/or from shared `Bytes` slices).

6. **Optimize vectored write helper**

   * Replace dynamic `Vec<IoSlice>` creation with a small fixed array for the common 2–3 slice case.

7. **Empty body fast-path with size hints**

   * Use `size_hint` / end-of-stream checks to skip polling the body stream when it’s provably empty.

### Phase 3 — Protocol v2 with backward compatibility

8. **Introduce protocol version 2**

   * Tokenize method/scheme/protocol into enums.
   * Tokenize common header names into `u16` indices.
   * Keep v1 decoder for fallback until you’re confident.

9. **Optional: lazy header *values* (bytes-first)**

   * Keep header values as bytes across the bridge and decode to `String` only on demand in Dart.

### Phase 4 — Parallelism & fewer sockets

10. **Multi-isolate bridge workers**

* Run N Dart isolates, each with its own bridge endpoint.
* Rust load-balances requests across endpoints (round-robin / consistent hash).
* This is the most practical way to turn Dart-side bridge overhead into multi-core throughput.

### Phase 5 — Step-change architecture (only if you still need more)

11. **Replace socket bridge**

* Start with Native Ports + `ExternalTypedData` (usually easier than a full ring buffer).
* Keep socket mode as a fallback for portability and debugging.

---

## A few “quick wins” that directly match your current code

These are specific to what’s in the attached files:

* **Dart `_BridgeSocketWriter` is async-with-no-await** → remove async/await and stop awaiting writes inside `_handleBridgeSocket`. This reduces per-request scheduling overhead immediately.
* **Dart direct path eagerly builds `Uri` and headers list** even when handler ignores them → make lazy.
* **Rust `proxy_request` allocates lots of `String`s** (headers, scheme, protocol, path/query) → encode from borrowed slices directly.
* **Rust `read_bridge_frame` allocates a new payload `Vec` every time** → reuse buffers per socket.

These four changes alone are the most likely to move `routed_ffi_direct` substantially toward `routed_ffi_native_direct` without changing the bridge protocol yet.

---

If you want, I can sketch concrete patch-style pseudocode for:

* a borrowed-field request encoder in Rust (no `String`/`Vec<(String,String)>` construction),
* a “lazy direct request view” in Dart that avoids `headers` materialization and `Uri` construction,
* and a protocol v2 header-token table layout that keeps v1 compatibility.




Below are **patch-style pseudocode sketches** that match your current code structure and wire format, but remove the biggest avoidable costs.

I’m keeping the patches “minimally invasive”: same framing (u32 length prefix over socket), same frame type IDs, and **v1 stays supported** while adding an opt-in **v2** tokenized header encoding.

---

# 1) Rust: borrowed-field request encoder (no `String` / no `Vec<(String,String)>`)

### Goals

* **Don’t build `BridgeRequest { String… headers: Vec<(String,String)> }`**.
* **Encode directly** from `Request::parts` and `HeaderMap` into `BridgeByteWriter`.
* Avoid header Vec allocation and avoid `split_path_and_query()` string allocations.

## Patch sketch (`lib.rs`)

### A. Replace `BridgeRequest` with a borrowed view + borrowed path split

```diff
@@
-use axum::http::{Request, Response, StatusCode, Version};
+use axum::http::{HeaderMap, Request, Response, StatusCode, Version};

-struct BridgeRequest {
-    method: String,
-    scheme: String,
-    authority: String,
-    path: String,
-    query: String,
-    protocol: String,
-    headers: Vec<(String, String)>,
-}
+struct BridgeRequestRef<'a> {
+    method: &'a str,
+    scheme: &'a str,
+    authority: &'a str,
+    path: &'a str,
+    query: &'a str,
+    protocol: &'a str,
+    headers: &'a HeaderMap,
+}
@@
-fn split_path_and_query(path_and_query: &str) -> (String, String) {
-    match path_and_query.split_once('?') {
-        Some((path, query)) => (path.to_string(), query.to_string()),
-        None => (path_and_query.to_string(), String::new()),
-    }
-}
+fn split_path_and_query_ref(path_and_query: &str) -> (&str, &str) {
+    match path_and_query.split_once('?') {
+        Some((path, query)) => (path, query),
+        None => (path_and_query, ""),
+    }
+}
```

### B. Update `proxy_request()` to build the borrowed request view

```diff
@@ async fn proxy_request(State(state): State<ProxyState>, request: Request<Body>) -> Response<Body> {
     let (parts, body) = request.into_parts();

     let path_and_query = parts
         .uri
         .path_and_query()
         .map(|value| value.as_str())
         .unwrap_or(parts.uri.path());
-    let (path, query) = split_path_and_query(path_and_query);
+    let (path, query) = split_path_and_query_ref(path_and_query);

     let body_stream = body.into_data_stream();

-    let authority = parts
-        .headers
-        .get("host")
-        .and_then(|value| value.to_str().ok())
-        .unwrap_or_default()
-        .to_string();
-    let scheme = parts.uri.scheme_str().unwrap_or("http").to_string();
-
-    let mut headers = Vec::with_capacity(parts.headers.len());
-    for (name, value) in parts.headers.iter() {
-        let value = match value.to_str() {
-            Ok(value) => value.to_string(),
-            Err(_) => continue,
-        };
-        headers.push((name.as_str().to_string(), value));
-    }
-
-    let bridge_request = BridgeRequest {
-        method: parts.method.as_str().to_string(),
-        scheme,
-        authority,
-        path,
-        query,
-        protocol: http_version_to_protocol(parts.version).to_string(),
-        headers,
-    };
+    let authority = parts
+        .headers
+        .get("host")
+        .and_then(|value| value.to_str().ok())
+        .unwrap_or_default();
+    let scheme = parts.uri.scheme_str().unwrap_or("http");
+    let protocol = http_version_to_protocol(parts.version);
+
+    let bridge_request = BridgeRequestRef {
+        method: parts.method.as_str(),
+        scheme,
+        authority,
+        path,
+        query,
+        protocol,
+        headers: &parts.headers,
+    };

     let (bridge_status, bridge_headers, bridge_body) =
-        match call_bridge(&state.bridge_pool, bridge_request, body_stream).await {
+        match call_bridge(&state.bridge_pool, bridge_request, body_stream).await {
```

### C. Update `call_bridge` / writers to accept `BridgeRequestRef<'_>`

```diff
@@
-async fn call_bridge(
-    bridge_pool: &Arc<BridgePool>,
-    request: BridgeRequest,
-    mut request_body_stream: BodyDataStream,
-) -> Result<(u16, Vec<(String, String)>, Body), String> {
+async fn call_bridge(
+    bridge_pool: &Arc<BridgePool>,
+    request: BridgeRequestRef<'_>,
+    mut request_body_stream: BodyDataStream,
+) -> Result<(u16, Vec<(String, String)>, Body), String> {
     let mut socket = bridge_pool.acquire().await?;
@@
-        &request,
+        &request,
@@
-async fn call_bridge_retry_empty_body(
-    bridge_pool: &Arc<BridgePool>,
-    request: &BridgeRequest,
-) -> Result<(u16, Vec<(String, String)>, Body), String> {
+async fn call_bridge_retry_empty_body(
+    bridge_pool: &Arc<BridgePool>,
+    request: &BridgeRequestRef<'_>,
+) -> Result<(u16, Vec<(String, String)>, Body), String> {
@@
-async fn write_bridge_request(
+async fn write_bridge_request(
     socket: &mut dyn BridgeStream,
-    request: &BridgeRequest,
+    request: &BridgeRequestRef<'_>,
     request_body_stream: &mut BodyDataStream,
     request_body_empty: &mut bool,
 ) -> Result<(), String> {
@@
-async fn write_bridge_empty_request(
+async fn write_bridge_empty_request(
     socket: &mut dyn BridgeStream,
-    request: &BridgeRequest,
+    request: &BridgeRequestRef<'_>,
 ) -> Result<(), String> {
```

### D. Encode directly from the borrowed view (single pass, patch header count in-place)

Add small “reserve/patch” helpers to the writer:

```diff
@@ struct BridgeByteWriter {
 impl BridgeByteWriter {
@@
+    fn reserve(&mut self, additional: usize) {
+        self.bytes.reserve(additional);
+    }
+
+    fn reserve_u32(&mut self) -> usize {
+        let pos = self.bytes.len();
+        self.bytes.extend_from_slice(&0u32.to_be_bytes());
+        pos
+    }
+
+    fn patch_u32(&mut self, pos: usize, value: u32) {
+        self.bytes[pos..pos + 4].copy_from_slice(&value.to_be_bytes());
+    }
 }
```

Now rewrite encoders to avoid `Vec<(String,String)>` completely:

```diff
-fn encode_bridge_request_start(request: &BridgeRequest) -> Result<Vec<u8>, String> {
+fn encode_bridge_request_start(request: &BridgeRequestRef<'_>) -> Result<Vec<u8>, String> {
     let mut writer = BridgeByteWriter::new();
+    // Optional: crude reserve (prevents several reallocs under load)
+    writer.reserve(256 + request.headers.len() * 32);
     writer.put_u8(BRIDGE_PROTOCOL_VERSION);
     writer.put_u8(BRIDGE_REQUEST_START_FRAME_TYPE);
     writer.put_string(request.method)?;
     writer.put_string(request.scheme)?;
     writer.put_string(request.authority)?;
     writer.put_string(request.path)?;
     writer.put_string(request.query)?;
     writer.put_string(request.protocol)?;
-    writer.put_u32(
-        u32::try_from(request.headers.len())
-            .map_err(|_| "bridge request has too many headers".to_string())?,
-    );
-    for (name, value) in request.headers.iter() {
-        writer.put_string(name)?;
-        writer.put_string(value)?;
-    }
+    // header_count placeholder (we only count UTF-8 values we actually emit)
+    let count_pos = writer.reserve_u32();
+    let mut count: u32 = 0;
+    for (name, value) in request.headers.iter() {
+        let Ok(value_str) = value.to_str() else { continue };
+        count += 1;
+        writer.put_string(name.as_str())?;
+        writer.put_string(value_str)?;
+    }
+    writer.patch_u32(count_pos, count);
     Ok(writer.into_inner())
 }
@@
-fn encode_bridge_request(request: &BridgeRequest, body_bytes: &[u8]) -> Result<Vec<u8>, String> {
+fn encode_bridge_request(request: &BridgeRequestRef<'_>, body_bytes: &[u8]) -> Result<Vec<u8>, String> {
     let mut writer = BridgeByteWriter::new();
+    writer.reserve(256 + request.headers.len() * 32 + body_bytes.len());
     writer.put_u8(BRIDGE_PROTOCOL_VERSION);
     writer.put_u8(BRIDGE_REQUEST_FRAME_TYPE);
     writer.put_string(request.method)?;
     writer.put_string(request.scheme)?;
     writer.put_string(request.authority)?;
     writer.put_string(request.path)?;
     writer.put_string(request.query)?;
     writer.put_string(request.protocol)?;
-    writer.put_u32(
-        u32::try_from(request.headers.len())
-            .map_err(|_| "bridge request has too many headers".to_string())?,
-    );
-    for (name, value) in request.headers.iter() {
-        writer.put_string(name)?;
-        writer.put_string(value)?;
-    }
+    let count_pos = writer.reserve_u32();
+    let mut count: u32 = 0;
+    for (name, value) in request.headers.iter() {
+        let Ok(value_str) = value.to_str() else { continue };
+        count += 1;
+        writer.put_string(name.as_str())?;
+        writer.put_string(value_str)?;
+    }
+    writer.patch_u32(count_pos, count);
     writer.put_bytes(body_bytes)?;
     Ok(writer.into_inner())
 }
```

That change alone removes:

* `authority.to_string()`, `scheme.to_string()`, `protocol.to_string()`, `method.to_string()`
* `split_path_and_query` allocations
* `Vec<(String,String)>` headers + per-header string clones

---

# 2) Dart: “lazy direct request view” (no header list materialization, no eager `Uri`)

### Goals

* Stop calling `frame.headers` (which creates `List<MapEntry<...>>`).
* Stop building `Uri` in the request constructor when the handler may not use it.
* Keep **source-compatible** API for direct handlers: `request.method`, `request.headers`, `request.uri`, `request.header(name)`.

## Patch sketch (`server_boot.dart`)

### A. Replace `FfiDirectRequest` with a frame-backed lazy view

```diff
@@
 final class FfiDirectRequest {
-  FfiDirectRequest({
-    required this.method,
-    required this.scheme,
-    required this.authority,
-    required this.path,
-    required this.query,
-    required this.protocol,
-    required this.headers,
-    required this.body,
-  }) : uri = _buildDirectUri(
-         scheme: scheme,
-         authority: authority,
-         path: path,
-         query: query,
-       );
-
-  final String method;
-  final String scheme;
-  final String authority;
-  final String path;
-  final String query;
-  final String protocol;
-  final List<MapEntry<String, String>> headers;
-  final Stream<Uint8List> body;
-  final Uri uri;
+  FfiDirectRequest._fromFrame(this._frame, this.body);
+
+  final BridgeRequestFrame _frame;
+  final Stream<Uint8List> body;
+
+  String get method => _frame.method;
+  String get scheme => _frame.scheme;
+  String get authority => _frame.authority;
+  String get path => _frame.path;
+  String get query => _frame.query;
+  String get protocol => _frame.protocol;
+
+  // Lazy: only computed if handler reads request.uri
+  late final Uri uri = _buildDirectUri(
+    scheme: scheme,
+    authority: authority,
+    path: path,
+    query: query,
+  );
+
+  // Lazy: this is a *view*; no per-request List.generate()
+  late final List<MapEntry<String, String>> headers =
+      UnmodifiableListView(_DirectHeaderListView(_frame));
@@
   String? header(String name) {
-    final target = name;
-    for (final entry in headers) {
-      if (_equalsAsciiIgnoreCase(entry.key, target)) {
-        return entry.value;
-      }
-    }
-    return null;
+    final target = name;
+    final n = _frame.headerCount;
+    for (var i = 0; i < n; i++) {
+      if (_equalsAsciiIgnoreCase(_frame.headerNameAt(i), target)) {
+        return _frame.headerValueAt(i);
+      }
+    }
+    return null;
   }
 }
+
+/// Random-access view over BridgeRequestFrame headers without materializing
+/// a List<MapEntry<...>> each request. MapEntry objects are created *on demand*.
+final class _DirectHeaderListView extends ListBase<MapEntry<String, String>> {
+  _DirectHeaderListView(this._frame);
+  final BridgeRequestFrame _frame;
+
+  @override
+  int get length => _frame.headerCount;
+  @override
+  set length(int _) => throw UnsupportedError('unmodifiable');
+
+  @override
+  MapEntry<String, String> operator [](int index) =>
+      MapEntry(_frame.headerNameAt(index), _frame.headerValueAt(index));
+
+  @override
+  void operator []=(int index, MapEntry<String, String> value) =>
+      throw UnsupportedError('unmodifiable');
+}
```

### B. Update `_toDirectRequest()` so it **never calls** `frame.headers`

```diff
 FfiDirectRequest _toDirectRequest(
   BridgeRequestFrame frame,
   Stream<Uint8List> bodyStream,
 ) {
-  return FfiDirectRequest(
-    method: frame.method,
-    scheme: frame.scheme,
-    authority: frame.authority,
-    path: frame.path,
-    query: frame.query,
-    protocol: frame.protocol,
-    headers: frame.headers,
-    body: bodyStream,
-  );
+  return FfiDirectRequest._fromFrame(frame, bodyStream);
 }
```

That’s the key line: **you stop paying `List<MapEntry>.generate(...)` per request**, and you stop building `Uri` unless it’s accessed.

---

# 3) Protocol v2 header-token table layout (supports v1 + v2)

This adds a **v2 encoding** where header *names* are tokenized, while **v1 stays valid** and decoders accept both.

## 3.1 Wire layout

### v1 header entry (today)

```
name:  string   (u32 len + bytes)
value: string   (u32 len + bytes)
```

### v2 header entry (tokenized name, literal fallback)

```
name_token: u16   // 0 = literal name follows, else 1..N index into static table
if name_token == 0:
  name: string
value: string
```

Everything else stays in the same order as v1 (method/scheme/path/query/protocol are still strings).

## 3.2 Shared token table (must match Rust + Dart order)

Example (keep this list short and stable; add later at the end only):

```text
1  host
2  connection
3  content-type
4  content-length
5  accept
6  accept-encoding
7  accept-language
8  user-agent
9  cache-control
10 pragma
11 authorization
12 cookie
13 set-cookie
14 origin
15 referer
16 x-forwarded-for
17 x-forwarded-proto
18 x-request-id
19 upgrade
20 transfer-encoding
21 content-encoding
22 location
23 server
24 date
25 etag
26 if-none-match
27 last-modified
28 if-modified-since
29 vary
```

Token `0` always means “literal string follows”.

---

## 3.3 Rust patch sketch (`lib.rs`): v1 + v2 decode/encode

### A. Add protocol constants + header token helpers

```diff
-const BRIDGE_PROTOCOL_VERSION: u8 = 1;
+const BRIDGE_PROTOCOL_VERSION_V1: u8 = 1;
+const BRIDGE_PROTOCOL_VERSION_V2: u8 = 2;

+const HEADER_TOKEN_LITERAL: u16 = 0;
+
+// 1-based tokens (index 0 unused)
+fn header_name_to_token(name: &str) -> u16 {
+    match name {
+        "host" => 1,
+        "connection" => 2,
+        "content-type" => 3,
+        "content-length" => 4,
+        "accept" => 5,
+        "accept-encoding" => 6,
+        "accept-language" => 7,
+        "user-agent" => 8,
+        "cache-control" => 9,
+        "pragma" => 10,
+        "authorization" => 11,
+        "cookie" => 12,
+        "set-cookie" => 13,
+        "origin" => 14,
+        "referer" => 15,
+        "x-forwarded-for" => 16,
+        "x-forwarded-proto" => 17,
+        "x-request-id" => 18,
+        "upgrade" => 19,
+        "transfer-encoding" => 20,
+        "content-encoding" => 21,
+        "location" => 22,
+        "server" => 23,
+        "date" => 24,
+        "etag" => 25,
+        "if-none-match" => 26,
+        "last-modified" => 27,
+        "if-modified-since" => 28,
+        "vary" => 29,
+        _ => HEADER_TOKEN_LITERAL,
+    }
+}
+
+fn header_token_to_name(token: u16) -> Option<&'static str> {
+    match token {
+        1 => Some("host"),
+        2 => Some("connection"),
+        3 => Some("content-type"),
+        4 => Some("content-length"),
+        5 => Some("accept"),
+        6 => Some("accept-encoding"),
+        7 => Some("accept-language"),
+        8 => Some("user-agent"),
+        9 => Some("cache-control"),
+        10 => Some("pragma"),
+        11 => Some("authorization"),
+        12 => Some("cookie"),
+        13 => Some("set-cookie"),
+        14 => Some("origin"),
+        15 => Some("referer"),
+        16 => Some("x-forwarded-for"),
+        17 => Some("x-forwarded-proto"),
+        18 => Some("x-request-id"),
+        19 => Some("upgrade"),
+        20 => Some("transfer-encoding"),
+        21 => Some("content-encoding"),
+        22 => Some("location"),
+        23 => Some("server"),
+        24 => Some("date"),
+        25 => Some("etag"),
+        26 => Some("if-none-match"),
+        27 => Some("last-modified"),
+        28 => Some("if-modified-since"),
+        29 => Some("vary"),
+        _ => None,
+    }
+}
```

Add `put_u16` to `BridgeByteWriter`:

```diff
 impl BridgeByteWriter {
@@
+    fn put_u16(&mut self, value: u16) {
+        self.bytes.extend_from_slice(&value.to_be_bytes());
+    }
 }
```

### B. Make `peek_bridge_frame_type` accept v1 or v2

```diff
 fn peek_bridge_frame_type(payload: &[u8]) -> Result<u8, String> {
@@
     let version = payload[0];
-    if version != BRIDGE_PROTOCOL_VERSION {
+    if version != BRIDGE_PROTOCOL_VERSION_V1 && version != BRIDGE_PROTOCOL_VERSION_V2 {
         return Err(format!("unsupported bridge protocol version: {version}"));
     }
     Ok(payload[1])
 }
```

### C. Encode v2 headers in request start / legacy request

Add helpers for v2 header encoding:

```rust
fn put_header_name_v2(writer: &mut BridgeByteWriter, name: &str) -> Result<(), String> {
    let token = header_name_to_token(name);
    writer.put_u16(token);
    if token == HEADER_TOKEN_LITERAL {
        writer.put_string(name)?;
    }
    Ok(())
}
```

Then in your encoder, switch on chosen version:

```diff
-fn encode_bridge_request_start(request: &BridgeRequestRef<'_>) -> Result<Vec<u8>, String> {
+fn encode_bridge_request_start_v1(request: &BridgeRequestRef<'_>) -> Result<Vec<u8>, String> { ... } // from section 1
+
+fn encode_bridge_request_start_v2(request: &BridgeRequestRef<'_>) -> Result<Vec<u8>, String> {
     let mut writer = BridgeByteWriter::new();
-    writer.put_u8(BRIDGE_PROTOCOL_VERSION);
+    writer.put_u8(BRIDGE_PROTOCOL_VERSION_V2);
     writer.put_u8(BRIDGE_REQUEST_START_FRAME_TYPE);
@@
     let count_pos = writer.reserve_u32();
     let mut count: u32 = 0;
     for (name, value) in request.headers.iter() {
         let Ok(value_str) = value.to_str() else { continue };
         count += 1;
-        writer.put_string(name.as_str())?;
+        put_header_name_v2(&mut writer, name.as_str())?;
         writer.put_string(value_str)?;
     }
     writer.patch_u32(count_pos, count);
     Ok(writer.into_inner())
 }
```

Same for the legacy single-frame request:

```diff
-fn encode_bridge_request(request: &BridgeRequestRef<'_>, body_bytes: &[u8]) -> Result<Vec<u8>, String> {
+fn encode_bridge_request_v2(request: &BridgeRequestRef<'_>, body_bytes: &[u8]) -> Result<Vec<u8>, String> {
     let mut writer = BridgeByteWriter::new();
-    writer.put_u8(BRIDGE_PROTOCOL_VERSION);
+    writer.put_u8(BRIDGE_PROTOCOL_VERSION_V2);
     writer.put_u8(BRIDGE_REQUEST_FRAME_TYPE);
@@
-        writer.put_string(name.as_str())?;
+        put_header_name_v2(&mut writer, name.as_str())?;
         writer.put_string(value_str)?;
@@
 }
```

Then in `write_bridge_request`, choose which encoder to call (config flag, env var, etc.):

```rust
let use_v2 = true; // TODO: config/feature gate
let start_payload = if use_v2 {
    encode_bridge_request_start_v2(request)?
} else {
    encode_bridge_request_start_v1(request)?
};
```

### D. Decode v2 response headers (so Dart can also tokenize its response header names)

Add helper to decode header name v2:

```rust
fn get_header_name_v2(reader: &mut BridgeByteReader<'_>) -> Result<String, String> {
    let token = reader.get_u16()?;
    if token == HEADER_TOKEN_LITERAL {
        return reader.get_string();
    }
    let name = header_token_to_name(token)
        .ok_or_else(|| format!("invalid header token: {token}"))?;
    Ok(name.to_string())
}
```

Update response decoders to accept v1 or v2:

```diff
 fn decode_bridge_response(payload: Vec<u8>) -> Result<BridgeResponse, String> {
     let mut reader = BridgeByteReader::new(&payload);
     let version = reader.get_u8()?;
-    if version != BRIDGE_PROTOCOL_VERSION {
+    if version != BRIDGE_PROTOCOL_VERSION_V1 && version != BRIDGE_PROTOCOL_VERSION_V2 {
         return Err(format!("unsupported bridge protocol version: {version}"));
     }
@@
     let header_count = reader.get_u32()? as usize;
     let mut headers = Vec::with_capacity(header_count);
     for _ in 0..header_count {
-        let name = reader.get_string()?;
+        let name = if version == BRIDGE_PROTOCOL_VERSION_V2 {
+            get_header_name_v2(&mut reader)?
+        } else {
+            reader.get_string()?
+        };
         let value = reader.get_string()?;
         headers.push((name, value));
     }
```

Do the same for `decode_bridge_response_start`.

---

## 3.4 Dart patch sketch (`bridge_runtime.dart`): decode both, encode either

### A. Support both protocol versions in the header validator

```diff
-const int bridgeFrameProtocolVersion = 1;
+const int bridgeFrameProtocolVersionV1 = 1;
+const int bridgeFrameProtocolVersionV2 = 2;
+
+// Outbound can be chosen at runtime (config/feature gate)
+const int bridgeFrameProtocolVersionOut = bridgeFrameProtocolVersionV2;
```

```diff
-int _readAndValidateHeader(
+int _readAndValidateHeaderV1V2(
   _BridgeFrameReader reader, {
   required int expectedFrameType,
   required String frameLabel,
 }) {
   final version = reader.readUint8();
-  if (version != bridgeFrameProtocolVersion) {
+  if (version != bridgeFrameProtocolVersionV1 &&
+      version != bridgeFrameProtocolVersionV2) {
     throw FormatException('unsupported bridge protocol version: $version');
   }
   final frameType = reader.readUint8();
   if (frameType != expectedFrameType) {
     throw FormatException('invalid bridge $frameLabel frame type: $frameType');
   }
-  return frameType;
+  return version; // return version so caller can branch
 }
```

Update callers (example for start payload decode):

```diff
 factory BridgeRequestFrame.decodeStartPayload(Uint8List payload) {
   final reader = _BridgeFrameReader(payload);
-  final frameType = _readAndValidateHeader(
+  final version = _readAndValidateHeaderV1V2(
     reader,
     expectedFrameType: _bridgeRequestStartFrameType,
     frameLabel: 'request start',
   );
-  if (frameType != _bridgeRequestStartFrameType) { ... }
+  // frame type already validated; version tells us how to parse headers
@@
-  for (var i = 0; i < headerCount; i++) {
-    headerNames[i] = reader.readString();
-    headerValues[i] = reader.readString();
-  }
+  for (var i = 0; i < headerCount; i++) {
+    headerNames[i] = (version == bridgeFrameProtocolVersionV2)
+        ? _readHeaderNameV2(reader)
+        : reader.readString();
+    headerValues[i] = reader.readString();
+  }
```

### B. Add the token table + read/write helpers

```dart
const int _headerTokenLiteral = 0;

// 1-based tokens
const List<String> _headerNameTable = <String>[
  'host',
  'connection',
  'content-type',
  'content-length',
  'accept',
  'accept-encoding',
  'accept-language',
  'user-agent',
  'cache-control',
  'pragma',
  'authorization',
  'cookie',
  'set-cookie',
  'origin',
  'referer',
  'x-forwarded-for',
  'x-forwarded-proto',
  'x-request-id',
  'upgrade',
  'transfer-encoding',
  'content-encoding',
  'location',
  'server',
  'date',
  'etag',
  'if-none-match',
  'last-modified',
  'if-modified-since',
  'vary',
];

int _headerNameToToken(String name) {
  // Fast path assumes canonical lowercase (HttpHeaders constants already are).
  switch (name) {
    case 'host': return 1;
    case 'connection': return 2;
    case 'content-type': return 3;
    case 'content-length': return 4;
    case 'accept': return 5;
    case 'accept-encoding': return 6;
    case 'accept-language': return 7;
    case 'user-agent': return 8;
    case 'cache-control': return 9;
    case 'pragma': return 10;
    case 'authorization': return 11;
    case 'cookie': return 12;
    case 'set-cookie': return 13;
    case 'origin': return 14;
    case 'referer': return 15;
    case 'x-forwarded-for': return 16;
    case 'x-forwarded-proto': return 17;
    case 'x-request-id': return 18;
    case 'upgrade': return 19;
    case 'transfer-encoding': return 20;
    case 'content-encoding': return 21;
    case 'location': return 22;
    case 'server': return 23;
    case 'date': return 24;
    case 'etag': return 25;
    case 'if-none-match': return 26;
    case 'last-modified': return 27;
    case 'if-modified-since': return 28;
    case 'vary': return 29;
    default: return _headerTokenLiteral;
  }
}

String _tokenToHeaderName(int token) {
  final idx = token - 1;
  if (idx < 0 || idx >= _headerNameTable.length) {
    throw FormatException('invalid header token: $token');
  }
  return _headerNameTable[idx];
}

void _writeHeaderNameV2(_BridgeFrameWriter writer, String name) {
  final token = _headerNameToToken(name);
  writer.writeUint16(token);
  if (token == _headerTokenLiteral) {
    writer.writeString(name);
  }
}

String _readHeaderNameV2(_BridgeFrameReader reader) {
  final token = reader.readUint16();
  if (token == _headerTokenLiteral) {
    return reader.readString();
  }
  return _tokenToHeaderName(token);
}
```

### C. Update request/response encoders to emit v2 when desired

Example: `BridgeResponseFrame.encodePayloadPrefixWithoutBody`:

```diff
 Uint8List encodePayloadPrefixWithoutBody() {
   final writer = _BridgeFrameWriter();
-  writer.writeUint8(bridgeFrameProtocolVersion);
+  writer.writeUint8(bridgeFrameProtocolVersionOut);
   writer.writeUint8(_bridgeResponseFrameType);
   writer.writeUint16(status);
   writer.writeUint32(headerCount);
   for (var i = 0; i < headerCount; i++) {
-    writer.writeString(headerNameAt(i));
+    if (bridgeFrameProtocolVersionOut == bridgeFrameProtocolVersionV2) {
+      _writeHeaderNameV2(writer, headerNameAt(i));
+    } else {
+      writer.writeString(headerNameAt(i));
+    }
     writer.writeString(headerValueAt(i));
   }
   writer.writeUint32(bodyBytes.length);
   return writer.takeBytes();
 }
```

And in response decode:

```diff
 factory BridgeResponseFrame.decodePayload(Uint8List payload) {
   final reader = _BridgeFrameReader(payload);
   final version = reader.readUint8();
-  if (version != bridgeFrameProtocolVersion) {
+  if (version != bridgeFrameProtocolVersionV1 &&
+      version != bridgeFrameProtocolVersionV2) {
     throw FormatException('unsupported bridge protocol version: $version');
   }
   final frameType = reader.readUint8();
@@
   for (var i = 0; i < headerCount; i++) {
-    headerNames[i] = reader.readString();
+    headerNames[i] = (version == bridgeFrameProtocolVersionV2)
+        ? _readHeaderNameV2(reader)
+        : reader.readString();
     headerValues[i] = reader.readString();
   }
```

Apply the same pattern to:

* `BridgeRequestFrame.decodePayload` (legacy single frame)
* `BridgeRequestFrame.decodeStartPayload`
* `BridgeResponseFrame.decodeStartPayload` (streaming)
* `BridgeRequestFrame.encodePayload/encodeStartPayload`
* `BridgeResponseFrame.encodePayload/encodeStartPayload`

Chunk/end frames don’t include headers, so only the version validation changes.

---

## What you get immediately

* **Rust borrowed encoder** removes a large chunk of per-request allocation/copy work on the proxy side.
* **Lazy direct request view** eliminates header list materialization and eager `Uri` build in the benchmark path (and in many real handlers that don’t touch them).
* **v2 header tokenization** reduces:

  * bytes over the bridge
  * decode time and **string allocations** for common header names in Dart (and optionally in Rust decode too)

If you want, I can also sketch the *next* incremental v2 step that gives another big win without going full shared memory: **encode header values as raw bytes** (not UTF-8 strings) and only decode to `String` lazily when needed.
