import '../mixins/default_view.dart';
import '../renderer.dart';

export '../renderer.dart';

/// Base class for all form widgets.
///
/// A widget is responsible for rendering an HTML input element and extracting
/// data from a GET/POST dictionary that corresponds to the widget.
///
/// This class provides the basic attributes and methods required for rendering
/// and handling form widgets. Subclasses can override methods to customize
/// behavior.
abstract class Widget {
  /// HTML attributes to be set on the rendered widget.
  final Map<String, dynamic> attrs;

  /// Whether the widget is required.
  bool isRequired = false;

  /// Whether the widget should be localized.
  bool isLocalized = false;

  bool needsMultipartForm = false;

  /// Template name for rendering the widget (optional).
  final String? templateName;

  /// Whether this widget supports microseconds.
  bool supportsMicroseconds = true;

  /// Whether this widget should be grouped in a `<fieldset>` with a `<legend>`.
  bool useFieldset = false;

  Widget({Map<String, dynamic>? attrs, this.templateName})
    : attrs = attrs != null ? Map.from(attrs) : {};

  /// Returns a dictionary of values to use when rendering the widget template.
  ///
  /// By default, the dictionary contains a single key, `'widget'`, which is a
  /// dictionary representation of the widget containing the following keys:
  /// - `'name'`: The name of the field.
  /// - `'is_hidden'`: Whether or not this widget is hidden.
  /// - `'required'`: Whether or not the field for this widget is required.
  /// - `'value'`: The value as returned by `formatValue()`.
  /// - `'attrs'`: HTML attributes to be set on the rendered widget.
  /// - `'template_name'`: The value of `self.templateName`.
  Map<String, dynamic> getContext(
    String name,
    dynamic value, [
    Map<String, dynamic>? extraAttrs,
  ]) {
    return {
      'widget': {
        'name': name,
        'is_hidden': isHidden,
        'required': isRequired,
        'value': formatValue(value),
        'attrs': buildAttrs(attrs, extraAttrs),
        'template_name': templateName,
      },
    };
  }

  /// Cleans and returns a value for use in the widget template.
  ///
  /// Subclasses should override this method to handle specific formatting
  /// requirements.
  dynamic formatValue(dynamic value) {
    if (value == '' || value == null) {
      return null;
    }
    return value.toString();
  }

  /// Returns the HTML ID attribute of this widget for use by a `<label>`.
  ///
  /// This method should be overridden by subclasses to handle cases where
  /// widgets have multiple HTML elements and IDs.
  String idForLabel(String? id) {
    return id ?? '';
  }

  /// Renders the widget using a specified template or default rendering method.
  ///
  /// Attempts to render the widget with the given name and value using the specified
  /// template or a default rendering method. If no template is available and no
  /// default render method exists, throws a [RenderException].
  ///
  /// [name] The name of the widget to render.
  /// [value] The value to be rendered in the widget.
  /// [attrs] Optional HTML attributes to apply to the widget.
  /// [renderer] Optional renderer for template rendering.
  /// [templateName] Optional template name to override the default.
  ///
  /// Returns a [Future] containing the rendered widget as a [String].
  ///
  /// Throws a [RenderException] if rendering fails and no default method is available.
  Future<String> render(
    String name,
    dynamic value, {
    Map<String, dynamic>? attrs,
    Renderer? renderer,
    String? templateName,
  }) async {
    final context = getContext(name, value, attrs);

    final template = templateName ?? this.templateName;

    if (template == null) {
      if (this is DefaultView) {
        return (this as DefaultView).renderDefault(context);
      }
      throw RenderException(
        'No template name provided and no default render method available.',
      );
    }
    try {
      final content = await renderer?.renderAsync(template, context);
      if (content == null || content.isEmpty) {
        throw RenderException('No content returned from renderer.');
      }
      return content;
    } catch (e) {
      if (this is DefaultView) {
        return (this as DefaultView).renderDefault(context);
      }
      if (e is RenderException) {
        rethrow;
      }
      throw RenderException(e.toString());
    }
  }

  /// Builds an attribute dictionary by merging base attributes and extra attributes.
  Map<String, dynamic> buildAttrs(
    Map<String, dynamic> baseAttrs,
    Map<String, dynamic>? extraAttrs,
  ) {
    final attrs = Map<String, dynamic>.from(baseAttrs);

    if (extraAttrs != null) {
      for (final entry in extraAttrs.entries) {
        // Handle boolean attributes
        if (entry.value == 'true') {
          attrs[entry.key] = entry.key; // HTML5 boolean attribute style
        } else if (entry.value == 'false') {
          attrs.remove(entry.key); // Remove false boolean attributes
        } else {
          attrs[entry.key] = entry.value;
        }
      }
    }

    return attrs;
  }

  /// Extracts the value of this widget from form data.
  ///
  /// This method should be overridden by subclasses to handle specific
  /// extraction logic.
  dynamic valueFromData(Map<String, dynamic> data, String name) {
    return data[name];
  }

  /// Determines whether the value for this widget is omitted from the data.
  ///
  /// Subclasses can override this method to handle special cases where
  /// the widget's value might not appear in the data.
  bool valueOmittedFromData(Map<String, dynamic> data, String name) {
    return !data.containsKey(name);
  }

  /// Whether this widget is hidden.
  ///
  /// Subclasses can override this property to indicate if the widget is hidden.
  bool get isHidden => false;

  /// Determines whether the widget can be rendered with the `required` HTML attribute.
  ///
  /// By default, returns `false` for hidden widgets and `true` otherwise.
  /// Subclasses can override this method to handle specific cases.
  bool useRequiredAttribute(dynamic initial) {
    return !isHidden;
  }
}
