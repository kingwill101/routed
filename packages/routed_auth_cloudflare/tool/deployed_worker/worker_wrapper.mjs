import './worker.dart.js';

export default {
  async fetch(request, env, ctx) {
    return await globalThis.__routed_fetch__(request, ctx, env);
  },
};
