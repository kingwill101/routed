import 'package:args/command_runner.dart';
import 'package:routed_cli/src/console/args/base_command.dart';
import 'package:routed_cli/src/console/args/commands/provider_metadata.dart';
import 'package:routed_core/routed_core.dart';

/// Lists providers that are available to be passed to an [Engine].
///
/// Provider activation is now code-owned: applications compose typed provider
/// instances in Dart instead of editing a YAML manifest.
class ProviderListCommand extends BaseCommand {
  /// Creates the provider-listing command.
  ProviderListCommand({super.logger, super.fileSystem});

  @override
  String get name => 'provider:list';

  @override
  String get description => 'Display available Routed providers.';

  @override
  String get category => 'Providers';

  @override
  Future<void> run() async {
    return guarded(() async {
      final rest = results?.rest ?? const <String>[];
      if (rest.length > 1) {
        throw UsageException('Specify at most one provider id.', usage);
      }
      final filterId = rest.isEmpty ? null : rest.first;
      if (filterId != null && !ProviderRegistry.instance.has(filterId)) {
        throw UsageException('Provider "$filterId" is not registered.', usage);
      }

      logger.info('Available Providers');
      for (final registration in ProviderRegistry.instance.registrations) {
        if (filterId != null && registration.id != filterId) {
          continue;
        }
        final provider = registration.factory();
        final description = registration.description.isNotEmpty
            ? registration.description
            : provider.describe();
        logger.info(
          '${registration.id.padRight(24)}'
          '${description.isEmpty ? '' : ' — $description'}',
        );
      }
    });
  }
}
