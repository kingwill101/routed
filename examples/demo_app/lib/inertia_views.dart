import 'package:routed/routed.dart';

void configureInertiaViews(Engine engine) {
  engine.useViewEngine(LiquidViewEngine(directory: 'views'));
}
