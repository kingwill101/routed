/// Localization demo showcasing Routed translation helpers.
library;

import 'package:routed/routed.dart';

/// Builds the example [Engine] with translation-enabled routes.
Future<Engine> createEngine() async {
  final engine = await Engine.create(
    options: [
      (engine) {
        final registry = _ensureResolverRegistry(engine);
        _registerPreviewResolver(registry);
      },
    ],
  );

  engine.get('/', (ctx) async {
    final payload = _localizedPayload(ctx, note: 'default resolver order');
    return ctx.json(payload);
  });

  engine.get('/preview', (ctx) async {
    final previewEnabled = ctx.query('preview');
    final payload = _localizedPayload(
      ctx,
      note: previewEnabled == null
          ? 'Add ?preview=true&preview_locale=es to trigger the preview resolver.'
          : 'Preview resolver engaged.',
    )..['resolver'] = 'preview';
    return ctx.json(payload);
  });

  engine.get('/header', (ctx) async {
    final header =
        ctx.request.headers.value(HttpHeaders.acceptLanguageHeader) ?? 'unset';
    final payload = _localizedPayload(
      ctx,
      note: 'Resolved from Accept-Language header: $header',
    )..['resolver'] = 'header';
    return ctx.json(payload);
  });

  return engine;
}

/// Builds the JSON payload shared by the demo routes.
Map<String, Object?> _localizedPayload(EngineContext ctx, {String? note}) {
  final rawName = ctx.query('name');
  final name = rawName == null || rawName.trim().isEmpty
      ? 'Routed'
      : rawName.trim();
  final notificationCount = int.tryParse(ctx.query('notifications') ?? '') ?? 0;

  final greeting = trans(
    'messages.greeting',
    replacements: {'name': name},
  ).toString();

  final notificationSummary = transChoice(
    'messages.notifications',
    notificationCount,
    replacements: {'count': notificationCount},
  );

  return {
    'locale': currentLocale(),
    'message': greeting,
    'notifications': notificationSummary,
    'cta_hint': trans('cta_hint').toString(),
    'legal_notice': trans('legal_notice').toString(),
    if (note != null) 'note': note,
  };
}

void _registerPreviewResolver(LocaleResolverRegistry registry) {
  registry.register('preview', (context) {
    return _PreviewLocaleResolver(
      flagParameter: context.option<String>('flag_parameter') ?? 'preview',
      localeParameter:
          context.option<String>('locale_parameter') ?? 'preview_locale',
    );
  });
}

LocaleResolverRegistry _ensureResolverRegistry(Engine engine) {
  if (engine.container.has<LocaleResolverRegistry>()) {
    return engine.container.get<LocaleResolverRegistry>();
  }
  final registry = LocaleResolverRegistry();
  engine.container.instance<LocaleResolverRegistry>(registry);
  return registry;
}

/// Resolves locales when both `preview` and `preview_locale` query params exist.
class _PreviewLocaleResolver extends LocaleResolver {
  _PreviewLocaleResolver({
    required this.flagParameter,
    required this.localeParameter,
  });

  final String flagParameter;
  final String localeParameter;

  @override
  String? resolve(LocaleResolutionContext context) {
    final flag = context.query(flagParameter);
    if (!_isTruthy(flag)) {
      return null;
    }
    final rawLocale = context.query(localeParameter);
    if (rawLocale == null) {
      return null;
    }
    final normalized = rawLocale.trim();
    if (normalized.isEmpty) {
      return null;
    }
    return normalized.replaceAll('_', '-');
  }

  bool _isTruthy(String? value) {
    if (value == null) {
      return false;
    }
    switch (value.trim().toLowerCase()) {
      case '1':
      case 'true':
      case 'yes':
      case 'on':
        return true;
    }
    return false;
  }
}
