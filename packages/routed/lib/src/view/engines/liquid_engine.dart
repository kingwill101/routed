import 'dart:async';

import 'package:liquify/liquify.dart' as liquid;
import 'package:routed/src/render/html/liquid.dart';
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
  /// The [fileSystem] parameter specifies which file system implementation to use
  /// for loading templates. If not provided, the local file system is used.
  LiquidViewEngine({String? directory, liquid.Root? root})
    : _root = root ?? LiquidRoot() {
    if (directory != null) {
      if (_root is LiquidRoot) {
        (_root).fileSystem.currentDirectory = directory;
      } else if (_root is liquid.FileSystemRoot) {
        (_root).fileSystem.currentDirectory = directory;
      }
    }
  }

  @override
  Future<String> render(String name, [Map<String, dynamic>? data]) async {
    try {
      final parsed = liquid.Template.parse(name, data: data ?? {}, root: _root);
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
      final parsed = liquid.Template.fromFile(
        filePath,
        _root!,
        data: data ?? {},
      );
      return await parsed.renderAsync();
    } catch (e) {
      throw TemplateRenderException(filePath, e.toString());
    }
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
