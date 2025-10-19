// import 'package:class_view/src/view/class_view/form/mixins/default_view.dart';
// import 'package:class_view/src/view/class_view/form/widgets/base_widget.dart';

// /// A widget for rendering number input fields.
// class NumberInput extends Widget with DefaultView {
//   /// Creates a new number input widget.
//   NumberInput({
//     Map<String, String>? attributes,
//   }) : super(attrs: attributes);

//   @override
//   Future<String> renderDefault(Map<String, dynamic> context) async {
//     final widget = context['widget'] as Map<String, dynamic>;
//     final name = widget['name'] as String;
//     final value = widget['value'];
//     final attrs = widget['attrs'] as Map<String, String>;

//     // Ensure step attribute is present for float fields
//     if (!attrs.containsKey('step')) {
//       attrs['step'] = 'any';
//     }

//     final buffer = StringBuffer('<input type="number"');
//     buffer.write(' name="$name"');

//     if (value != null) {
//       buffer.write(' value="$value"');
//     }

//     attrs.forEach((key, value) {
//       buffer.write(' $key="$value"');
//     });

//     buffer.write('>');
//     return buffer.toString();
//   }
// }
