import 'package:serinus/serinus.dart';

class AppController extends Controller {
  AppController() : super('/') {
    on(Route.get('/'), (context) async => 'ok');
    on(Route.get('/json'), (context) async => {'ok': true});
  }
}
