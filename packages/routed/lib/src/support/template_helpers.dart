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
            AppZone.context.getSession<dynamic>(key) ?? defaultValue,

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
              AppZone.context.getSession<Map<String, dynamic>>('old') ?? {};
          return oldInput[key] ?? defaultValue;
        },

        'has_error': (String key) {
          final errors =
              AppZone.context.getSession<Map<String, dynamic>>('errors') ?? {};
          return errors.containsKey(key);
        },

        'get_error': (String key) {
          final errors =
              AppZone.context.getSession<Map<String, dynamic>>('errors') ?? {};
          return (errors[key] as List<dynamic>? ?? []).firstOrNull;
        },

        'get_errors': (String field) {
          final errors =
              AppZone.context.getSession<Map<String, dynamic>>('errors') ?? {};
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
              AppZone.context.getSession<Map<String, dynamic>>('old') ?? {};
          String inputValue;
          final oldValue = oldInput[name];
          if (oldValue != null) {
            inputValue = oldValue is String ? oldValue : oldValue.toString();
          } else {
            inputValue = value;
          }

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
              AppZone.context.getSession<Map<String, dynamic>>('old') ?? {};
          String inputValue;
          final oldValue = oldInput[name];
          if (oldValue != null) {
            inputValue = oldValue is String ? oldValue : oldValue.toString();
          } else {
            inputValue = value;
          }
          
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

  static Map<String, dynamic> routedVars = {
    'csrf_token': () {
      final token = AppZone.context.getSession<String>(AppZone.engine.config.security.csrfCookieName);
      if (token is String) {
        return token;
      }
      return '';
    },
    'csrf_field': () {
      final token = AppZone.context.getSession<String>(AppZone.engine.config.security.csrfCookieName);
      final tokenStr = token is String ? token : '';
      return '''
            <input type="hidden"
                   name="_csrf"
                   value="$tokenStr">
          ''';
    },
    'csrf_meta': () {
      final token = AppZone.context.getSession<String>(AppZone.engine.config.security.csrfCookieName);
      final tokenStr = token is String ? token : '';
      return '''
            <meta name="csrf-token"
                  content="$tokenStr">  ''';
    },
    'helper_functions': () => FormBuilder.helperFunctions,
  };
}
