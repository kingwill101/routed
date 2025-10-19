import 'package:routed/routed.dart';
import 'package:routed_class_view/routed_class_view.dart';
import 'package:routed_testing/routed_testing.dart';

class BodyHandlingTestView extends View {
  @override
  List<String> get allowedMethods => ['POST'];

  @override
  Future<void> post() async {
    await sendJson({'body_info': {}});
  }
}

void main() {
  final engine = Engine()
    ..postView('/body-handling', () => BodyHandlingTestView());

  // engineTest('should read JSON body correctly', (eng, client) async {
  //   final requestData = {'name': 'John', 'age': 30, 'city': 'NYC'};
  //   final response = await client.postJson('/body-handling', requestData);
  //
  //   response.assertStatus(200).assertJson((json) {
  //     json
  //         .has('body_info.json_body')
  //         .where('body_info.json_body.name', 'John')
  //         .where('body_info.json_body.age', 30)
  //         .where('body_info.json_body.city', 'NYC');
  //   });
  // }, engine: engine);

  engineTest('should read raw body as string', (eng, client) async {
    final response = await client.post(
      '/body-handling',
      'Plain text body content',
      headers: {
        'Content-Type': ['text/plain'],
      },
    );
    response.dump();
    response.assertStatus(200).assertJson((json) {
      json.where('body_info.body', 'Plain text body content');
    });
  }, engine: engine);

  // engineTest('should handle form data', (eng, client) async {
  //   final formBody = 'title=Test+Title&description=Test+Description&active=true';
  //   final response = await client.post(
  //     '/body-handling',
  //     formBody,
  //     headers: {
  //       'Content-Type': ['application/x-www-form-urlencoded']
  //     },
  //   );
  //
  //   response.assertStatus(200).assertJson((json) {
  //     json
  //         .has('body_info.form_data')
  //         .where('body_info.form_data.title', 'Test Title')
  //         .where('body_info.form_data.description', 'Test Description')
  //         .where('body_info.form_data.active', 'true');
  //   });
  // }, engine: engine);
}
