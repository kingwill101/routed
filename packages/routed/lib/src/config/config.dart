import 'package:routed/src/contracts/config/config.dart';
import 'package:routed_core/routed_core.dart'
    as core_config
    show ConfigImpl, ScopedConfig;

class ConfigImpl extends core_config.ConfigImpl implements Config {
  ConfigImpl([super.items]);
}

/// A request-scoped config wrapper that overlays mutable values on top of
/// a shared parent config without cloning the full tree.
class ScopedConfig extends core_config.ScopedConfig implements Config {
  ScopedConfig(super.parent);
}
