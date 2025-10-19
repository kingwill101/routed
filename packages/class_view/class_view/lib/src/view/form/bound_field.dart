import 'dart:async';

import '../base_views/base_form_view.dart' show Form;
import '../view_engine.dart' show TemplateNotFoundException;
import 'fields/field.dart';
import 'fields/multi_value.dart';
import 'mixins/renderable_field_mixin.dart';
import 'mixins/renderable_mixin.dart';
import 'widgets/base_widget.dart';
import 'widgets/multi_value_widget.dart';
import 'widgets/text_input.dart';
import 'widgets/textarea.dart';

/// A field that is bound to a form instance.
class BoundField<T> with RenderableMixin, RenderableFieldMixin {
  /// The form this field is bound to.
  final Form form;

  /// The field instance.
  final Field<T> field;

  /// The name of the field.
  final String name;

  /// The HTML name for this field.
  late final String htmlName;

  /// The HTML ID for this field.
  late final String? autoId;

  /// The label for this field.
  late final String label;

  /// The help text for this field.
  late final String? helpText;

  /// The current value of the field.
  dynamic get value => form.data[name];

  /// Any validation errors for this field.
  List<String> get errors {
    final fieldErrors = form.errors[name];
    if (fieldErrors == null) return [];
    if (fieldErrors is List<String>) return fieldErrors;
    if (fieldErrors is String) return [fieldErrors];
    return [];
  }

  /// Whether this field has any errors.
  bool get hasErrors => errors.isNotEmpty;

  /// The label HTML for template rendering.
  String get labelHtml => renderLabel();

  BoundField(this.form, this.field, this.name) {
    htmlName = form.addPrefix(name);
    autoId = 'id_$name';
    label = field.label ?? _prettyName(name);
    helpText = field.helpText ?? '';
  }

  @override
  /// Render the field using a specific widget, with optional attributes and initial value handling.
  Future<String> asWidget({
    Widget? widget,
    Map<String, dynamic>? attrs,
    bool onlyInitial = false,
  }) async {
    // Use provided widget or field's default widget
    final widgetToUse = widget ?? field.widget;

    if (field.localize) {
      field.widget.isLocalized = true;
    }

    // Build combined attributes
    var combinedAttrs = <String, dynamic>{...?attrs};
    combinedAttrs = buildWidgetAttrs(field.widget.attrs, widgetToUse);
    // Add auto ID if not present
    if (autoId != null && !combinedAttrs.containsKey('id')) {
      combinedAttrs['id'] = onlyInitial ? '${autoId}_initial' : autoId;
    }

    // Handle initial value if needed
    final name = onlyInitial ? '${htmlName}_initial' : htmlName;
    final fieldValue = onlyInitial ? form.data['${htmlName}_initial'] : value;

    // Render the widget
    return widgetToUse.render(
      name,
      fieldValue,
      attrs: combinedAttrs,
      renderer: form.renderer,
    );
  }

  @override
  FutureOr<Map<String, dynamic>> getContext() async {
    return {
      'name': name,
      'html_name': htmlName,
      'auto_id': autoId,
      'label': label,
      'help_text': helpText,
      'value': value,
      'errors': errors,
      'has_errors': hasErrors,
      'label_html': renderLabel(),
      'help_text_html': renderHelpText(),
      'errors_html': await renderErrors(),
      'is_hidden': isHidden,
      'html': await toHtml(),
      'widget_html': await asWidget(),
      'template_name': templateName,
      'initial': initial(),
      'aria_describedby': ariaDescribedby,
      'widget_attrs': buildWidgetAttrs(field.widget.attrs, field.widget),
      'field': await toFieldMap(field),
    };
  }

  /// Return a string of HTML for representing this as an <input type="text">.
  Future<String> asText({Map<String, dynamic>? attrs}) async {
    return asWidget(widget: TextInput(), attrs: attrs);
  }

  /// Return a string of HTML for representing this as a <textarea>.
  Future<String> asTextarea({Map<String, dynamic>? attrs}) async {
    return asWidget(widget: Textarea(), attrs: attrs);
  }

  @override
  /// Return a string of HTML for representing this as an <input type="hidden">.
  Future<String> asHidden({
    Map<String, dynamic>? attrs,
    bool onlyInitial = false,
  }) async {
    return asWidget(
      widget: field.hiddenWidget,
      attrs: attrs,
      onlyInitial: onlyInitial,
    );
  }

  /// Returns the label's HTML representation.
  String renderLabel({String? labelText, Map<String, dynamic>? attrs}) {
    final text = labelText ?? label;
    final labelAttrs = {'for': autoId, ...?attrs};

    return '<label ${_renderAttrs(labelAttrs)}>$text</label>';
  }

  /// Returns the help text's HTML representation.
  String renderHelpText({Map<String, dynamic>? attrs}) {
    if (helpText == null || helpText!.isEmpty) return '';

    return '<span ${_renderAttrs(attrs)}>$helpText</span>';
  }

  /// Returns the error messages' HTML representation synchronously.
  /// This is a fallback that generates HTML directly without templates.
  String renderErrorsSync({Map<String, dynamic>? attrs, String? errorClass}) {
    if (!hasErrors) return '';

    final className = errorClass ?? attrs?['class'] ?? 'errorlist';
    final buffer = StringBuffer();
    buffer.writeln('<ul class="$className"');

    final fieldAutoId = autoId;
    if (fieldAutoId != null && fieldAutoId.isNotEmpty) {
      buffer.write(' id="${fieldAutoId}_error"');
    }

    buffer.writeln('>');
    for (final error in errors) {
      buffer.writeln('  <li>$error</li>');
    }
    buffer.writeln('</ul>');

    return buffer.toString();
  }

