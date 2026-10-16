import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // Flutter puts INTERNET only in the debug and profile manifests: a release
  // build without it in the main one can't download a single model (every
  // lookup fails: "No address associated with hostname").
  test('the release app may use the network', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest, contains('<uses-permission android:name="android.permission.INTERNET" />'));
  });
}
