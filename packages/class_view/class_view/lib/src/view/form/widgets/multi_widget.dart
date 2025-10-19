import '../mixins/default_view.dart';
import 'base_widget.dart';

/// A widget that is composed of multiple widgets.
///
/// In addition to the values added by Widget.getContext(), this widget
/// adds a list of subwidgets to the context as widget['subwidgets'].
/// These can be looped over and rendered like normal widgets.
///
/// You'll probably want to use this class with MultiValueField.
abstract class MultiWidget extends Widget with DefaultView {
  /// The list of widgets that make up this composite widget
  final List<Widget> widgets;

  /// The names of the individual widgets
  final List<String> widgetNames;

  MultiWidget({required this.widgets, super.attrs})
    : widgetNames = List.generate(widgets.length, (i) => '_$i');

  @override
  bool get isHidden => widgets.every((widget) => widget.isHidden);

  @override
  Map<String, dynamic> getContext(
    String name,
    dynamic value, [
    Map<String, dynamic>? extraAttrs,
  ]) {
    final context = super.getContext(name, value, extraAttrs);
    final List<dynamic> decompressedValue = value is List
        ? value
        : decompress(value);

    final subwidgets = <Map<String, dynamic>>[];
    for (int i = 0; i < widgets.length; i++) {
      final widget = widgets[i];
      final widgetName = '$name${widgetNames[i]}';
      final widgetValue = i < decompressedValue.length
          ? decompressedValue[i]
          : null;

      // Merge attributes from the widget itself and any extra attributes
      final widgetAttrs = Map<String, dynamic>.from(widget.attrs);
      if (extraAttrs != null) {
        widgetAttrs.addAll(extraAttrs);
      }

      // Handle ID attribute
      if (widgetAttrs.containsKey('id')) {
        widgetAttrs['id'] = '${widgetAttrs['id']}_$i';
      }

      // Get the widget's context with the merged attributes
      final widgetContext = widget.getContext(
        widgetName,
        widgetValue,
        widgetAttrs,
      );

      // Add rendered widget to subwidgets list
      if (widgetContext['widget'] is Map<String, dynamic>) {
        final subwidget = widgetContext['widget'] as Map<String, dynamic>;
        subwidget['rendered'] = widget.render(
          widgetName,
          widgetValue,
          attrs: widgetAttrs,
        );
        subwidgets.add(subwidget);
      }
    }

    context['widget']['subwidgets'] = subwidgets;
    return context;
  }

  @override
  dynamic valueFromData(Map<String, dynamic> data, String name) {
    return widgets.asMap().entries.map((entry) {
      final i = entry.key;
      final widget = entry.value;
      return widget.valueFromData(data, '$name${widgetNames[i]}');
    }).toList();
  }

  @override
  bool valueOmittedFromData(Map<String, dynamic> data, String name) {
    return widgets.asMap().entries.every((entry) {
      final i = entry.key;
      final widget = entry.value;
      return widget.valueOmittedFromData(data, '$name${widgetNames[i]}');
    });
  }

  /// Decompresses a single value into a list of values for the subwidgets
  List<dynamic> decompress(dynamic value);
}
