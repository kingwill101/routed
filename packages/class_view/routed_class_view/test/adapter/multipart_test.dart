import 'package:routed/routed.dart';
import 'package:routed_class_view/routed_class_view.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:http_parser/http_parser.dart';

class MultipartTestView extends View {
  @override
  List<String> get allowedMethods => ['POST'];

  @override
  Future<void> post() async {
    final formData = await getFormData();
    await sendJson({
      'body_info': {'form_data': formData},
    });
  }
}

void main() {
  final engine = Engine()..postView('/multipart', () => MultipartTestView());

  engineTest('should handle multipart file upload correctly', (
    eng,
    client,
  ) async {
    final response = await client.multipart('/multipart', (builder) {
      builder.addField('text', 'This is a text field');
      builder.addFileFromString(
        name: 'file',
        content: 'Hello, World!',
        filename: 'test.txt',
        contentType: MediaType('text', 'plain'),
      );
    });

    response.assertStatus(200).assertJson((json) {
      json.has('body_info.form_data');
      json.where('body_info.form_data.text', 'This is a text field');
      json.has('body_info.form_data.file');
    });
  }, engine: engine);
}
