import 'package:html/dom.dart';

class FormBuilder {
  static Element _createBaseElement(
    String name, {
    String label = '',
    bool required = false,
  }) {
    var div = Element.tag('div');
    div.classes.add('form-group');

    if (label.isNotEmpty) {
      var labelElement = Element.tag('label')
        ..classes
            .addAll(['block', 'text-gray-700', 'text-sm', 'font-bold', 'mb-2'])
        ..text = label;
      if (required) {
        labelElement.append(Element.tag('span')
          ..classes.add('text-red-500')
          ..text = ' *');
      }
      div.append(labelElement);
    }

    return div;
  }

  static String flashMessages() {
    var container = Element.tag('div')
      ..attributes['id'] = 'flash-messages'
      ..classes.addAll(['space-y-4', 'mb-6']);

    var template = '''
        {% set messages = flash_messages() %}
        {% if messages %}
          {% for category, message in messages %}
            <div class="rounded-lg p-4 border {{ get_alert_class(category) }} flex items-center justify-between"
                 role="alert"
                 data-auto-dismiss="5000">
              <div class="flex items-center">
                {{ get_alert_icon(category) | safe }}
                <span class="text-sm">{{ message }}</span>
              </div>
              <button type="button"
                      class="text-gray-400 hover:text-gray-600"
                      onclick="this.parentElement.remove()">
                <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
                  <path fill-rule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z"></path>
                </svg>
              </button>
            </div>
          {% endfor %}
        {% endif %}
      ''';

    container.innerHtml = template;
    return container.outerHtml;
  }

  static String textField(
    String name, {
    String label = '',
    String type = 'text',
    String placeholder = '',
    bool required = false,
    int rows = 0,
    String value = '',
  }) {
    var div = _createBaseElement(name, label: label, required: required);

    var inputClasses = [
      'w-full',
      'px-3',
      'py-2',
      'border',
      'rounded-lg',
      'focus:outline-none',
      'focus:ring-2',
      'focus:ring-blue-500',
      'disabled:bg-gray-100',
      'disabled:cursor-not-allowed'
    ];

    if (rows > 0) {
      var textarea = Element.tag('textarea')
        ..attributes['name'] = name
        ..attributes['rows'] = rows.toString()
        ..attributes['placeholder'] = placeholder
        ..classes.addAll(inputClasses);

      textarea.innerHtml = "{{ old_input('$name') }}";
      div.append(textarea);
    } else {
      var input = Element.tag('input')
        ..attributes['type'] = type
        ..attributes['name'] = name
        ..attributes['placeholder'] = placeholder
        ..classes.addAll(inputClasses);

      if (required) input.attributes['required'] = '';

      input.attributes['value'] = "{{ old_input('$name') }}";
      div.append(input);
    }

    var errorDiv = Element.tag('div')
      ..innerHtml = '''
          {% if has_error('$name') %}
            <p class="text-red-500 text-xs mt-1">{{ get_error('$name') }}</p>
          {% endif %}
        ''';
    div.append(errorDiv);

    return div.outerHtml;
  }

  static String select(
    String name,
    Map<String, String> options, {
    String label = '',
    bool required = false,
    String value = '',
  }) {
    var div = _createBaseElement(name, label: label, required: required);

    var select = Element.tag('select')
      ..attributes['name'] = name
      ..classes.addAll([
        'w-full',
        'px-3',
        'py-2',
        'border',
        'rounded-lg',
        'focus:outline-none',
        'focus:ring-2',
        'focus:ring-blue-500',
        'disabled:bg-gray-100',
        'disabled:cursor-not-allowed'
      ]);

    if (required) select.attributes['required'] = '';

    // Add default empty option
    var defaultOption = Element.tag('option')
      ..attributes['value'] = ''
      ..text = 'Select an option';
    select.append(defaultOption);

    options.forEach((optionValue, text) {
      var option = Element.tag('option')
        ..attributes['value'] = optionValue
        ..innerHtml = text;
      if (value == optionValue) {
        option.attributes['selected'] = 'selected';
      }
      select.append(option);
    });

    div.append(select);

    var errorDiv = Element.tag('div')
      ..innerHtml = '''
          {% if has_error('$name') %}
            <p class="text-red-500 text-xs mt-1">{{ get_error('$name') }}</p>
          {% endif %}
        ''';
    div.append(errorDiv);

    return div.outerHtml;
  }

  // Helper template functions to be registered in your app
  static const String helperFunctions = '''
      {% macro get_alert_class(category) %}
        {% if category == 'success' %}
          bg-green-50 text-green-800 border-green-200
        {% elif category == 'error' %}
          bg-red-50 text-red-800 border-red-200
        {% elif category == 'warning' %}
          bg-yellow-50 text-yellow-800 border-yellow-200
        {% else %}
          bg-blue-50 text-blue-800 border-blue-200
        {% endif %}
      {% endmacro %}

      {% macro get_alert_icon(category) %}
        {% if category == 'success' %}
          <svg class="w-5 h-5 mr-2" fill="currentColor" viewBox="0 0 20 20">
            <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z"></path>
          </svg>
        {% elif category == 'error' %}
          <svg class="w-5 h-5 mr-2" fill="currentColor" viewBox="0 0 20 20">
            <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z"></path>
          </svg>
        {% elif category == 'warning' %}
          <svg class="w-5 h-5 mr-2" fill="currentColor" viewBox="0 0 20 20">
            <path fill-rule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92z"></path>
          </svg>
        {% else %}
          <svg class="w-5 h-5 mr-2" fill="currentColor" viewBox="0 0 20 20">
            <path fill-rule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z"></path>
          </svg>
        {% endif %}
      {% endmacro %}
    ''';
}
