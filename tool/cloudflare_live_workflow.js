import { WorkflowEntrypoint } from "cloudflare:workers";

export class RoutedLiveWorkflow extends WorkflowEntrypoint {
  async run(event, step) {
    return step.do("echo", async () => ({
      marker: event.payload?.marker ?? "missing",
    }));
  }
}

export default {
  async fetch() {
    return new Response("workflow-worker-ok");
  },
};
