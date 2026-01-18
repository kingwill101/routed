#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
SERVERS=(dart_io relic shelf serinus routed)

for name in "${SERVERS[@]}"; do
  dir="$ROOT_DIR/servers/$name"
  if [[ ! -d "$dir" ]]; then
    continue
  fi
  echo "Building $name..."
  (cd "$dir" && dart pub get && mkdir -p build && dart compile exe bin/server.dart -o build/server)
  echo "Built $name -> $dir/build/server"
 done
