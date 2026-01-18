#!/usr/bin/env bash
set -euo pipefail

URL=${URL:-http://127.0.0.1:8001/}
DURATION=${DURATION:-15s}
CONCURRENCY=${CONCURRENCY:-100}
THREADS=${THREADS:-4}
OUT_DIR=${OUT_DIR:-benchmarks/results}
TOOL=${TOOL:-}
WAIT_TIMEOUT=${WAIT_TIMEOUT:-0}
WAIT_INTERVAL=${WAIT_INTERVAL:-0.2}

mkdir -p "$OUT_DIR"

ts=$(date +%Y%m%d-%H%M%S)
name=$(echo "$URL" | sed 's#[/:]#_#g')
out="$OUT_DIR/${name}-${ts}.txt"

if [[ "$WAIT_TIMEOUT" != "0" ]]; then
  if command -v curl >/dev/null 2>&1; then
    deadline=$(( $(date +%s) + WAIT_TIMEOUT ))
    until curl -sf "$URL" >/dev/null 2>&1; do
      if [[ $(date +%s) -ge "$deadline" ]]; then
        echo "Timed out waiting for $URL" >&2
        exit 1
      fi
      sleep "$WAIT_INTERVAL"
    done
  fi
fi

if [[ -z "$TOOL" ]]; then
  if command -v wrk >/dev/null 2>&1; then
    TOOL=wrk
  elif command -v hey >/dev/null 2>&1; then
    TOOL=hey
  fi
fi

case "$TOOL" in
  wrk)
    wrk -t"$THREADS" -c"$CONCURRENCY" -d"$DURATION" --latency "$URL" | tee "$out"
    ;;
  hey)
    hey -z "$DURATION" -c "$CONCURRENCY" "$URL" | tee "$out"
    ;;
  *)
    echo "No benchmark tool found. Install wrk or hey, or set TOOL explicitly." >&2
    exit 1
    ;;
 esac

echo "Saved results to $out"
