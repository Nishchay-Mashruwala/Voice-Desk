import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The models' and the word list's licences, as Flutter's licence page shows
/// them (the packages' own are added by Flutter). Texts are the originals, in
/// `assets/licences/`.
const _modelLicences = {
  'Parakeet': 'cc-by-4.0.txt',
  'IndicConformer': 'indicconformer-mit.txt',
  'IndicConformer phone versions': 'parismita-apache-2.0.txt',
  'Silero VAD': 'silero-vad-mit.txt',
  'CAM++': '3d-speaker-apache-2.0.txt',
  'English word list': 'scowl.txt',
};

var _registered = false;

/// Adds them to Flutter's licence registry (once, however often it is called).
void registerModelLicences() {
  if (_registered) return;
  _registered = true;
  LicenseRegistry.addLicense(() async* {
    for (final MapEntry(key: what, value: file) in _modelLicences.entries) {
      yield LicenseEntryWithLineBreaks([what], await rootBundle.loadString('assets/licences/$file'));
    }
  });
}
