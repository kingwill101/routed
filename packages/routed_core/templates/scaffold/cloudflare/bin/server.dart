import 'package:routed_node/cloudflare.dart';
import 'package:{{{routed:packageName}}}/app.dart' as app;

void main() {
  defineCloudflareFetchFactoryWithEnvironmentAsync(
    app.createCloudflareEngine,
  );
}
