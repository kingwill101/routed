import '../validation.dart';
import '../widgets/base_widget.dart' show Widget;
import '../widgets/hidden_input.dart';
import '../widgets/text_input.dart';
import 'field.dart';

class DurationField<T> extends Field<T> {
  @override
  Map<String, String> get defaultErrorMessages => const {
    "required": "This field is required.",
    "invalid": "Enter a valid duration.",
    "overflow": "The duration value is too large.",
    "min_duration": "Duration must be %(min_duration)s or longer",
    "max_duration": "Duration must be %(max_duration)s or shorter",
  };

  final Duration? minDuration;
  final Duration? maxDuration;

  DurationField({
    String? name,
    this.minDuration,
    this.maxDuration,
    Widget? widget,
    Widget? hiddenWidget,
    super.validators,
    super.required = true,
    super.label,
    super.initial,
    super.helpText,
    Map<String, String>? errorMessages,
    super.showHiddenInitial,
    super.localize,
    super.disabled,
    super.labelSuffix,
    super.templateName,
  }) : super(
         name: name ?? '',
         widget: widget ?? TextInput(),
         hiddenWidget: hiddenWidget ?? HiddenInput(),
         errorMessages: {
           ...const {
             "required": "This field is required.",
             "invalid": "Enter a valid duration.",
             "overflow": "The duration value is too large.",
             "min_duration": "Duration must be %(min_duration)s or longer",
             "max_duration": "Duration must be %(max_duration)s or shorter",
           },
           ...?errorMessages,
         },
       );

  @override
  T? toDart(dynamic value) {
    if (value == null || value.toString().isEmpty) {
      if (required) {
        throw ValidationError({
          'required': [
            errorMessages?["required"] ?? defaultErrorMessages["required"]!,
          ],
        });
      }
      return null;
    }

    try {
      final parts = value.toString().split(':');
      if (parts.length != 3) {
        throw ValidationError({
          'invalid': [
            errorMessages?["invalid"] ?? defaultErrorMessages["invalid"]!,
          ],
        });
      }

      final hours = int.parse(parts[0]);
      final minutes = int.parse(parts[1]);
      final seconds = int.parse(parts[2]);

      if (minutes >= 60 || seconds >= 60) {
        throw ValidationError({
          'invalid': [
            errorMessages?["invalid"] ?? defaultErrorMessages["invalid"]!,
          ],
        });
      }

      final duration = Duration(
        hours: hours,
        minutes: minutes,
        seconds: seconds,
      );

      return duration as T;
    } catch (e) {
      if (e is ValidationError) rethrow;
      throw ValidationError({
        'invalid': [
          errorMessages?["invalid"] ?? defaultErrorMessages["invalid"]!,
        ],
      });
    }
  }

  @override
  Future<void> validate(T? value) async {
    await super.validate(value);

    if (value == null || value.toString().isEmpty) {
      return;
    }

    final duration = value as Duration;
    if (minDuration != null && duration < minDuration!) {
      throw ValidationError({
        'min_duration': [
          (errorMessages?["min_duration"] ??
                  defaultErrorMessages["min_duration"]!)
              .replaceAll("%(min_duration)s", formatDuration(minDuration!)),
        ],
      });
    }

    if (maxDuration != null && duration > maxDuration!) {
      throw ValidationError({
        'max_duration': [
          (errorMessages?["max_duration"] ??
                  defaultErrorMessages["max_duration"]!)
              .replaceAll("%(max_duration)s", formatDuration(maxDuration!)),
        ],
      });
    }
  }

  String formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$hours:$minutes:$seconds';
  }
}
