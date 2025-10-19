// import 'package:class_view/src/view/class_view/form/fields/field.dart';
// import 'package:class_view/src/view/class_view/form/validation.dart';
// import 'package:class_view/src/view/class_view/form/widgets/text_input.dart';
// import 'package:class_view/src/view/class_view/form/widgets/hidden_input.dart';
// import 'package:class_view/src/view/class_view/form/widgets/base_widget.dart'
//     show Widget;
//
// class GenericIPAddressField<T> extends Field<T> {
//   @override
//   Map<String, String> get defaultErrorMessages => const {
//     "required": "This field is required.",
//     "invalid": "Enter a valid IPv4 or IPv6 address.",
//     "invalid_ipv4": "Enter a valid IPv4 address.",
//     "invalid_ipv6": "Enter a valid IPv6 address.",
//   };
//
//   final bool unpackIPv4;
//   final String protocol;
//
//   static final RegExp _ipv4Regex = RegExp(
//       r'^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$');
//
//   static final RegExp _ipv6Regex = RegExp(
//       r'^(?:(?:[0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}|(?:[0-9a-fA-F]{1,4}:){1,7}:|(?:[0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|(?:[0-9a-fA-F]{1,4}:){1,5}(?::[0-9a-fA-F]{1,4}){1,2}|(?:[0-9a-fA-F]{1,4}:){1,4}(?::[0-9a-fA-F]{1,4}){1,3}|(?:[0-9a-fA-F]{1,4}:){1,3}(?::[0-9a-fA-F]{1,4}){1,4}|(?:[0-9a-fA-F]{1,4}:){1,2}(?::[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:(?:(?::[0-9a-fA-F]{1,4}){1,6})|:(?:(?::[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(?::[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|::(?:ffff(?::0{1,4}){0,1}:){0,1}(?:(?:25[0-5]|(?:2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(?:25[0-5]|(?:2[0-4]|1{0,1}[0-9]){0,1}[0-9])|(?:[0-9a-fA-F]{1,4}:){1,4}:(?:(?:25[0-5]|(?:2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(?:25[0-5]|(?:2[0-4]|1{0,1}[0-9]){0,1}[0-9]))$');
//
//   GenericIPAddressField({
//     String? name,
//     this.protocol = 'both',
//     this.unpackIPv4 = false,
//     Widget? widget,
//     Widget? hiddenWidget,
//     super.validators,
//     super.required,
//     super.label,
//     super.initial,
//     super.helpText,
//     Map<String, String>? errorMessages,
//     super.showHiddenInitial,
//     super.localize,
//     super.disabled,
//     super.labelSuffix,
//     super.templateName,
//   }) : super(
//           name: name ?? '',
//           widget: widget ?? TextInput(),
//           hiddenWidget: hiddenWidget ?? HiddenInput(),
//           errorMessages: {
//             ...const {
//               "required": "This field is required.",
//               "invalid": "Enter a valid IPv4 or IPv6 address.",
//               "invalid_ipv4": "Enter a valid IPv4 address.",
//               "invalid_ipv6": "Enter a valid IPv6 address.",
//             },
//             ...?errorMessages,
//           });
//
//   @override
//   T? toDart(dynamic value) {
//     if (value == null || value.toString().isEmpty) {
//       return null;
//     }
//
//     final ip = value.toString().trim();
//     final isIPv4 = _ipv4Regex.hasMatch(ip);
//     final isIPv6 = _ipv6Regex.hasMatch(ip);
//
//     if (protocol == 'both' && !isIPv4 && !isIPv6) {
//       throw ValidationError(
//           errorMessages?["invalid"] ?? defaultErrorMessages["invalid"]!);
//     } else if (protocol == 'IPv4' && !isIPv4) {
//       throw ValidationError(
//           errorMessages?["invalid_ipv4"] ?? defaultErrorMessages["invalid_ipv4"]!);
//     } else if (protocol == 'IPv6' && !isIPv6) {
//       throw ValidationError(
//           errorMessages?["invalid_ipv6"] ?? defaultErrorMessages["invalid_ipv6"]!);
//     }
//
//     return ip as T;
//   }
// }
