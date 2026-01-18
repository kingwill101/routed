#!/usr/bin/env bash
#
# Full Benchmark Suite
# ====================
# Reproducible benchmarking with AOT/JIT modes, warmup, multiple runs,
# and statistical reporting (median, min, max).
#
# Usage:
#   ./full_benchmark.sh              # Run both AOT and JIT
#   MODE=aot ./full_benchmark.sh     # AOT only
#   MODE=jit ./full_benchmark.sh     # JIT only
#   RUNS=5 ./full_benchmark.sh       # 5 runs per endpoint
#
set -euo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RESULTS_DIR="$ROOT_DIR/results"

# Configuration (override via environment)
DURATION=${DURATION:-10s}
CONCURRENCY=${CONCURRENCY:-100}
THREADS=${THREADS:-4}
WARMUP_DURATION_AOT=${WARMUP_DURATION_AOT:-5s}
WARMUP_DURATION_JIT=${WARMUP_DURATION_JIT:-10s}
RUNS=${RUNS:-3}
MODE=${MODE:-both}  # aot, jit, or both

# Servers to benchmark (order: baseline first, then frameworks alphabetically, routed last)
SERVERS=(dart_io relic serinus shelf routed)
ENDPOINTS=("/" "/json")

# Port mapping
declare -A PORTS=(
  [dart_io]=8001
  [relic]=8007
  [shelf]=8002
  [serinus]=8003
  [routed]=8006
)

mkdir -p "$RESULTS_DIR"

log() { echo "[$(date +%H:%M:%S)] $*"; }
err() { echo "[$(date +%H:%M:%S)] ERROR: $*" >&2; }

cleanup() {
  log "Cleaning up..."
  pkill -9 -f "servers/.*/bin/server" 2>/dev/null || true
  pkill -9 -f "dart run bin/server.dart" 2>/dev/null || true
  sleep 1
}
trap cleanup EXIT

wait_for_server() {
  local url=$1
  local timeout=${2:-15}
  local i=0
  while ! curl -sf "$url" >/dev/null 2>&1; do
    ((i++))
    if ((i >= timeout * 5)); then
      return 1
    fi
    sleep 0.2
  done
  return 0
}

build_all_aot() {
  log "Building AOT executables..."
  for name in "${SERVERS[@]}"; do
    local dir="$ROOT_DIR/servers/$name"
    if [[ -d "$dir" ]]; then
      log "  Building $name..."
      (cd "$dir" && dart pub get >/dev/null 2>&1 && dart compile exe bin/server.dart -o bin/server >/dev/null 2>&1) || {
        err "Failed to build $name"
        return 1
      }
    fi
  done
  log "Build complete."
}

median() {
  local arr=("$@")
  IFS=$'\n' sorted=($(sort -n <<<"${arr[*]}")); unset IFS
  local n=${#sorted[@]}
  echo "${sorted[$((n/2))]}"
}

# Normalize wrk latency values to microseconds for sorting.
to_us() {
  local raw="$1"
  local num unit
  num=$(printf "%s" "$raw" | sed -E 's/[^0-9.]+.*$//')
  unit=$(printf "%s" "$raw" | sed -E 's/[0-9.]+//g')
  case "$unit" in
    us|µs|μs) awk -v n="$num" 'BEGIN {printf "%.3f", n}' ;;
    ms) awk -v n="$num" 'BEGIN {printf "%.3f", n * 1000}' ;;
    s) awk -v n="$num" 'BEGIN {printf "%.3f", n * 1000000}' ;;
    *) awk -v n="$num" 'BEGIN {printf "%.3f", n}' ;;
  esac
}

us_to_ms() {
  local us="$1"
  awk -v n="$us" 'BEGIN {printf "%.2fms", n / 1000}'
}

# Results storage
declare -a ALL_RESULTS=()

