import 'package:routed_observability/routed_observability.dart';
import 'package:test/test.dart';

void main() {
  test('exports available', () {
    registerRoutedObservabilityProviders();
    expect(true, isTrue);
  });
}
