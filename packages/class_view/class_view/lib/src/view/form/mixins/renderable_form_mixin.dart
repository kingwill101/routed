import 'default_view.dart';
import 'renderable_mixin.dart';

/// Mixin for renderable forms.
/// Provides form-specific rendering functionality.
mixin RenderableFormMixin on DefaultView, RenderableMixin {
  String templateNameP = 'form/form_p.html';

  String templateNameTable = 'form/form_table.html';

  String templateNameUl = 'form/form_ul.html';

  String templateNameDiv = 'form/form_div.html';

  @override
  Future<String> renderDefault(Map<String, dynamic> context) {
    throw UnimplementedError();
  }

  List<(Map<String, dynamic>, List<String>)> _normalizeFields(
    List<dynamic>? rawFields,
  ) {
    if (rawFields == null) {
      return <(Map<String, dynamic>, List<String>)>[];
    }

    return rawFields.map<(Map<String, dynamic>, List<String>)>((f) {
      // Handle {field: map, errors: list} format
      if (f is Map<String, dynamic>) {
        if (f.containsKey('field') && f.containsKey('errors')) {
          final fieldData = f['field'] as Map<String, dynamic>;
          final errors =
              (f['errors'] as List?)?.map((e) => e.toString()).toList() ??
              <String>[];
          return (fieldData, errors);
        }
        // Handle plain map format (legacy)
        final errors =
            (f['errors'] as List?)?.map((e) => e.toString()).toList() ??
            <String>[];
        return (f, errors);
      }

      // Handle [fieldMap, errors] format
      if (f is List) {
        if (f.length >= 2 && f[0] is Map<String, dynamic>) {
          final fieldData = f[0] as Map<String, dynamic>;
          final errors =
              (f[1] as List?)?.map((e) => e.toString()).toList() ?? <String>[];
          return (fieldData, errors);
        }
      }

      // Handle tuple format
      if (f is (dynamic, List)) {
        final fieldData = f.$1;
        if (fieldData is Map<String, dynamic>) {
          final errors = f.$2.map((e) => e.toString()).toList();
          return (fieldData, errors);
        }
      }

      throw StateError('Unexpected field context type: ${f.runtimeType}');
    }).toList();
  }

  /// Build a fallback paragraph layout
  Future<String> _buildParagraphLayout(Map<String, dynamic> context) async {
    final StringBuffer buffer = StringBuffer();
    final errors = (context['errors'] as List?)
        ?.map((e) => e.toString())
        .toList();
    final fields = _normalizeFields(context['fields'] as List<dynamic>?);
    final hiddenFields =
        context['hidden_fields'] as List<Map<String, dynamic>>?;

    if (errors?.isNotEmpty ?? false) {
      buffer.writeln(errors!.join('\n'));
    }

    if ((errors?.isNotEmpty ?? false) && fields.isEmpty) {
      buffer.writeln(
        '<p>${hiddenFields?.map((e) => e['html'] ?? '').join('\n') ?? ''}</p>',
      );
    }

    for (final (field, _) in fields) {
      buffer.write('<p>');
      buffer.writeln(field['label_html'] ?? '');
      buffer.writeln(field['widget_html'] ?? '');
      buffer.writeln(field['help_text_html'] ?? '');

      // Render errors using the errors_html key which has proper markup
      if (field['errors_html'] != null && field['errors_html'] != '') {
        buffer.writeln(field['errors_html']);
      }

      buffer.writeln('</p>');
    }

    if (fields.isEmpty && (errors?.isEmpty ?? true)) {
      buffer.writeln(
        hiddenFields?.map((e) => e['html'] ?? '').join('\n') ?? '',
      );
    }

    return buffer.toString();
  }

  /// Build a fallback div layout
  Future<String> _buildDivLayout(Map<String, dynamic> context) async {
    final StringBuffer buffer = StringBuffer();
    final errors = (context['errors'] as List?)
        ?.map((e) => e.toString())
        .toList();
    final fields = _normalizeFields(context['fields'] as List<dynamic>?);
    final hiddenFields =
        context['hidden_fields'] as List<Map<String, dynamic>>?;

    if (errors?.isNotEmpty ?? false) {
      buffer.writeln(errors!.join('\n'));
    }

    if ((errors?.isNotEmpty ?? false) && fields.isEmpty) {
      buffer.writeln(
        '<div>${hiddenFields?.map((e) => e['html'] ?? '').join('\n') ?? ''}</div>',
      );
    }

    for (final (field, _) in fields) {
      buffer.writeln('<div>');
      buffer.writeln(field['label_html'] ?? '');
      buffer.writeln(field['widget_html'] ?? '');
      buffer.writeln(field['help_text_html'] ?? '');

      // Render errors using the errors_html key which has proper markup
      if (field['errors_html'] != null && field['errors_html'] != '') {
        buffer.writeln(field['errors_html']);
      }

      buffer.writeln('</div>');
    }

    if (fields.isEmpty && (errors?.isEmpty ?? true)) {
      buffer.writeln(
        hiddenFields?.map((e) => e['html'] ?? '').join('\n') ?? '',
      );
    }

    return buffer.toString();
  }

  /// Build a fallback table layout
  Future<String> _buildTableLayout(Map<String, dynamic> context) async {
    final StringBuffer buffer = StringBuffer();
    final errors = (context['errors'] as List?)
        ?.map((e) => e.toString())
        .toList();
    final fields = _normalizeFields(context['fields'] as List<dynamic>?);
    final hiddenFields =
        context['hidden_fields'] as List<Map<String, dynamic>>?;

    if (errors?.isNotEmpty ?? false) {
      buffer.writeln('<tr><td colspan="2">');
      buffer.writeln(errors!.join('\n'));
      if (fields.isEmpty) {
        buffer.writeln(
          hiddenFields?.map((e) => e['html'] ?? '').join('\n') ?? '',
        );
      }
      buffer.writeln('</td></tr>');
    }

    for (final (field, _) in fields) {
      buffer.writeln('<tr>');
      buffer.write('<th>');
      buffer.writeln(field['label_html'] ?? '');
      buffer.writeln('</th>');

      buffer.writeln('<td>');
      buffer.writeln(field['widget_html'] ?? '');
      buffer.writeln(field['help_text_html'] ?? '');

      // Render errors using the errors_html key which has proper markup
      if (field['errors_html'] != null && field['errors_html'] != '') {
        buffer.writeln(field['errors_html']);
      }

      buffer.writeln('</td></tr>');
    }

    if (fields.isEmpty && (errors?.isEmpty ?? true)) {
      buffer.writeln(
        hiddenFields?.map((e) => e['html'] ?? '').join('\n') ?? '',
      );
    }

    return buffer.toString();
  }

  /// Build a fallback unordered list layout
  Future<String> _buildUlLayout(Map<String, dynamic> context) async {
    final StringBuffer buffer = StringBuffer();
    final errors = (context['errors'] as List?)
        ?.map((e) => e.toString())
        .toList();
    final fields = _normalizeFields(context['fields'] as List<dynamic>?);
    final hiddenFields =
        context['hidden_fields'] as List<Map<String, dynamic>>?;

    if (errors?.isNotEmpty ?? false) {
      buffer.writeln(errors!.join('\n'));
      if (fields.isEmpty) {
        buffer.writeln(
          '<li>${hiddenFields?.map((e) => e['html'] ?? '').join('\n') ?? ''}</li>',
        );
      }
    }

    for (final (field, _) in fields) {
      buffer.write('<li>');
      buffer.writeln(field['label_html'] ?? '');
      buffer.writeln(field['widget_html'] ?? '');
      buffer.writeln(field['help_text_html'] ?? '');

      // Render errors using the errors_html key which has proper markup
      if (field['errors_html'] != null && field['errors_html'] != '') {
        buffer.writeln(field['errors_html']);
      }

      buffer.writeln('</li>');
    }

    if (fields.isEmpty && (errors?.isEmpty ?? true)) {
      buffer.writeln(
        hiddenFields?.map((e) => e['html'] ?? '').join('\n') ?? '',
      );
    }

    return buffer.toString();
  }

  /// Render the form as paragraphs.
  Future<String> asP() async {
    try {
      return await render(templateName: templateNameP);
    } catch (e) {
      final context = await getContext();
      return _buildParagraphLayout(context);
    }
  }

  /// Render the form as table rows.
  /// Note: Does not include the surrounding <table> tag.
  Future<String> asTable() async {
    try {
      return await render(templateName: templateNameTable);
    } catch (e) {
      final context = await getContext();
      return _buildTableLayout(context);
    }
  }

  /// Render the form as an unordered list.
  /// Note: Does not include the surrounding <ul> tag.
  Future<String> asUl() async {
    try {
      return await render(templateName: templateNameUl);
    } catch (e) {
      final context = await getContext();
      return _buildUlLayout(context);
    }
  }

  /// Render the form as divs.
  Future<String> asDiv() async {
    try {
      final html = await render(templateName: templateNameDiv);
      print(
        'RenderableFormMixin.asDiv -> rendered using template $templateNameDiv',
      );
      return html;
    } catch (e) {
      final context = await getContext();
      return _buildDivLayout(context);
    }
  }

  /// Default rendering method.
  /// By default, renders the form as divs.
  @override
  Future<String> toHtml() => asDiv();
}
