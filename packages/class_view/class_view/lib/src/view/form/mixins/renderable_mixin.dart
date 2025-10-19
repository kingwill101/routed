import 'dart:async';

import '../fields/field.dart';
import '../widgets/base_widget.dart';

/// Base mixin for renderable objects.
/// Provides common rendering functionality.
mixin RenderableMixin {
  /// Get the renderer instance
  Renderer? get renderer;

  /// Get the template name for this renderable object.
  String get templateName;

  /// Get the context data for rendering.
  FutureOr<Map<String, dynamic>> getContext();

  /// Render the object using the given template and context.
  /// If no template is provided, uses the default template.
  /// If no context is provided, uses the default context.
  Future<String> render({
    String? templateName,
    Map<String, dynamic>? context,
  }) async {
    if (renderer == null) {
      throw Exception('No renderer available');
    }
    final template = templateName ?? this.templateName;
    final ctx = context ?? await getContext();
    return renderer?.renderAsync(template, ctx) ?? '';
  }

  /// String representation of the object.
  /// By default, renders the object using the default template.
  @override
  String toString() => render().toString();

  /// HTML representation of the object.
  /// By default, renders the object using the default template.
  Future<String> toHtml() => render();

  /// Converts a Field instance to a map of its properties.
  Future<Map<String, dynamic>> toFieldMap(Field<dynamic> field) async {
    return {
      'name': field.name,
      'required': field.required,
      'label': field.label,
      'initial': field.initial,
      'help_text': field.helpText,
      'show_hidden_initial': field.showHiddenInitial,
      'localize': field.localize,
      'disabled': field.disabled,
      'label_suffix': field.labelSuffix,
      'template_name': field.templateName,
      'error_messages': field.errorMessages,
      'widget': toWidgetMap(field.widget),
      'hidden_widget': toWidgetMap(field.hiddenWidget),
    };
  }

  /// Converts a Widget instance to a map of its properties.
  Map<String, dynamic> toWidgetMap(Widget widget) {
    return {
      'attrs': widget.attrs,
      'is_required': widget.isRequired,
      'is_localized': widget.isLocalized,
      'needs_multipart_form': widget.needsMultipartForm,
      'template_name': widget.templateName,
      'supports_microseconds': widget.supportsMicroseconds,
      'use_fieldset': widget.useFieldset,
      'is_hidden': widget.isHidden,
    };
  }
}
