import './build/worker.dart.js';

const __routedDurableObjects =
    globalThis.__routed_durable_objects__ ?? {};

export class CloudflareRateLimitStoreObject {
  constructor(state, env) {
    const factory = __routedDurableObjects.CloudflareRateLimitStoreObject;
    if (!factory) {
      throw new Error('CloudflareRateLimitStoreObject is not registered.');
    }
    this.delegate = factory(state, env);
  }

  fetch(request) {
    return this.delegate.fetch(request);
  }
}

export default {
  async fetch(request, env, ctx) {
    return await globalThis.__routed_fetch__(request, ctx, env);
  },
};
