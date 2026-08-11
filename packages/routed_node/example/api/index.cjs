// Node bootstrap for the compiled Dart sample.
//
// 1. Sets globalThis.self for dart2js
// 2. Exposes require as globalThis.__routedRequire (and require) so Dart interop
//    can load node:http when process.getBuiltinModule is unavailable
// 3. Loads build/server.js from `npm run build`
'use strict';

globalThis.self ??= globalThis;

// Make CommonJS require visible to dart2js-compiled code.
try {
  // eslint-disable-next-line no-undef
  if (typeof require === 'function') {
    globalThis.__routedRequire = require;
    globalThis.require ??= require;
  }
} catch (_) {
  // ignore
}

try {
  require('./build/server.js');
} catch (err) {
  if (err && err.code === 'MODULE_NOT_FOUND') {
    console.error(
      'Missing build/server.js. Run: npm run build\n' +
        'On the Dart VM (no Node listen yet), try: npm run smoke',
    );
    process.exit(1);
  }
  throw err;
}
