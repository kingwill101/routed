import 'dart:io';

import 'package:hooks/hooks.dart';
import 'package:native_prebuilt/hooks.dart';

Future<void> main(List<String> args) async {
  await build(args, (input, output) async {
    final isWorkspace = _isWorkspaceCheckout(input.packageRoot);
    final detected = detect(Directory.fromUri(input.packageRoot));
    if (detected == null) {
      throw StateError(
        'Could not discover server_native native_prebuilt.yaml from '
        '${input.packageRoot}.',
      );
    }

    // The manifest owns the recipes and release metadata. The local source
    // override keeps workspace builds on the checked-out Rust source instead
    // of cloning the release tag declared for published-package fallback.
    final project = detected.copyWith(
      sources: const [
        LocalSource(paths: <String>['.']),
      ],
      prebuiltPolicy: isWorkspace
          ? PrebuiltPolicy.forceSourceBuild
          : PrebuiltPolicy.preferPrebuilt,
    );

    await NativeProjectBuilder(
      project: project,
      resolvers: isWorkspace ? const <PrebuiltResolver>[] : null,
    ).run(input: input, output: output, logger: null);
  });
}

bool _isWorkspaceCheckout(Uri packageRoot) {
  var directory = Directory.fromUri(packageRoot).absolute;
  while (true) {
    final hasPackages = Directory('${directory.path}/packages').existsSync();
    if (File('${directory.path}/pubspec.yaml').existsSync() && hasPackages) {
      return true;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) return false;
    directory = parent;
  }
}
