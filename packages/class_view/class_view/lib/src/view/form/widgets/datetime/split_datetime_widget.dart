import '../multi_widget.dart';
import 'date_input.dart';
import 'time_input.dart';

/// A widget that splits datetime input into two `<input type="text">` boxes.
class SplitDateTimeWidget extends MultiWidget {
  @override
  bool get supportsMicroseconds => false;

  SplitDateTimeWidget({
    super.attrs,
    String? dateFormat,
    String? timeFormat,
    Map<String, String>? dateAttrs,
    Map<String, String>? timeAttrs,
  }) : super(
         widgets: [
           DateInput(
             attrs: dateAttrs ?? attrs ?? {},
             format: dateFormat ?? 'yyyy-MM-dd',
             templateName: 'widgets/date.html',
             inputType: 'date',
           ),
           TimeInput(
             attrs: timeAttrs ?? attrs ?? {},
             format: timeFormat ?? 'HH:mm',
             templateName: 'widgets/time.html',
             inputType: 'time',
           ),
         ],
       );

  @override
  List<dynamic> decompress(dynamic value) {
    if (value != null) {
      return [value.date, value.time];
    }
    return [null, null];
  }

  @override
  Future<String> renderDefault(Map<String, dynamic> context) async {
    final buffer = StringBuffer();
    final subwidgets = context['widget']['subwidgets'] as List<dynamic>;

    for (var i = 0; i < subwidgets.length; i++) {
      final subwidget = subwidgets[i];
      final subContext = Map<String, dynamic>.from(context);
      subContext['widget'] = subwidget;

      if (i > 0) {
        buffer.write(' '); // Add space between date and time inputs
      }

      buffer.write(
        await widgets[i].render(
          subwidget['template_name'] as String,
          subContext,
        ),
      );
    }

    return buffer.toString();
  }
}
