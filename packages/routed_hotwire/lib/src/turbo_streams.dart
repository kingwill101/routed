/// Turbo Stream builders for HTML fragments and payload helpers.
enum TurboStreamAction {
  /// Inserts the template at the end of the target.
  append,

  /// Inserts the template at the beginning of the target.
  prepend,

  /// Replaces the target element.
  replace,

  /// Replaces the contents of the target element.
  update,

  /// Removes the target element.
  remove,

  /// Inserts the template immediately before the target.
  before,

  /// Inserts the template immediately after the target.
  after,

  /// Requests a refresh of the current page.
  refresh,
}

/// Builds a `<turbo-stream>` fragment for [action].
///
/// [target] selects one element by its identifier, while [targets] may use a
/// CSS selector. Actions that render content place [html] inside a template.
String turboStream({
  required TurboStreamAction action,
  String? target,
  String? targets,
  String? html,
  Map<String, String>? attributes,
}) {
  final buffer = StringBuffer()
    ..write('<turbo-stream action="')
    ..write(action.name)
    ..write('"');

  if (target != null && target.isNotEmpty) {
    buffer
      ..write(' target="')
      ..write(target)
      ..write('"');
  }

  if (targets != null && targets.isNotEmpty) {
    buffer
      ..write(' targets="')
      ..write(targets)
      ..write('"');
  }

  if (attributes != null && attributes.isNotEmpty) {
    attributes.forEach((key, value) {
      if (value.isEmpty) return;
      buffer
        ..write(' ')
        ..write(key)
        ..write('="')
        ..write(_escapeAttribute(value))
        ..write('"');
    });
  }

  buffer.write('>');

  final needsTemplate = switch (action) {
    TurboStreamAction.remove || TurboStreamAction.refresh => false,
    _ => true,
  };

  if (needsTemplate) {
    buffer.write('<template>');
    if (html != null) buffer.write(html);
    buffer.write('</template>');
  }

  buffer.write('</turbo-stream>');
  return buffer.toString();
}

/// Builds an append stream that inserts [html] into [target].
String turboStreamAppend({
  required String target,
  required String html,
  Map<String, String>? attributes,
}) => turboStream(
  action: TurboStreamAction.append,
  target: target,
  html: html,
  attributes: attributes,
);

/// Builds a prepend stream that inserts [html] into [target].
String turboStreamPrepend({
  required String target,
  required String html,
  Map<String, String>? attributes,
}) => turboStream(
  action: TurboStreamAction.prepend,
  target: target,
  html: html,
  attributes: attributes,
);

/// Builds a replace stream that replaces [target] with [html].
String turboStreamReplace({
  required String target,
  required String html,
  Map<String, String>? attributes,
}) => turboStream(
  action: TurboStreamAction.replace,
  target: target,
  html: html,
  attributes: attributes,
);

/// Builds an update stream that replaces the contents of [target] with [html].
String turboStreamUpdate({
  required String target,
  required String html,
  Map<String, String>? attributes,
}) => turboStream(
  action: TurboStreamAction.update,
  target: target,
  html: html,
  attributes: attributes,
);

/// Builds a remove stream for [target].
String turboStreamRemove({
  required String target,
  Map<String, String>? attributes,
}) => turboStream(
  action: TurboStreamAction.remove,
  target: target,
  attributes: attributes,
);

/// Builds a stream that inserts [html] immediately before [target].
String turboStreamBefore({
  required String target,
  required String html,
  Map<String, String>? attributes,
}) => turboStream(
  action: TurboStreamAction.before,
  target: target,
  html: html,
  attributes: attributes,
);

/// Builds a stream that inserts [html] immediately after [target].
String turboStreamAfter({
  required String target,
  required String html,
  Map<String, String>? attributes,
}) => turboStream(
  action: TurboStreamAction.after,
  target: target,
  html: html,
  attributes: attributes,
);

/// Builds a refresh stream, optionally carrying a Turbo [requestId].
String turboStreamRefresh({
  String? requestId,
  Map<String, String>? attributes,
}) {
  final merged = <String, String>{...?attributes};
  if (requestId != null && requestId.isNotEmpty) {
    merged.putIfAbsent('request-id', () => requestId);
  }
  return turboStream(
    action: TurboStreamAction.refresh,
    attributes: merged.isEmpty ? null : merged,
  );
}

/// Combines stream fragments into a single payload in iteration order.
String joinTurboStreams(Iterable<String> fragments) {
  final buffer = StringBuffer();
  fragments.forEach(buffer.write);
  return buffer.toString();
}

/// Normalizes body input for Turbo Stream responses.
///
/// Accepts a complete [String] or an [Iterable] of chunks. Throws an
/// [ArgumentError] for any other value.
String normalizeTurboStreamBody(dynamic body) {
  if (body is String) return body;
  if (body is Iterable) {
    final buffer = StringBuffer();
    body.forEach(buffer.write);
    return buffer.toString();
  }
  throw ArgumentError.value(
    body,
    'body',
    'Turbo stream responses accept String or Iterable<String> data.',
  );
}

String _escapeAttribute(String value) {
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}
