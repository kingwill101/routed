import '../base_input.dart';
import 'split_datetime_widget.dart';

/// A widget that splits datetime input into two `<input type="hidden">` inputs.
class SplitHiddenDateTimeWidget extends SplitDateTimeWidget {
  SplitHiddenDateTimeWidget({
    super.attrs,
    super.dateFormat,
    super.timeFormat,
    super.dateAttrs,
    super.timeAttrs,
  }) {
    for (final widget in widgets) {
      if (widget is Input) {
        widget.inputType = 'hidden';
      }
    }
  }
}
