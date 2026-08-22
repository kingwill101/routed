import 'dart:convert';

import 'package:routed_core/routed_core.dart';

import '../binding/convert/xml.dart';
import 'binding.dart';

/// Binds an XML object body into a map or [Bindable] instance.
///
/// The decoded value preserves the document root as its first map key, using
/// the same representation as [XmlMapDecoder]. Attributes are stored under
/// `@attributes` and text content under `#text`.
class XmlBinding extends Binding {
  @override
  String get name => 'xml';

  @override
  MimeType get mimeType => MimeType.xml;

  Future<Map<String, dynamic>> _decodedBody(EngineContext context) async {
    final body = utf8.decode(await context.request.bytes);
    if (body.trim().isEmpty) {
      return <String, dynamic>{};
    }

    try {
      return const XmlMapDecoder().convert(body);
    } on Object catch (error) {
      throw XmlParseError(details: error.toString());
    }
  }

  @override
  Future<T> bind<T>(EngineContext context, T instance) async {
    final decoded = await _decodedBody(context);
    bindBody(decoded, instance);
    return instance;
  }

  /// Applies a decoded XML document to a map or [Bindable] instance.
  void bindBody(Map<String, dynamic> decoded, dynamic instance) {
    if (instance is Map) {
      instance.addAll(decoded);
    } else if (instance is Bindable) {
      instance.bind(decoded);
    }
  }
}

/// A malformed XML request-body error.
class XmlParseError extends EngineError {
  /// Creates an XML parse error with optional parser details.
  XmlParseError({this.details = ''}) : super(message: 'Invalid XML payload.');

  /// Parser details retained for internal diagnostics.
  final String details;

  @override
  int? get code => 400;

  @override
  String get message => details.isEmpty
      ? 'Invalid XML payload.'
      : 'Invalid XML payload: $details';

  @override
  Map<String, dynamic> toJson() => {
    'error': 'invalid_xml',
    'message': message,
    'code': code,
  };
}
