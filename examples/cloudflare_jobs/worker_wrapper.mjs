import './build/worker.dart.js';

const __routedDurableObjects = globalThis.__routed_durable_objects__ ?? {};

export class CloudflareScheduleStoreObject {
  constructor(state, env) {
    const factory = __routedDurableObjects.CloudflareScheduleStoreObject;
    if (!factory) {
      throw new Error('CloudflareScheduleStoreObject is not registered.');
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

  async queue(batch, env, ctx) {
    const handler = globalThis.__routed_queue__;
    if (typeof handler !== 'function') {
      throw new Error('Routed Queue handler is not registered.');
    }
    return await handler(batch, env, ctx);
  },

  async scheduled(controller, env, ctx) {
    const handler = globalThis.__routed_scheduled__;
    if (typeof handler !== 'function') {
      throw new Error('Routed scheduled handler is not registered.');
    }
    return await handler(controller, env, ctx);
  },
};
