import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart' show UsageException;
import 'package:file/file.dart' as fs;

import '../base_command.dart';

class StimulusInstallCommand extends BaseCommand {
  StimulusInstallCommand({super.logger, super.fileSystem}) {
    argParser
      ..addOption(
        'mode',
        help:
            'Installation mode. The default "cdn" scaffolds ES modules that import Stimulus from a CDN.',
        allowed: const ['cdn'],
        defaultsTo: 'cdn',
      )
      ..addFlag(
        'force',
        abbr: 'f',
        help: 'Overwrite existing files that would otherwise be skipped.',
        negatable: false,
      );
  }

  @override
  String get name => 'stimulus:install';

  @override
  String get description =>
      'Scaffold Stimulus application boilerplate and a sample controller.';

  @override
  String get invocation => 'routed stimulus:install [--force]';

  @override
  Future<void> run() => guarded(() async {
    final root = await findProjectRoot();
    if (root == null) {
      throw UsageException(
        'Unable to locate pubspec.yaml. Run this command from a routed project root.',
        usage,
      );
    }

    final mode = results?['mode'] as String? ?? 'cdn';
    final force = (results?['force'] as bool?) ?? false;

    switch (mode) {
      case 'cdn':
        await _installCdn(root, force: force);
        break;
      default:
        throw UsageException('Unsupported mode "$mode".', usage);
    }
  });

  Future<void> _installCdn(
    fs.Directory projectRoot, {
    required bool force,
  }) async {
    final relativeFiles = <String, String>{
      'public/js/controllers/application.js': _applicationJsCdn,
      'public/js/controllers/index.js': _indexJs,
      'public/js/controllers/hello_controller.js': _helloControllerJs,
      'public/js/stimulus.js': _entryJs,
    };

    final created = <String>[];
    final skipped = <String>[];

    for (final entry in relativeFiles.entries) {
      final file = fileSystem.file(joinPath([projectRoot.path, entry.key]));
      final exists = await file.exists();
      if (exists && !force) {
        skipped.add(entry.key);
        continue;
      }
      await writeTextFile(file, entry.value);
      created.add(entry.key);
    }

    if (created.isNotEmpty) {
      logger.info('Generated Stimulus scaffolding:');
      for (final path in created) {
        logger.info('  ✓ $path');
      }
    }

    if (skipped.isNotEmpty) {
      logger.warn('Skipped existing files (use --force to overwrite):');
      for (final path in skipped) {
        logger.warn('  • $path');
      }
    }

    logger.info('');
    logger.info('Next steps:');
    logger.info(
      '  1. Include <script type="module" src="/js/stimulus.js"></script> in your base HTML layout.',
    );
    logger.info(
      '  2. Attach controllers via data-controller attributes, e.g. data-controller="hello".',
    );
    logger.info(
      '  3. Edit public/js/controllers/index.js to register additional controllers as needed.',
    );
  }
}

const String _stimulusCdnUrl =
    'https://cdn.jsdelivr.net/npm/@hotwired/stimulus/+esm';

final String _applicationJsCdn =
    '''
import { Application } from '$_stimulusCdnUrl';

const application = Application.start();
application.debug = false;

// Expose the Stimulus application for debugging.
window.Stimulus = application;

export { application };
''';

final String _indexJs = '''
import { application } from './application.js';
import HelloController from './hello_controller.js';

// Register your controllers here.
application.register('hello', HelloController);

export { application };
''';

final String _helloControllerJs =
    '''
import { Controller } from '$_stimulusCdnUrl';

export default class extends Controller {
  static targets = ['name', 'output'];

  greet() {
    const name = this.nameTarget?.value?.trim() || 'friend';
    this.outputTarget.textContent = `Hello, \${name}!`;
  }
}
''';

final String _entryJs = '''
// Boot the Stimulus application and register controllers.
import './controllers/index.js';
''';
