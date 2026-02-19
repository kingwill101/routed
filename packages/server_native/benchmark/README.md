# Framework Benchmarks

This directory holds framework-level transport benchmarks for `server_native`.

## Goal

Measure before/after transport swaps:

- baseline: `dart:io HttpServer`
- switched: `server_native NativeHttpServer`

for the same framework handler logic.

Current framework adapters:

- `dart:io`
- `routed`
- `relic`
- `shelf`
- `native_direct` (Rust static direct path, non-framework)

## Run

From `packages/server_native/`:

```bash
dart run benchmark/framework_transport_benchmark.dart
```

Useful options:

```bash
dart run benchmark/framework_transport_benchmark.dart \
  --framework=all \
  --requests=2500 \
  --concurrency=64 \
  --warmup=300 \
  --iterations=25 \
  --native-callback=true
```

JSON output:

```bash
dart run benchmark/framework_transport_benchmark.dart --json
```

## Cases

- `dart_io_io`
- `dart_io_native`
- `routed_io`
- `routed_native`
- `relic_io`
- `relic_native`
- `shelf_io`
- `shelf_native`
- `native_direct_rust`

The `*_native` cases use `NativeHttpServer` and can be toggled between
native-callback and bridge-socket path via `--native-callback=...`.

## `--native-callback` Meaning

- `--native-callback=true`:
  Rust accepts the socket and invokes Dart request handling through the direct
  FFI callback path (bridge socket bypassed), while keeping
  `HttpRequest`/`HttpResponse` compatibility in `NativeHttpServer`.
- `--native-callback=false`:
  Rust and Dart communicate over the bridge socket/frame path before requests
  are materialized as `HttpRequest`/`HttpResponse`.
- `native_direct_rust` is a pure Rust static benchmark mode and does not use
  Dart `HttpRequest` handling, so this flag does not change its code path.

## Latest Results

Host run date: **February 19, 2026**  
Command (both modes):

```bash
dart run benchmark/framework_transport_benchmark.dart \
  --framework=all \
  --requests=2500 \
  --concurrency=64 \
  --warmup=300 \
  --iterations=25 \
  --native-callback=true \
  --json

dart run benchmark/framework_transport_benchmark.dart \
  --framework=all \
  --requests=2500 \
  --concurrency=64 \
  --warmup=300 \
  --iterations=25 \
  --native-callback=false \
  --json
```

### `nativeCallback=true`

| Case | req/s | p95 (ms) |
| --- | ---: | ---: |
| native_direct_rust | 12362 | 6.34 |
| dart_io_native | 8370 | 9.05 |
| dart_io_io | 7703 | 9.72 |
| routed_native | 7110 | 10.88 |
| relic_native | 6823 | 11.31 |
| shelf_native | 6524 | 11.66 |
| routed_io | 5703 | 12.51 |
| shelf_io | 5181 | 14.08 |
| relic_io | 5073 | 14.46 |

### `nativeCallback=false`

| Case | req/s | p95 (ms) |
| --- | ---: | ---: |
| native_direct_rust | 12656 | 6.17 |
| dart_io_native | 7565 | 10.60 |
| dart_io_io | 6938 | 10.31 |
| routed_native | 6392 | 11.93 |
| relic_native | 5990 | 12.73 |
| shelf_native | 5843 | 13.07 |
| routed_io | 5792 | 12.56 |
| relic_io | 5267 | 13.80 |
| shelf_io | 5071 | 14.40 |

## Benchmark Context

These numbers are from the author's local development machine and should be
treated as directional, not absolute. Throughput and latency will vary across
CPU generations, power settings, kernel/network stack, and background load.

Test host used for the results above:

- Date: `2026-02-19T02:29:38-05:00`
- OS: `Manjaro Linux (rolling)`
- Kernel: `Linux 6.18.8-1-MANJARO x86_64`
- CPU: `Intel Core i7-10510U` (4 cores / 8 threads, turbo up to 4.9 GHz)
- Memory: `31 GiB`
- Logical CPUs: `8`
- CPU governor: `powersave`
- Intel turbo setting (`intel_pstate/no_turbo`): `0` (turbo enabled)
- Dart SDK: `3.10.4 (stable) on linux_x64`
- Rust toolchain (native package override): `1.92.0`

Run conditions:

- Benchmarks were executed on a non-dedicated local workstation.
- Background processes were not fully eliminated.
- Results are best used for relative comparisons across cases in the same run.
