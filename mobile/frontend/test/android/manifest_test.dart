import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

  test('recordings and the database are not copied to Google Drive by Android backup', () {
    // Everything stays on the phone (spec): no cloud backup of the app's data.
    expect(manifest, contains('android:allowBackup="false"'));
  });

  test('the app starts its own engine so a recording outlives the window', () {
    expect(manifest, contains('android:name=".VoiceDeskApplication"'));
  });

  test('the service may record and process', () {
    expect(manifest, contains('android:foregroundServiceType="microphone|dataSync"'));
    expect(manifest, contains('android.permission.FOREGROUND_SERVICE_DATA_SYNC'));
  });

  test('the app stays in portrait', () {
    final activity = RegExp(r'<activity[^>]*android:name="\.MainActivity"[^>]*>').firstMatch(manifest)!.group(0)!;
    expect(activity, contains('android:screenOrientation="portrait"'));
  });

  test('on iOS too: portrait only, on iPhone and iPad', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    List<String> orientations(String key) {
      final array = RegExp('<key>${RegExp.escape(key)}</key>' r'\s*<array>(.*?)</array>', dotAll: true)
          .firstMatch(plist)!
          .group(1)!;
      return RegExp('<string>(.*?)</string>').allMatches(array).map((m) => m.group(1)!).toList();
    }

    expect(orientations('UISupportedInterfaceOrientations'), ['UIInterfaceOrientationPortrait']);
    expect(orientations('UISupportedInterfaceOrientations~ipad'), ['UIInterfaceOrientationPortrait']);
    expect(plist, contains('<key>UIRequiresFullScreen</key>'));
  });
}
