import 'package:html_unescape/html_unescape.dart';
import 'package:routed/routed.dart';
import 'package:routed/src/support/form_builder.dart';

class TemplateHelpers {
  static Map<String, Function> getBuiltins() => {
        // Existing functions...
        'route': (String name, [dynamic params]) {
          if (params is Map) {
            return AppZone.route(name, params.cast());
          }
          return AppZone.route(name, null);
        },

        'config': (String key, [dynamic defaultValue]) =>
            AppZone.config.get(key, defaultValue),

        // Asset versioning/paths
        'asset': (String path) =>
            AppZone.config.get('app.asset_url', '') + path,

        // Environment checks
        'is_production': () => AppZone.config.get('app.env') == 'production',

        'is_development': () => AppZone.config.get('app.env') == 'development',

        // App info
        'app_name': () => AppZone.config.get('app.name', 'Routed App'),

        'app_version': () => AppZone.config.get('app.version', '1.0.0'),

        // Session access
        'session': (String key, [dynamic defaultValue]) =>
            AppZone.context.getSession(key),

        'has_session': (String key) => AppZone.context.hasSession(key),

        // Flash message handling
        'flash_messages': () {
          final messages =
              AppZone.context.getFlashMessages(withCategories: true);
          return messages;
        },

        // Session info
        'session_id': () => AppZone.context.sessionId,

        'session_created': () => AppZone.context.sessionCreatedAt,

        'old_input': (String key, [String defaultValue = '']) {
          final oldInput =
              AppZone.context.getSession('old') as Map<String, dynamic>? ?? {};
          return oldInput[key] ?? defaultValue;
        },

        'has_error': (String key) {
          final errors =
              AppZone.context.getSession('errors') as Map<String, dynamic>? ??
                  {};
          return errors.containsKey(key);
        },

        'get_error': (String key) {
          final errors =
              AppZone.context.getSession('errors') as Map<String, dynamic>? ??
                  {};
          return (errors[key] as List<dynamic>? ?? []).firstOrNull;
        },

        'get_errors': (String field) {
          final errors =
              AppZone.context.getSession('errors') as Map<String, dynamic>? ??
                  {};
          return errors[field] as List<dynamic>? ?? [];
        },

        'csrf_token': () => AppZone.context.sessionId,

        'csrf_field': () => '''
            <input type="hidden"
                   name="_csrf"
                   value="${AppZone.context.sessionId}">
          ''',

        'csrf_meta': () => '''
            <meta name="csrf-token"
                  content="${AppZone.context.sessionId}">
          ''',
        'form_text': (
          String name, {
          String label = '',
          String type = 'text',
          String placeholder = '',
          bool required = false,
          String value = '',
          int rows = 0,
        }) {
          final oldInput =
              AppZone.context.getSession('old') as Map<String, dynamic>? ?? {};
          final inputValue = oldInput[name] ?? value;

          return FormBuilder.textField(
            name,
            label: label,
            type: type,
            placeholder: placeholder,
            required: required,
            value: inputValue,
            rows: rows,
          );
        },

        'form_select': (
          String name,
          Map<String, String> options, {
          String label = '',
          String value = '',
          bool required = false,
        }) {
          final oldInput =
              AppZone.context.getSession('old') as Map<String, dynamic>? ?? {};
          final inputValue = oldInput[name] ?? value;
          return FormBuilder.select(
            name,
            options,
            label: label,
            value: inputValue,
            required: required,
          );
        },
        'helper_functions': () => FormBuilder.helperFunctions,
        'flash_messages_html': () =>
            AppZone.engineConfig.templateEngine!.renderContent('''
             ${FormBuilder.helperFunctions}
             ${FormBuilder.flashMessages()}
            '''),

        'safe': (String html) {
          return HtmlUnescape().convert(html);
        }
      };

  static List<String> scripts = [
    FormBuilder.flashMessages(),
    FormBuilder.helperFunctions,
  ];

  static Map<String, dynamic> routed_vars = {
    'csrf_token': () => AppZone.context
        .getSession(AppZone.engine.config.security.csrfCookieName),
    'csrf_field': () => '''
            <input type="hidden"
                   name="_csrf"
                   value="${AppZone.context.getSession(AppZone.engine.config.security.csrfCookieName)}">
          ''',
    'csrf_meta': () => '''
            <meta name="csrf-token"
                  content="${AppZone.context.getSession(AppZone.engine.config.security.csrfCookieName)}">  ''',
    'helper_functions': () => FormBuilder.helperFunctions,
    //   'flash_messages_html': () => FormBuilder.flashMessages(),
  };
}
