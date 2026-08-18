import 'package:test/test.dart';
import 'package:routed_observability/routed_observability.dart';

void main() {
  test('exports available', () {
    registerRoutedObservabilityProviders();
    expect(true, isTrue);
  });
}
