/// Turbo Stream builders for HTML fragments and payload helpers.
enum TurboStreamAction {
  append,
  prepend,
  replace,
  update,
  remove,
  before,
  after,
  refresh,
}

/// Build a `<turbo-stream>` fragment.
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

String turboStreamRemove({
  required String target,
  Map<String, String>? attributes,
}) => turboStream(
  action: TurboStreamAction.remove,
  target: target,
  attributes: attributes,
);

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

/// Combine stream fragments into a single payload.
String joinTurboStreams(Iterable<String> fragments) {
  final buffer = StringBuffer();
  for (final fragment in fragments) {
    buffer.write(fragment);
  }
  return buffer.toString();
}

/// Normalise body input for Turbo Stream responses.
String normalizeTurboStreamBody(dynamic body) {
  if (body is String) return body;
  if (body is Iterable) {
    final buffer = StringBuffer();
    for (final chunk in body) {
      buffer.write(chunk);
    }
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
