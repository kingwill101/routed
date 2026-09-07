import 'package:routed_architecture_cloudflare_d1/app.dart';
import 'package:routed_node/cloudflare.dart';

void main() {
  defineCloudflareFetchFactoryWithEnvironmentAsync(createEngine);
}
