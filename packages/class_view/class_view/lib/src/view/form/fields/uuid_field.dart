// import 'package:class_view/src/view/class_view/form/fields/field.dart';
// import 'package:class_view/src/view/class_view/form/validation.dart';
//
// /// A form field that validates and converts UUID strings.
// class UUIDField extends Field {
//   /// Creates a new UUID field.
//   ///
//   /// The [required] parameter determines if the field is required.
//   UUIDField({bool required = false}) : super(required: required);
//
//   @override
//   Future<String?> clean(dynamic value) async {
//     value = await super.clean(value);
//     if (value == null) {
//       return null;
//     }
//
//     // Convert to string if not already
//     final strValue = value.toString();
//
//     // Remove any dashes and whitespace
//     final cleanValue = strValue.replaceAll('-', '').trim();
//
//     // Validate UUID format (32 hex digits)
//     if (!RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(cleanValue)) {
//       throw ValidationError('Enter a valid UUID.');
//     }
//
//     // Format with dashes
//     return '${cleanValue.substring(0, 8)}-${cleanValue.substring(8, 12)}-'
//         '${cleanValue.substring(12, 16)}-${cleanValue.substring(16, 20)}-${cleanValue.substring(20)}';
//   }
//
//   @override
//   dynamic prepareValue(dynamic value) {
//     if (value == null) {
//       return null;
//     }
//     // Return the formatted UUID with dashes
//     return value.toString();
//   }
// }
