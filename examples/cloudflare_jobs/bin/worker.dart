import 'package:routed_cloudflare_jobs_example/app.dart' as app;
import 'package:routed_node/cloudflare.dart';

void main() {
  defineCloudflareDurableObjects({
    'CloudflareScheduleStoreObject': app.CloudflareScheduleStoreObject.new,
  });
  defineCloudflareFetchFactoryWithEnvironmentAsync(app.createCloudflareEngine);
  defineCloudflareJobsQueueExportFactoryWithEnvironmentAsync(
    app.createCloudflareJobConsumer,
  );
  defineCloudflareSchedulerExportFactoryWithEnvironmentAsync(
    app.createCloudflareScheduler,
  );
}
