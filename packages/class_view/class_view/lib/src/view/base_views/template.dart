import 'dart:async';
import 'dart:io' show HttpStatus;

import '../form/renderer.dart';
import '../mixins/context_mixin.dart';
import '../mixins/single_object_mixin.dart';
import '../mixins/template_response_mixin.dart';
import '../template_manager.dart';
import '../view_engine.dart';
import 'base.dart';

/// Generic TemplateView for rendering templates with context data
///
/// A clean template view that users can extend with minimal implementation.
/// Automatically handles template rendering with context data.
///
/// Example usage:
/// ```dart
/// class AboutView extends TemplateView {
///   @override
///   String get templateName => 'about.html';
///
///   @override
///   Future<Map<String, dynamic>> getExtraContext() async {
///     return {'company': 'Acme Corp'};
///   }
/// }
/// ```
abstract class TemplateView extends View
    with ContextMixin, TemplateResponseMixin {
  @override
  List<String> get allowedMethods => ['GET'];

  @override
  ViewEngine? get viewEngine => TemplateManager.engine;

  @override
  Renderer? get renderer => TemplateManager.renderer;

  @override
  Future<void> get() async {
    if (templateName == null) {
      throw Exception(
        'templateName must be specified in TemplateView subclasses',
      );
    }

    final contextData = await getContextData();
    await renderToResponse(contextData, templateName: templateName);
  }

  /// Get the context data for the template
  @override
  Future<Map<String, dynamic>> getContextData() async {
    return {};
  }

  @override
  Future<void> renderToResponse(
    Map<String, dynamic> templateContext, {
    String? templateName,
    int statusCode = HttpStatus.ok,
  }) async {
    // Get the template name to render
    final template = templateName ?? this.templateName;
    if (template == null) {
      throw Exception('No template name specified');
    }

    // Use the View's renderer if available, otherwise use viewEngine
    if (renderer != null) {
      final content = await renderer!.renderAsync(template, templateContext);
      setHeader('Content-Type', contentType);
      setStatusCode(statusCode);
      write(content);
    } else if (viewEngine != null) {
      final content = await viewEngine!.render(template, templateContext);
      setHeader('Content-Type', contentType);
      setStatusCode(statusCode);
      write(content);
    } else {
      throw Exception('No renderer or viewEngine configured');
    }
  }
}

/// Generic TemplateDetailView for rendering templates with a single object
///
/// Combines template rendering with single object retrieval for detail pages.
/// Users only need to implement getObject() and provide template/object names.
///
/// Example usage:
/// ```dart
/// class PostDetailView extends TemplateDetailView<Post> {
///   @override
///   String get templateName => 'posts/detail.html';
///
///   @override
///   Future<Post?> getObject() async {
///     final id = await getParam('id');
///     return await PostRepository.findById(id);
///   }
/// }
/// ```
abstract class TemplateDetailView<T> extends View
    with ContextMixin, SingleObjectMixin<T>, TemplateResponseMixin {
  @override
  List<String> get allowedMethods => ['GET'];

  @override
  Future<void> get() async {
    if (templateName == null) {
      throw Exception(
        'templateName must be specified in TemplateDetailView subclasses',
      );
    }

    final contextData = await getContextData();
    await renderToResponse(contextData, templateName: templateName);
  }
}
