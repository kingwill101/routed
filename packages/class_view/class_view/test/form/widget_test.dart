import 'package:class_view/class_view.dart'
    show
        CheckboxInput,
        CheckboxSelectMultiple,
        ClearableFileInput,
        ColorInput,
        DateInput,
        DateTimeInput,
        EmailInput,
        FileInput,
        HiddenInput,
        Media,
        MultipleHiddenInput,
        NullBooleanSelect,
        NumberInput,
        PasswordInput,
        RadioSelect,
        Renderer,
        Script,
        SearchInput,
        Select,
        SelectMultiple,
        SplitDateTimeWidget,
        SplitHiddenDateTimeWidget,
        TelInput,
        TextInput,
        Textarea,
        TimeInput,
        URLInput;
import 'package:test/test.dart';

void main() {
  group('Basic Input Widgets', () {
    test('TextInput renders correctly', () async {
      final widget = TextInput();
      final html = await widget.render('name', 'test value');
      expect(html, contains('type="text"'));
      expect(html, contains('name="name"'));
      expect(html, contains('value="test value"'));
    });

    test('EmailInput renders correctly', () async {
      final widget = EmailInput();
      final html = await widget.render('email', 'test@example.com');
      expect(html, contains('type="email"'));
      expect(html, contains('value="test@example.com"'));
    });

    test('PasswordInput renders correctly', () async {
      final widget = PasswordInput();
      final html = await widget.render('password', 'secret');
      expect(html, contains('type="password"'));
      expect(html, contains('value="secret"'));
    });

    test('NumberInput renders correctly', () async {
      final widget = NumberInput();
      final html = await widget.render('age', 25);
      expect(html, contains('type="number"'));
      expect(html, contains('value="25"'));
    });

    test('URLInput renders correctly', () async {
      final widget = URLInput();
      final html = await widget.render('website', 'https://example.com');
      expect(html, contains('type="url"'));
      expect(html, contains('value="https://example.com"'));
    });

    test('TelInput renders correctly', () async {
      final widget = TelInput();
      final html = await widget.render('phone', '+1234567890');
      expect(html, contains('type="tel"'));
      expect(html, contains('value="+1234567890"'));
    });

    test('SearchInput renders correctly', () async {
      final widget = SearchInput();
      final html = await widget.render('query', 'search term');
      expect(html, contains('type="search"'));
      expect(html, contains('value="search term"'));
    });

    test('ColorInput renders correctly', () async {
      final widget = ColorInput();
      final html = await widget.render('color', '#ff0000');
      expect(html, contains('type="color"'));
      expect(html, contains('value="#ff0000"'));
    });
  });

  group('Hidden Input Widgets', () {
    test('HiddenInput renders correctly', () async {
      final widget = HiddenInput();
      final html = await widget.render('hidden', 'hidden_value');
      expect(html, contains('type="hidden"'));
      expect(html, contains('value="hidden_value"'));
    });

    test('MultipleHiddenInput renders correctly', () async {
      final widget = TestMultipleHiddenInput();
      final html = await widget.render('values', ['1', '2', '3']);
      expect(html, contains('type="hidden"'));
      expect(html.split('type="hidden"').length - 1, equals(3));
      expect(html, contains('value="1"'));
      expect(html, contains('value="2"'));
      expect(html, contains('value="3"'));
    });
  });

  group('DateTime Widgets', () {
    test('DateInput renders correctly', () async {
      final widget = DateInput();
      final html = await widget.render('date', '2023-12-31');
      expect(html, contains('type="date"'));
      expect(html, contains('value="2023-12-31"'));
    });

    test('TimeInput renders correctly', () async {
      final widget = TimeInput();
      final html = await widget.render('time', '14:30');
      expect(html, contains('type="time"'));
      expect(html, contains('value="14:30"'));
    });

    test('DateTimeInput renders correctly', () async {
      final widget = DateTimeInput();
      final html = await widget.render('datetime', '2023-12-31T14:30');
      expect(html, contains('type="datetime-local"'));
      expect(html, contains('value="2023-12-31T14:30"'));
    });

    test('SplitDateTimeWidget renders correctly', () async {
      final widget = TestSplitDateTimeWidget();
      final value = TestDateTime(date: '2023-12-31', time: '14:30');
      final html = await widget.render('datetime', value);
      expect(html, contains('name="datetime_0"')); // Date part
      expect(html, contains('name="datetime_1"')); // Time part
      expect(html, contains('value="2023-12-31"'));
      expect(html, contains('value="14:30"'));
    });

    test('SplitHiddenDateTimeWidget renders correctly', () async {
      final widget = TestSplitHiddenDateTimeWidget();
      final value = TestDateTime(date: '2023-12-31', time: '14:30');
      final html = await widget.render('datetime', value);
      expect(html, contains('type="hidden"'));
      expect(html, contains('name="datetime_0"')); // Date part
      expect(html, contains('name="datetime_1"')); // Time part
      expect(html, contains('value="2023-12-31"'));
      expect(html, contains('value="14:30"'));
    });
  });

  group('File Widgets', () {
    test('FileInput renders correctly', () async {
      final widget = FileInput();
      final html = await widget.render('file', null);
      expect(html, contains('type="file"'));
      expect(widget.needsMultipartForm, isTrue);
    });

    test('ClearableFileInput renders correctly', () async {
      final widget = ClearableFileInput();
      final testFile = TestFile('test.txt');
      final html = await widget.render('file', testFile);
      expect(html, contains('type="file"'));
      expect(html, contains('clear'));
      expect(html, contains('Currently: test.txt'));
      expect(widget.needsMultipartForm, isTrue);
    });
  });

  group('Choice Widgets', () {
    final choices = [
      ['1', 'Option 1'],
      ['2', 'Option 2'],
      ['3', 'Option 3'],
    ];

    test('Select renders correctly', () async {
      final widget = Select(choices: choices);
      final html = await widget.render('select', '2');
      expect(html, contains('<select'));
      expect(html, contains('name="select"'));
      expect(html, contains('value="1"'));
      expect(html, contains('value="2"'));
      expect(html, contains('value="3"'));
      expect(html, contains('Option 1'));
      expect(html, contains('Option 2'));
      expect(html, contains('Option 3'));
      expect(html, contains('selected'));
      expect(html, contains('</select>'));
    });

    test('SelectMultiple renders correctly', () async {
      final widget = SelectMultiple(choices: choices);
      final html = await widget.render('select_multiple', ['1', '3']);
      expect(html, contains('<select'));
      expect(html, contains('name="select_multiple"'));
      expect(html, contains('multiple'));
      expect(html, contains('value="1"'));
      expect(html, contains('value="2"'));
      expect(html, contains('value="3"'));
      expect(html.split('selected').length - 1, equals(2));
    });

    test('RadioSelect renders correctly', () async {
      final widget = RadioSelect(choices: choices);
      final html = await widget.render('radio', '2');
      expect(html, contains('type="radio"'));
      expect(html, contains('name="radio"'));
      expect(html, contains('value="1"'));
      expect(html, contains('value="2"'));
      expect(html, contains('value="3"'));
      expect(html, contains('checked'));
    });

    test('CheckboxSelectMultiple renders correctly', () async {
      final widget = CheckboxSelectMultiple(choices: choices);
      final html = await widget.render('checkbox_multiple', ['1', '3']);
      expect(html, contains('type="checkbox"'));
      expect(html, contains('name="checkbox_multiple"'));
      expect(html, contains('value="1"'));
      expect(html, contains('value="2"'));
      expect(html, contains('value="3"'));
      expect(html.split('checked').length - 1, equals(2));
    });

    test('NullBooleanSelect renders correctly', () async {
      final widget = NullBooleanSelect();

      final nullHtml = await widget.render('active', null);
      expect(nullHtml, contains('<select'));
      expect(nullHtml, contains('name="active"'));
      expect(nullHtml, contains('<option value=""'));
      expect(nullHtml, contains('selected'));
      expect(nullHtml, contains('Unknown'));

      final trueHtml = await widget.render('active', true);
      expect(trueHtml, contains('<option value="true"'));
      expect(trueHtml, contains('selected'));
      expect(trueHtml, contains('Yes'));

      final falseHtml = await widget.render('active', false);
      expect(falseHtml, contains('<option value="false"'));
      expect(falseHtml, contains('selected'));
      expect(falseHtml, contains('No'));
    });
  });

  group('Boolean Widgets', () {
    test('CheckboxInput renders correctly', () async {
      final widget = CheckboxInput();
      final html = await widget.render('agree', true);
      expect(html, contains('type="checkbox"'));
      expect(html, contains('name="agree"'));
      expect(html, contains('checked'));

      final uncheckedHtml = await widget.render('agree', false);
      expect(uncheckedHtml, contains('type="checkbox"'));
      expect(uncheckedHtml, contains('name="agree"'));
      expect(uncheckedHtml, isNot(contains('checked')));
    });
  });

  group('Textarea Widget', () {
    test('Textarea renders correctly', () async {
      final widget = Textarea();
      final html = await widget.render('content', 'Test\nMultiline\nContent');
      expect(html, contains('<textarea'));
      expect(html, contains('name="content"'));
      expect(html, contains('Test\nMultiline\nContent'));
      expect(html, contains('</textarea>'));
    });
  });

  group('Media Widgets', () {
    test('Media renders correctly', () {
      final media = Media.js('script.js');
      final html = media.render();
      expect(html, contains('<script'));
      expect(html, contains('src="script.js"'));
      expect(html, contains('</script>'));

      final cssMedia = Media.css('style.css');
      final cssHtml = cssMedia.render();
      expect(cssHtml, contains('<link'));
      expect(cssHtml, contains('href="style.css"'));
      expect(cssHtml, contains('rel="stylesheet"'));
    });

    test('Script defines media correctly', () {
      final script = const Script(path: 'script.js');
      final media = script.getMedia();
      expect(media.length, equals(1));
      expect(media.first.path, equals('script.js'));
      expect(media.first.type, equals('js'));

      final html = media.first.render();
      expect(html, contains('<script'));
      expect(html, contains('src="script.js"'));
      expect(html, contains('</script>'));
    });
  });

  group('Widget Attributes', () {
    test('handles required attribute', () async {
      final widget = TestTextInput()..isRequired = true;
      final html = await widget.render('name', '');
      expect(html, contains('required'));
    });

    test('handles disabled attribute', () async {
      final html = await TestTextInput().render(
        'name',
        '',
        attrs: {'disabled': 'disabled'},
      );
      expect(html, contains('disabled="disabled"'));
    });

    test('handles custom attributes', () async {
      final html = await TestTextInput().render(
        'name',
        '',
        attrs: {
          'class': 'custom-class',
          'data-test': 'value',
          'aria-label': 'Test Input',
        },
      );
      expect(html, contains('class="custom-class"'));
      expect(html, contains('data-test="value"'));
      expect(html, contains('aria-label="Test Input"'));
    });
  });
}

