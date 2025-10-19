import '../mixins/default_view.dart';
import 'base_widget.dart';

/// Base class for widgets that let users choose from a list of options.
abstract class ChoiceWidget extends Widget with DefaultView {
  /// Whether multiple options can be selected.
  final bool allowMultipleSelected;

  /// The type of input element to use.
  final String? inputType;

  /// Template name for individual options.
  final String? optionTemplateName;

  /// Whether to add an index to the ID attribute.
  final bool addIdIndex;

  /// Attribute to use for checked/selected options.
  final Map<String, dynamic> checkedAttribute;

  /// Whether options inherit attributes from the parent widget.
  final bool optionInheritsAttrs;

  /// The list of choices available to select from.
  List<List<dynamic>> _choices;

  ChoiceWidget({
    super.attrs,
    List<List<dynamic>>? choices,
    this.allowMultipleSelected = false,
    this.inputType,
    this.optionTemplateName,
    this.addIdIndex = true,
    this.checkedAttribute = const {'checked': true},
    this.optionInheritsAttrs = true,
  }) : _choices = choices ?? [];

  List<List<dynamic>> get choices => _choices;

  set choices(List<List<dynamic>> value) {
    _choices = value.map((choice) {
      if (choice.length == 2 && choice[1] is List) {
        return [choice[0], choice[1]];
      }
      return choice;
    }).toList();
  }

  Iterable<Map<String, dynamic>> subwidgets(
    String name,
    dynamic value, [
    Map<String, String>? extraAttrs,
  ]) sync* {
    value = formatValue(value);
    yield* options(name, value, extraAttrs);
  }

  Iterable<Map<String, dynamic>> options(
    String name,
    dynamic value, [
    Map<String, String>? extraAttrs,
  ]) sync* {
    for (final group in optgroups(name, value, extraAttrs)) {
      yield* group.$2;
    }
  }

  List<(String?, List<Map<String, dynamic>>, Map<String, dynamic>)> optgroups(
    String name,
    dynamic value, [
    Map<String, dynamic>? extraAttrs,
  ]) {
    final groups =
        <(String?, List<Map<String, dynamic>>, Map<String, dynamic>)>[];
    bool hasSelected = false;

    for (int index = 0; index < choices.length; index++) {
      final String optionValue = choices[index][0]?.toString() ?? '';
      final dynamic optionLabel = choices[index][1];
      final List<Map<String, dynamic>> subgroup = [];
      String? groupName;
      int? subindex;
      List<List<dynamic>> groupChoices;

      if (optionLabel is List<List<dynamic>>) {
        groupName = optionValue;
        subindex = 0;
        groupChoices = optionLabel;
      } else {
        groupName = null;
        subindex = null;
        groupChoices = [
          [optionValue, optionLabel],
        ];
      }

      final groupAttrs = <String, dynamic>{};
      groups.add((groupName, subgroup, groupAttrs));

      for (final choice in groupChoices) {
        final dynamic subvalue = choice[0];
        final dynamic sublabel = choice[1];
        final bool selected = isValueSelected(subvalue, value);
        hasSelected = hasSelected || selected;

        subgroup.add(
          createOption(
            name,
            subvalue,
            sublabel,
            selected,
            index,
            subindex: subindex,
            attrs: extraAttrs,
          ),
        );

        if (subindex != null) {
          subindex++;
        }
      }
    }

    return groups;
  }

  bool isValueSelected(dynamic optionValue, dynamic value) {
    if (value == null) return false;
    if (allowMultipleSelected && value is List) {
      final result = value.any((v) => v?.toString() == optionValue?.toString());
      return result;
    }
    final result = value.toString() == optionValue?.toString();
    return result;
  }

  Map<String, dynamic> createOption(
    String name,
    dynamic value,
    dynamic label,
    bool selected,
    int index, {
    int? subindex,
    Map<String, dynamic>? attrs,
  }) {
    final String indexStr = subindex == null
        ? index.toString()
        : '${index}_$subindex';
    final Map<String, dynamic> optionAttrs = optionInheritsAttrs
        ? {...?attrs, ...this.attrs}
        : {};
    if (selected) {
      optionAttrs.addAll(checkedAttribute);
    }
    if (optionAttrs.containsKey('id')) {
      optionAttrs['id'] = idForLabel(optionAttrs['id'] as String?, indexStr);
    }
    return {
      'name': name,
      'value': value,
      'label': label,
      'selected': selected,
      'index': indexStr,
      'attrs': optionAttrs,
      'type': inputType,
      'template_name': optionTemplateName,
      'wrap_label': true,
    };
  }

  @override
  Map<String, dynamic> getContext(
    String name,
    dynamic value, [
    Map<String, dynamic>? extraAttrs,
  ]) {
    final context = super.getContext(name, value, extraAttrs);
    context['widget']['optgroups'] = optgroups(name, value, extraAttrs);
    return context;
  }

  @override
  String idForLabel(String? id, [String? index]) {
    return addIdIndex && id != null && index != null
        ? '${id}_$index'
        : id ?? '';
  }

  @override
  dynamic valueFromData(Map<String, dynamic> data, String name) {
    if (allowMultipleSelected && data[name] is List) {
      return List<String>.from(data[name] as Iterable<dynamic>);
    }
    return data[name];
  }

  @override
  List<String> formatValue(dynamic value) {
    if (value == null) return [];
    if (value is! List) {
      value = [value];
    }
    return value.map((v) => v?.toString() ?? '').toList();
  }
}
