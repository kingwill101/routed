import { WorkerEntrypoint } from "cloudflare:workers";

export default class RoutedLiveService extends WorkerEntrypoint {
  async fetch() {
    return new Response("service-fetch-ok");
  }

  async add(a, b) {
    return Number(a) + Number(b);
  }

  async constant() {
    return 5;
  }

  async greet(name) {
    return `hello ${name}`;
  }
}
