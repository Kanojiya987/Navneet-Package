// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:geo_camera_pro_example/main.dart';

void main() {
  testWidgets('shows camera and GPS tracking controls', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    expect(find.text('Start Tracking'), findsOneWidget);
    expect(find.text('Stop Tracking'), findsOneWidget);
    expect(find.text('Capture Photo'), findsOneWidget);
  });
}