  /// Returns the error messages' HTML representation asynchronously.
  /// Attempts to use a Liquid template first, falls back to generated HTML.
  Future<String> renderErrors({
    Map<String, dynamic>? attrs,
    String? errorClass,
  }) async {
    if (!hasErrors) return '';

    final className = errorClass ?? attrs?['class'] ?? 'errorlist';

    // Try to render using template directly
    if (renderer != null) {
      try {
        final context = {
          'errors': errors,
          'error_class': className,
          'field_id': autoId,
        };
        return await renderer!.renderAsync('form/errors/list/ul.html', context);
      } on TemplateNotFoundException {
        // Fall through to sync rendering
      } catch (_) {
        // Ignore and fall back to sync rendering
      }
    }

    // Fall back to generating HTML directly
    return renderErrorsSync(attrs: attrs, errorClass: errorClass);
  }

  /// Helper method to render HTML attributes.
  String _renderAttrs(Map<String, dynamic>? attrs) {
    if (attrs == null || attrs.isEmpty) return '';

    return attrs.entries.map((e) => '${e.key}="${e.value}"').join(' ');
  }

  /// Converts a field name to a more readable format.
  String _prettyName(String name) {
    return name
        .replaceAll(RegExp(r'_+'), ' ')
        .trim()
        .split(' ')
        .map(
          (word) =>
              word.isEmpty ? '' : word[0].toUpperCase() + word.substring(1),
        )
        .join(' ');
  }

  /// Returns the complete field HTML representation including label, help text, and errors.
  @override
  String toString() {
    return '''
      ${renderLabel()}
      <!-- field render placeholder -->
      ${renderHelpText()}
      ${renderErrorsSync()}
    '''
        .trim();
  }

  bool get isHidden => field.widget.isHidden;

  /// Returns the complete field HTML representation including label, help text, and errors asynchronously.
  @override
  Future<String> toHtml() async {
    try {
      return await render();
    } catch (e) {
      // Fallback when renderer is not available
      return '''
        ${renderLabel()}
        ${await field.widget.render(htmlName, value)}
        ${renderHelpText()}
        ${await renderErrors()}
      '''
          .trim();
    }
  }

  @override
  Renderer? get renderer => form.renderer;

  @override
  String get templateName {
    return field.templateName ?? renderer?.fieldTemplateName ?? '';
  }

  dynamic initial() {
    return form.getInitialForField(field, name);
  }

  String? get ariaDescribedby {
    // Preserve aria-describedby set on the widget
    if (field.widget.attrs.containsKey('aria-describedby')) {
      return null;
    }

    final ariaDescribedby = <String>[];
    if (autoId != null && !isHidden) {
      if (helpText != null) {
        ariaDescribedby.add('${autoId}_helptext');
      }
      if (errors.isNotEmpty) {
        ariaDescribedby.add('${autoId}_error');
      }
    }
    return ariaDescribedby.isEmpty ? null : ariaDescribedby.join(' ');
  }

  Map<String, dynamic> buildWidgetAttrs(
    Map<String, dynamic> attrs,
    Widget? widgetToUse,
  ) {
    final widget = widgetToUse ?? field.widget;
    final newAttrs = Map<String, dynamic>.from(attrs);

    if (widget.useRequiredAttribute(initial()) &&
        field.required &&
        form.useRequiredAttribute) {
      if (field is MultiValueField &&
          !(field as MultiValueField).requireAllFields &&
          widget is MultiValueWidget) {
        for (var i = 0; i < (field as MultiValueField).fields.length; i++) {
          final subfield = (field as MultiValueField).fields[i];
          final subwidget = widget.widgets[i];
          if (subwidget.useRequiredAttribute(initial()) && subfield.required) {
            subwidget.attrs['required'] = 'required';
          }
        }
      } else {
        newAttrs['required'] = 'required';
      }
    }

    if (field.disabled) {
      newAttrs['disabled'] = 'disabled';
    }

    if (!widget.isHidden && errors.isNotEmpty) {
      newAttrs['aria-invalid'] = 'true';
    }

    if (!newAttrs.containsKey('aria-describedby')) {
      final ariaDescribedby = this.ariaDescribedby;
      if (ariaDescribedby != null) {
        newAttrs['aria-describedby'] = ariaDescribedby;
      }
    }

    // Merge any additional attributes from the widget
    if (widgetToUse != null) {
      for (final entry in widgetToUse.attrs.entries) {
        // Handle boolean attributes
        if (entry.value == 'true') {
          newAttrs[entry.key] = entry.key; // HTML5 boolean attribute style
        } else if (entry.value == 'false') {
          newAttrs.remove(entry.key); // Remove false boolean attributes
        } else {
          newAttrs[entry.key] = entry.value;
        }
      }
    }

    return newAttrs;
  }

  @override
  Future<String> render({
    String? templateName,
    Map<String, dynamic>? context,
  }) async {
    if (renderer != null) {
      try {
        return await super.render(templateName: templateName, context: context);
      } on TemplateNotFoundException {
        // Fall through to fallback rendering
      } catch (_) {
        // Fall through to fallback rendering
      }
    }

    // Fallback when renderer is not available or fails - include complete field rendering
    return '''
        ${renderLabel()}
        ${await field.widget.render(htmlName, value)}
        ${renderHelpText()}
        ${await renderErrors()}
      '''
        .trim();
  }
}
