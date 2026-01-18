import 'dart:async';

import 'package:liquify/liquify.dart' as liquid;
import 'package:routed/src/render/html/liquid.dart';
import 'package:routed/src/context/context.dart';
import 'package:routed/src/view/view_engine.dart';

export 'package:routed/src/render/html/liquid.dart';

/// A view engine implementation that uses the Liquid template language.
class LiquidViewEngine implements ViewEngine {
  final liquid.Root? _root;

  @override
  List<String> get extensions => ['.liquid', '.html'];

  /// Creates a new [LiquidViewEngine] instance.
  ///
  /// The [root] parameter specifies the root object to use for rendering templates.
  /// If not provided, the default root object is used.
  ///
  /// The [directory] parameter scopes template resolution without mutating the
  /// underlying file system's current directory.
  LiquidViewEngine({String? directory, liquid.Root? root})
    : _root = _resolveRoot(root, directory);

  static liquid.Root _resolveRoot(liquid.Root? root, String? directory) {
    final resolvedRoot = root ?? LiquidRoot();
    final baseDirectory = directory?.trim();
    if (baseDirectory == null || baseDirectory.isEmpty) {
      return resolvedRoot;
    }
    if (resolvedRoot is LiquidRoot) {
      resolvedRoot.setBaseDirectory(baseDirectory);
      return resolvedRoot;
    }
    if (resolvedRoot is liquid.FileSystemRoot) {
      return liquid.FileSystemRoot(
        baseDirectory,
        fileSystem: resolvedRoot.fileSystem,
      );
    }
    return resolvedRoot;
  }

  @override
  Future<String> render(String name, [Map<String, dynamic>? data]) async {
    try {
      final scopedData = Map<String, dynamic>.from(data ?? {});
      final ctx = scopedData.remove(kViewEngineContextKey);
      final parsed = liquid.Template.parse(
        name,
        data: scopedData,
        root: _root,
        environmentSetup: _environmentSetup(ctx),
      );
      return await parsed.renderAsync();
    } catch (e) {
      throw TemplateRenderException(name, e.toString());
    }
  }

  @override
  Future<String> renderFile(
    String filePath, [
    Map<String, dynamic>? data,
  ]) async {
    try {
      final scopedData = Map<String, dynamic>.from(data ?? {});
      final ctx = scopedData.remove(kViewEngineContextKey);
      final parsed = liquid.Template.fromFile(
        filePath,
        _root!,
        data: scopedData,
        environmentSetup: _environmentSetup(ctx),
      );
      return await parsed.renderAsync();
    } catch (e) {
      throw TemplateRenderException(filePath, e.toString());
    }
  }

  void Function(liquid.Environment)? _environmentSetup(Object? ctx) {
    if (ctx is! EngineContext) {
      return null;
    }
    return (env) {
      env.registerLocalFilter('trans', (value, args, named) {
        final key =
            _coerceString(value) ??
            (args.isNotEmpty ? _coerceString(args.first) : null);
        if (key == null) return value;

        final replacements = Map<String, dynamic>.from(named);
        final locale =
            replacements.remove('locale') ?? replacements.remove('lang');

        final resolved = ctx.trans(
          key,
          replacements: replacements.isEmpty ? null : replacements,
          locale: locale?.toString(),
        );
        return (resolved ?? key).toString();
      });

      env.registerLocalFilter('trans_choice', (value, args, named) {
        final key =
            _coerceString(value) ??
            (args.isNotEmpty ? _coerceString(args.first) : null);
        if (key == null) return value;

        final replacements = Map<String, dynamic>.from(named);
        final locale =
            replacements.remove('locale') ?? replacements.remove('lang');
        final dynamic countSource =
            replacements.remove('count') ??
            (args.length > 1 ? args[1] : (args.isNotEmpty ? args.last : null));
        final num? count = _asNum(countSource);
        if (count == null) {
          final resolved = ctx.trans(
            key,
            replacements: replacements.isEmpty ? null : replacements,
            locale: locale?.toString(),
          );
          return (resolved ?? key).toString();
        }

        return ctx
            .transChoice(
              key,
              count,
              replacements: replacements.isEmpty ? null : replacements,
              locale: locale?.toString(),
            )
            .toString();
      });

      env.registerLocalFilter('transChoice', (value, args, named) {
        return env.getFilter('trans_choice')!(value, args, named);
      });
    };
  }

  String? _coerceString(dynamic input) {
    if (input == null) return null;
    if (input is String) return input;
    return input.toString();
  }

  num? _asNum(dynamic input) {
    if (input == null) return null;
    if (input is num) return input;
    if (input is String) {
      return num.tryParse(input);
    }
    return null;
  }
}

/// Exception thrown when there is an error rendering a template.
class TemplateRenderException implements Exception {
  final String templateName;
  final String error;

  TemplateRenderException(this.templateName, this.error);

  @override
  String toString() => 'Error rendering template $templateName: $error';
}
