import 'package:routed_core/src/engine/config.dart' show EtagStrategy;
import 'package:routed_core/src/config/typed.dart';
import 'package:routed_core/src/provider/typed_provider.dart';

class RoutingConfig implements ValidatableConfiguration {
  const RoutingConfig({
    this.redirectTrailingSlash = true,
    this.handleMethodNotAllowed = true,
    this.defaultOptionsEnabled = true,
    this.etagStrategy = EtagStrategy.disabled,
  });

  final bool redirectTrailingSlash;
  final bool handleMethodNotAllowed;
  final bool defaultOptionsEnabled;
  final EtagStrategy etagStrategy;

  @override
  void validate(ConfigValidationContext context) {}
}
