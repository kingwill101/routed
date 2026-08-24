import 'package:routed_cloudflare_auth_example/app.dart';
import 'package:routed_node/cloudflare.dart';

void main() {
  defineCloudflareDurableObjects({
    'CloudflareRateLimitStoreObject': CloudflareRateLimitStoreObject.new,
  });
  defineCloudflareFetchFactoryWithEnvironmentAsync(createCloudflareEngine);
}
