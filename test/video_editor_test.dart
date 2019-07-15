import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_editor/video_editor.dart';

void main() {
  const MethodChannel channel = MethodChannel('video_editor');

  setUp(() {
    channel.setMockMethodCallHandler((MethodCall methodCall) async {
      return '42';
    });
  });

  tearDown(() {
    channel.setMockMethodCallHandler(null);
  });

  test('getPlatformVersion', () async {
    expect(await VideoEditor.platformVersion, '42');
  });
}