run_benchmark() {
  local name=$1
  local mode=$2
  local port=${PORTS[$name]}
  local dir="$ROOT_DIR/servers/$name"
  local warmup_duration
  
  [[ "$mode" == "aot" ]] && warmup_duration=$WARMUP_DURATION_AOT || warmup_duration=$WARMUP_DURATION_JIT
  
  log "=== $name ($mode) on port $port ==="
  
  # Kill any existing servers on this port
  pkill -9 -f "servers/$name/bin/server" 2>/dev/null || true
  sleep 1
  
  # Start server
  if [[ "$mode" == "aot" ]]; then
    if [[ ! -x "$dir/bin/server" ]]; then
      err "Binary not found: $dir/bin/server"
      return 1
    fi
    PORT=$port "$dir/bin/server" >/dev/null 2>&1 &
  else
    (cd "$dir" && PORT=$port dart run bin/server.dart >/dev/null 2>&1) &
  fi
  local server_pid=$!
  
  # Wait for server
  if ! wait_for_server "http://127.0.0.1:$port/" 15; then
    err "Server not responding on port $port"
    kill $server_pid 2>/dev/null || true
    return 1
  fi
  log "Server ready (PID: $server_pid)"
  
  # Warmup
  log "Warmup ($warmup_duration)..."
  wrk -t"$THREADS" -c"$CONCURRENCY" -d"$warmup_duration" "http://127.0.0.1:$port/" >/dev/null 2>&1 || true
  
  # Benchmark each endpoint
  for endpoint in "${ENDPOINTS[@]}"; do
    local url="http://127.0.0.1:$port$endpoint"
    log "Benchmarking $endpoint..."
    
    local rps_values=()
    local latency_us_values=()
    local p99_us_values=()
    
    for ((run=1; run<=RUNS; run++)); do
      log "  Run $run/$RUNS..."
      local output
      output=$(wrk -t"$THREADS" -c"$CONCURRENCY" -d"$DURATION" --latency "$url" 2>&1)
      
      local rps=$(echo "$output" | grep "Requests/sec" | awk '{print $2}')
      local latency=$(echo "$output" | grep -E "^\s+Latency" | head -1 | awk '{print $2}')
      local p99=$(echo "$output" | grep "99%" | awk '{print $2}')
      
      rps_values+=("${rps:-0}")
      if [[ -n "$latency" ]]; then
        latency_us_values+=("$(to_us "$latency")")
      fi
      if [[ -n "$p99" ]]; then
        p99_us_values+=("$(to_us "$p99")")
      fi
      
      sleep 1
    done
    
    # Calculate stats
    local rps_median=$(median "${rps_values[@]}")
    IFS=$'\n' sorted_rps=($(sort -n <<<"${rps_values[*]}")); unset IFS
    local rps_min="${sorted_rps[0]}"
    local rps_max="${sorted_rps[-1]}"
    
    local latency_median_us="0"
    local p99_median_us="0"
    if (( ${#latency_us_values[@]} > 0 )); then
      latency_median_us=$(median "${latency_us_values[@]}")
    fi
    if (( ${#p99_us_values[@]} > 0 )); then
      p99_median_us=$(median "${p99_us_values[@]}")
    fi
    local latency_median_ms
    local p99_median_ms
    latency_median_ms=$(us_to_ms "$latency_median_us")
    p99_median_ms=$(us_to_ms "$p99_median_us")

    ALL_RESULTS+=("$name|$mode|$endpoint|$rps_median|$rps_min|$rps_max|$latency_median_ms|$p99_median_ms")
    log "  Result: $rps_median RPS (range: $rps_min - $rps_max)"
  done
  
  # Stop server
  kill $server_pid 2>/dev/null || true
  wait $server_pid 2>/dev/null || true
  log ""
}

generate_report() {
  local timestamp=$(date +%Y%m%d-%H%M%S)
  local report_file="$RESULTS_DIR/benchmark-$timestamp.md"
  
  {
    echo "# Dart HTTP Framework Benchmark"
    echo ""
    echo "**Generated:** $(date)"
    echo ""
    echo "## Configuration"
    echo ""
    echo "| Parameter | Value |"
    echo "|-----------|-------|"
    echo "| Duration | $DURATION |"
    echo "| Concurrency | $CONCURRENCY |"
    echo "| Threads | $THREADS |"
    echo "| Runs | $RUNS |"
    echo "| Warmup (AOT) | $WARMUP_DURATION_AOT |"
    echo "| Warmup (JIT) | $WARMUP_DURATION_JIT |"
    echo ""
    
    for current_mode in aot jit; do
      local has_results=false
      for result in "${ALL_RESULTS[@]}"; do
        IFS='|' read -r _ mode _ _ _ _ _ <<< "$result"
        [[ "$mode" == "$current_mode" ]] && has_results=true && break
      done
      
      if $has_results; then
        echo "## ${current_mode^^} Mode"
        echo ""
        echo "| Framework | Endpoint | Median RPS | Min | Max | Avg Latency (median) | P99 (median) |"
        echo "|-----------|----------|------------|-----|-----|----------------------|--------------|"
        for result in "${ALL_RESULTS[@]}"; do
          IFS='|' read -r name mode endpoint rps_med rps_min rps_max latency p99 <<< "$result"
          if [[ "$mode" == "$current_mode" ]]; then
            echo "| $name | \`$endpoint\` | **$rps_med** | $rps_min | $rps_max | $latency | $p99 |"
          fi
        done
        echo ""
      fi
    done
    
    echo "## Reproduction"
    echo ""
    echo "\`\`\`bash"
    echo "cd benchmarks && ./scripts/full_benchmark.sh"
    echo "\`\`\`"
  } > "$report_file"
  
  log "Report: $report_file"
  echo ""
  cat "$report_file"
}

main() {
  log "=== Dart HTTP Framework Benchmark ==="
  log "Mode: $MODE | Duration: $DURATION | Runs: $RUNS"
  echo ""
  
  if ! command -v wrk &>/dev/null; then
    err "wrk not found. Install: apt install wrk / brew install wrk"
    exit 1
  fi
  
  # Build AOT if needed
  if [[ "$MODE" == "aot" || "$MODE" == "both" ]]; then
    build_all_aot || exit 1
    echo ""
  fi
  
  # Run benchmarks
  if [[ "$MODE" == "aot" || "$MODE" == "both" ]]; then
    for name in "${SERVERS[@]}"; do
      run_benchmark "$name" "aot" || true
    done
  fi
  
  if [[ "$MODE" == "jit" || "$MODE" == "both" ]]; then
    for name in "${SERVERS[@]}"; do
      run_benchmark "$name" "jit" || true
    done
  fi
  
  generate_report
  log "=== Complete ==="
}

main
