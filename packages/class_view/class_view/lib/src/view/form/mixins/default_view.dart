/// Default view mixin providing fallback template rendering
///
/// This mixin integrates with TemplateManager to provide intelligent fallbacks
/// when specific templates or renderers are not available.
mixin DefaultView {
  Future<String> renderDefault(Map<String, dynamic> context);
}
