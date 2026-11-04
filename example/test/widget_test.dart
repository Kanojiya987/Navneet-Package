import 'package:flutter_test/flutter_test.dart';
import 'package:geo_camera_pro_example/main.dart';

void main() {
  testWidgets('renders GeoCameraView with mode switcher and HUD overlay', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('PHOTO'), findsOneWidget);
    expect(find.text('VIDEO'), findsOneWidget);
    expect(find.text('PORTRAIT'), findsOneWidget);
    expect(find.text('MORE'), findsOneWidget);
  });
}
