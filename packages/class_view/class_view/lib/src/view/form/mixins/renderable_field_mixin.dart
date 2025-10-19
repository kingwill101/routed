import 'renderable_mixin.dart';

/// Mixin for renderable form fields.
/// Provides field-specific rendering functionality.
mixin RenderableFieldMixin on RenderableMixin {
  /// Render the field as a complete field group.
  Future<String> asFieldGroup() async {
    return render();
  }

  /// Render the field as a hidden input.
  Future<String> asHidden({
    Map<String, dynamic>? attrs,
    bool onlyInitial = false,
  }) async {
    throw UnimplementedError(
      "Subclasses of RenderableFieldMixin must provide an as_hidden() method.",
    );
  }

  /// Render the field as a widget.
  Future<String> asWidget() async {
    throw UnimplementedError(
      "Subclasses of RenderableFieldMixin must provide an as_widget() method.",
    );
  }

  /// Render this field as an HTML widget.
  @override
  Future<String> toHtml() async {
    if (showHiddenInitial) {
      return '${await asWidget()}${await asHidden(onlyInitial: true)}';
    }
    return asWidget();
  }

  /// Whether to show a hidden initial value.
  bool get showHiddenInitial => false;
}
