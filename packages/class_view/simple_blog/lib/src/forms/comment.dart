import 'package:class_view/class_view.dart';

/// Comment form for post detail page
class CommentForm extends Form {
  CommentForm({Map<String, dynamic>? data, super.isBound = false})
    : super(
        data: data ?? {},
        files: {},
        fields: {
          'name': CharField<String>(required: true, maxLength: 100),
          'email': EmailField(required: true),
          'comment': CharField<String>(required: true, maxLength: 1000),
        },
      );
}