// Test helper classes
class TestFile {
  final String url;
  final String name;

  TestFile(this.name) : url = name;

  @override
  String toString() => name;
}

class TestMultipleHiddenInput extends MultipleHiddenInput {
  @override
  Future<String> render(
    String name,
    value, {
    Map<String, dynamic>? attrs,
    Renderer? renderer,
    String? templateName,
  }) async {
    if (value is! List) return '';
    return value
        .map((v) => '<input type="hidden" name="$name" value="$v">')
        .join();
  }
}

class TestTextInput extends TextInput {
  @override
  Future<String> render(
    String name,
    value, {
    Map<String, dynamic>? attrs,
    Renderer? renderer,
    String? templateName,
  }) async {
    final allAttrs = {
      'type': 'text',
      'name': name,
      if (value != null) 'value': value.toString(),
      if (isRequired) 'required': 'required',
      ...?attrs,
    };
    return '<input ${allAttrs.entries.map((e) => '${e.key}="${e.value}"').join(' ')}>';
  }
}

class TestDateTime {
  final String date;
  final String time;

  TestDateTime({required this.date, required this.time});
}

class TestSplitDateTimeWidget extends SplitDateTimeWidget {
  @override
  Future<String> renderDefault(Map<String, dynamic> context) async {
    final widgets = context['widget']['subwidgets'] as List<dynamic>;
    final dateWidget = widgets[0];
    final timeWidget = widgets[1];
    return '''
      <input type="date" name="${dateWidget['name']}" value="${dateWidget['value']}">
      <input type="time" name="${timeWidget['name']}" value="${timeWidget['value']}">
    ''';
  }
}

class TestSplitHiddenDateTimeWidget extends SplitHiddenDateTimeWidget {
  @override
  Future<String> renderDefault(Map<String, dynamic> context) async {
    final widgets = context['widget']['subwidgets'] as List<dynamic>;
    final dateWidget = widgets[0];
    final timeWidget = widgets[1];
    return '''
      <input type="hidden" name="${dateWidget['name']}" value="${dateWidget['value']}">
      <input type="hidden" name="${timeWidget['name']}" value="${timeWidget['value']}">
    ''';
  }
}
