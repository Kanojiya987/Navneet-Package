import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geo_camera_pro/geo_camera_pro_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MethodChannelGeoCameraPro platform = MethodChannelGeoCameraPro();
  const MethodChannel channel = MethodChannel('geo_camera_pro');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          return '42';
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('getPlatformVersion', () async {
    expect(await platform.getPlatformVersion(), '42');
  });
}
