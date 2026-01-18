# Dart HTTP Framework Benchmarks

Performance comparison of Dart HTTP frameworks using reproducible methodology.

## Frameworks Tested

| Framework | Description | Port |
|-----------|-------------|------|
| **dart:io** | Raw `HttpServer` baseline (no framework) | 8001 |
| **relic** | Serverpod Relic framework | 8007 |
| **serinus** | Modular framework with DI | 8003 |
| **shelf** | Google's composable middleware framework | 8002 |
| **routed** | This framework | 8006 |

## Endpoints

| Endpoint | Work Done |
|----------|-----------|
| `GET /` | Return plain text `"ok"` |
| `GET /json` | Serialize `{"ok": true}` at runtime with `jsonEncode()` |

All JSON endpoints perform runtime serialization for fair comparison.

## Quick Start

```bash
# Run full benchmark suite (AOT + JIT, 3 runs each)
cd benchmarks
./scripts/full_benchmark.sh

# AOT only
MODE=aot ./scripts/full_benchmark.sh

# JIT only
MODE=jit ./scripts/full_benchmark.sh

# More runs for stability
RUNS=5 ./scripts/full_benchmark.sh
```

Results are saved to `benchmarks/results/` with timestamps.

## Methodology

### Compilation Modes

| Mode | Command | Use Case |
|------|---------|----------|
| **AOT** | `dart compile exe` | Production deployments, cold-start |
| **JIT** | `dart run` | Development, long-running with warmup |

### Protocol

1. **Build** - Compile all servers to native executables (AOT mode)
2. **Start** - Launch server under test
3. **Warmup** - 5s (AOT) or 10s (JIT) load to prime caches and JIT optimizer
4. **Measure** - Multiple runs per endpoint (default: 3)
5. **Report** - Median RPS (resistant to outliers), min/max range, median avg latency, median p99
6. **Stop** - Kill server before next framework

### Load Parameters

```bash
wrk -t4 -c100 -d10s <url>
```

| Parameter | Default | Description |
|-----------|---------|-------------|
| `THREADS` | 4 | wrk threads |
| `CONCURRENCY` | 100 | Concurrent connections |
| `DURATION` | 10s | Measurement duration |
| `WARMUP_DURATION_AOT` | 5s | AOT warmup |
| `WARMUP_DURATION_JIT` | 10s | JIT warmup (longer for optimization) |
| `RUNS` | 3 | Runs per endpoint |

### Endpoint Order

Fixed order to eliminate ordering effects:
1. `GET /` (plain text)
2. `GET /json` (JSON serialization)

### Statistical Reporting

- **Median RPS** - Primary metric, resistant to outliers
- **Min/Max** - Shows variance range
- **Avg latency (median)** - Median of avg response time across runs
- **P99 (median)** - Median of p99 across runs (tail latency)

## Manual Benchmarking

### Build AOT Executables

```bash
./scripts/dart_build.sh
# Or individually:
cd servers/routed && dart compile exe bin/server.dart -o bin/server
```

### Run Individual Server

```bash
# AOT
./scripts/dart_run_bin.sh routed

# JIT  
./scripts/dart_run_jit.sh routed
```

### Run Benchmark

```bash
# Warmup
wrk -t4 -c100 -d5s http://127.0.0.1:8006/

# Measure
wrk -t4 -c100 -d10s http://127.0.0.1:8006/
wrk -t4 -c100 -d10s http://127.0.0.1:8006/json
```

## Docker

Build and run via compose profiles:

```bash
cd benchmarks

# AOT servers
docker compose --profile aot up -d --build

# JIT servers
docker compose --profile jit up -d --build

# Run benchmark
docker compose --profile bench run --rm \
  -e URL=http://routed_aot:8006/ \
  bench
```

## Interpreting Results

### What the Numbers Mean

- **dart:io** is the theoretical ceiling - raw `HttpServer` with no abstractions
- Framework overhead = 100% - (framework RPS / dart:io RPS)
- Lower latency and higher RPS are better

### Typical Results

Based on the latest full benchmark run (AOT + JIT, 3 runs, 10s duration).

| Framework | AOT / (RPS) | AOT /json (RPS) | % of dart:io (/) |
|-----------|-------------|-----------------|------------------|
| dart:io | ~18,600 | ~17,500 | 100% |
| routed | ~13,700 | ~14,300 | ~74% |
| shelf | ~12,800 | ~11,700 | ~69% |
| serinus | ~12,400 | ~11,400 | ~67% |
| relic | ~11,900 | ~11,600 | ~64% |

*Results vary by hardware and thermal state. Relative rankings are stable.*

### AOT vs JIT

- **AOT typically wins** for simple request handlers (less runtime overhead)
- **JIT may win** for complex handlers after sufficient warmup
- Use AOT for production, JIT for development

## Variance

Results vary ±10% between runs due to:
- OS scheduler decisions
- GC timing
- Thermal throttling
- Background processes

Run multiple times and use median for stable comparisons.

## Adding a Framework

1. Create `servers/<name>/` with standard structure
2. Implement `bin/server.dart` with `GET /` and `GET /json`
3. Use `PORT` environment variable (assign unique port)
4. Add to `SERVERS` and `PORTS` arrays in `full_benchmark.sh`
5. Run benchmark suite

## Notes

- Keep only one server running per port
- The routed benchmark uses `Engine()` (not `Engine.full()`)
- All JSON endpoints must use `jsonEncode()` at runtime, not pre-serialized strings
- Results are git-ignored (`results/` directory)
