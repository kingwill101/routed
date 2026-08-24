import 'package:routed/routed.dart';

void main() {
  // Importing package:routed registers official providers.
  assert(
    officialProvidersRegistered,
    'The routed facade did not register its official providers.',
  );
}
