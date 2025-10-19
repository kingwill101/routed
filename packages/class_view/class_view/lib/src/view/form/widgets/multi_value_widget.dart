import '../mixins/default_view.dart';
import 'multi_widget.dart';

class MultiValueWidget extends MultiWidget with DefaultView {
  MultiValueWidget({required super.widgets, super.attrs});

  @override
  Future<String> renderDefault(Map<String, dynamic> context) async {
    final subwidgets =
        context['widget']['subwidgets'] as List<Map<String, dynamic>>;
    final renderedWidgets = <String>[];

    for (var i = 0; i < widgets.length; i++) {
      final widget = widgets[i];
      final subwidget = subwidgets[i];
      final name = subwidget['name'] as String;
      final value = subwidget['value'];
      final attrsMap = subwidget['attrs'] as Map<String, dynamic>;
      final attrs = <String, String>{};
      attrsMap.forEach((key, val) {
        if (val is String) {
          attrs[key.toString()] = val;
        } else if (val is bool && val) {
          attrs[key.toString()] = '';
        } else {
          attrs[key.toString()] = val.toString();
        }
      });

      final rendered = await widget.render(name, value, attrs: attrs);
      renderedWidgets.add(rendered);
    }

    return renderedWidgets.join('\n');
  }

  @override
  List<dynamic> decompress(dynamic value) {
    if (value == null) {
      return List.filled(widgets.length, null);
    }
    if (value is List) {
      // Pad with nulls if the list is shorter than the number of widgets
      if (value.length < widgets.length) {
        return [...value, ...List.filled(widgets.length - value.length, null)];
      }
      return value;
    }
    return [value, ...List.filled(widgets.length - 1, null)];
  }

  @override
  Map<String, dynamic> getContext(
    String name,
    dynamic value, [
    Map<String, dynamic>? extraAttrs,
  ]) {
    final context = super.getContext(name, value, extraAttrs);
    final decompressedValue = decompress(value);

    final subwidgets = <Map<String, dynamic>>[];
    for (var i = 0; i < widgets.length; i++) {
      final widget = widgets[i];
      final val = i < decompressedValue.length ? decompressedValue[i] : null;

      // Merge widget's own attrs with any that were passed to the multi-widget
      final widgetAttrs = Map<String, dynamic>.from(widget.attrs);
      if (extraAttrs != null) {
        widgetAttrs.addAll(extraAttrs);
      }

      subwidgets.add({
        'widget': widget,
        'rendered': widget.formatValue(val),
        'name': '${name}_$i',
        'value': val,
        'attrs': widgetAttrs,
      });
    }

    context['widget']['subwidgets'] = subwidgets;
    return context;
  }
}
