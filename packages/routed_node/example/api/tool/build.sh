#!/usr/bin/env bash
# Compile the Node sample entry to JS (requires dart2js + JS-capable deps).
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
dart pub get
echo "Compiling bin/server.dart → build/server.js …"
dart compile js bin/server.dart -o build/server.js -O2
echo "Done. Start with: npm start"
