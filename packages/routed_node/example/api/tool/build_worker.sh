#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build

dart pub get
dart compile js bin/cloudflare.dart -o build/worker.dart.js -O2
cat > build/worker.js <<'BOOTSTRAP'
import './worker.dart.js';

export default {
  async fetch(request, env, ctx) {
    return await globalThis.__routed_fetch__(request, ctx, env);
  },
};
BOOTSTRAP

echo "Built build/worker.js"
