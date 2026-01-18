#!/usr/bin/env bash
set -euo pipefail

NAME=${1:-}
PORT=${2:-}
if [[ -z "$NAME" ]]; then
  echo "Usage: $0 <dart_io|relic|shelf|serinus|routed> [port]" >&2
  exit 1
fi

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
DIR="$ROOT_DIR/servers/$NAME"
if [[ ! -d "$DIR" ]]; then
  echo "Unknown server: $NAME" >&2
  exit 1
fi

BIN="$DIR/build/server"
if [[ ! -x "$BIN" ]]; then
  echo "Missing binary: $BIN" >&2
  echo "Run benchmarks/scripts/dart_build.sh first." >&2
  exit 1
fi

PORT_VALUE=${PORT:-}
if [[ -z "$PORT_VALUE" ]]; then
  case "$NAME" in
    dart_io) PORT_VALUE=8001 ;;
    relic) PORT_VALUE=8007 ;;
    shelf) PORT_VALUE=8002 ;;
    serinus) PORT_VALUE=8003 ;;
    routed) PORT_VALUE=8006 ;;
    *) PORT_VALUE=8000 ;;
  esac
fi

PORT="$PORT_VALUE" "$BIN"
