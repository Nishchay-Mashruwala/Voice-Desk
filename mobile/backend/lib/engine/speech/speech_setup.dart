import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../models/catalogue.dart';

/// A language recordings can be in. Stored by [name] (`en`, `hi`, `gu`).
enum Lang { en, hi, gu }

/// Which English reader: the 110M model, or the 0.6B one.
enum EnglishModel { faster, accurate }

/// Settings → Speech → "Accuracy (speech model)".
enum Accuracy { auto, faster, accurate }

/// How a recording is turned into text: kept with the recording when it is
/// made, so its job always reads it the same way.
@immutable
class SpeechSetup {
  const SpeechSetup(
      {required this.languages, this.prefer = Lang.gu, this.english = EnglishModel.faster, this.speakers = false});

  static const englishOnly = SpeechSetup(languages: {Lang.en});

  final Set<Lang> languages;

  /// Hindi or Gujarati, when it's unclear which.
  final Lang prefer;
  final EnglishModel english;

  /// Who said what (voice prints, then the speakers step).
  final bool speakers;

  bool get hasEnglish => languages.contains(Lang.en);

  /// The Indian languages, in the order `hi`, `gu`.
  List<Lang> get indian => [for (final l in [Lang.hi, Lang.gu]) if (languages.contains(l)) l];

  /// The models it needs, in download order.
  List<ModelId> get models => [
        ModelId.vad,
        if (hasEnglish) english == EnglishModel.faster ? ModelId.englishFaster : ModelId.englishAccurate,
        if (indian.isNotEmpty) ModelId.indicTokens,
        if (languages.contains(Lang.hi)) ModelId.hindi,
        if (languages.contains(Lang.gu)) ModelId.gujarati,
        if (speakers) ModelId.speakers,
      ];

  /// What it runs, as one word for remembering speeds: `faster+gu`, `hi+gu`.
  String get key => [if (hasEnglish) english.name, for (final l in indian) l.name].join('+');

  /// The languages as stored: `en,gu`.
  String get languagesCode => [for (final l in Lang.values) if (languages.contains(l)) l.name].join(',');

  /// Reads a stored setup; anything unknown falls back to English only.
  static SpeechSetup parse(String languages, String prefer, String english, {bool speakers = false}) {
    final langs = {
      for (final code in languages.split(','))
        for (final l in Lang.values)
          if (l.name == code.trim()) l,
    };
    return SpeechSetup(
      languages: langs.isEmpty ? const {Lang.en} : langs,
      prefer: langs.isEmpty || prefer != Lang.hi.name ? Lang.gu : Lang.hi,
      english: langs.isNotEmpty && english == EnglishModel.accurate.name ? EnglishModel.accurate : EnglishModel.faster,
      speakers: speakers,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SpeechSetup &&
      setEquals(other.languages, languages) &&
      other.prefer == prefer &&
      other.english == english &&
      other.speakers == speakers;

  @override
  int get hashCode => Object.hash(languagesCode, prefer, english, speakers);

  @override
  String toString() => 'SpeechSetup($languagesCode, ${prefer.name}, ${english.name}${speakers ? ', speakers' : ''})';
}

const kLanguagesKey = 'languages';
const kPreferIndicKey = 'prefer_indic';
const kAccuracyKey = 'accuracy';
const kSpeakerDetectionKey = 'speaker_detection';

/// Settings → Speech, as chosen (Auto not yet resolved).
@immutable
class SpeechSettings {
  const SpeechSettings(
      {this.languages = const {Lang.en}, this.prefer = Lang.gu, this.accuracy = Accuracy.auto, this.speakers = true});
  final Set<Lang> languages;
  final Lang prefer;
  final Accuracy accuracy;

  /// "Speaker detection".
  final bool speakers;

  SpeechSettings copyWith({Set<Lang>? languages, Lang? prefer, Accuracy? accuracy, bool? speakers}) => SpeechSettings(
        languages: languages ?? this.languages,
        prefer: prefer ?? this.prefer,
        accuracy: accuracy ?? this.accuracy,
        speakers: speakers ?? this.speakers,
      );
}

final speechSettingsProvider = AsyncNotifierProvider<SpeechSettingsNotifier, SpeechSettings>(SpeechSettingsNotifier.new);

class SpeechSettingsNotifier extends AsyncNotifier<SpeechSettings> {
  @override
  Future<SpeechSettings> build() async {
    final settings = ref.read(settingsRepositoryProvider);
    final stored = SpeechSetup.parse(
      await settings.getString(kLanguagesKey, orElse: 'en'),
      await settings.getString(kPreferIndicKey, orElse: 'gu'),
      '',
    );
    final accuracy = await settings.getString(kAccuracyKey, orElse: 'auto');
    return SpeechSettings(
      languages: stored.languages,
      prefer: stored.prefer,
      accuracy: Accuracy.values.firstWhere((a) => a.name == accuracy, orElse: () => Accuracy.auto),
      speakers: await settings.getBool(kSpeakerDetectionKey, orElse: true),
    );
  }

  /// At least one language stays on.
  Future<void> setLanguages(Set<Lang> languages) async {
    if (languages.isEmpty) throw ArgumentError.value(languages, 'languages', 'at least one');
    final now = await future;
    await ref
        .read(settingsRepositoryProvider)
        .setString(kLanguagesKey, SpeechSetup(languages: languages).languagesCode);
    state = AsyncData(now.copyWith(languages: Set.unmodifiable(languages)));
  }

  Future<void> setPrefer(Lang prefer) async {
    if (prefer == Lang.en) throw ArgumentError.value(prefer, 'prefer', 'Hindi or Gujarati');
    final now = await future;
    await ref.read(settingsRepositoryProvider).setString(kPreferIndicKey, prefer.name);
    state = AsyncData(now.copyWith(prefer: prefer));
  }

  Future<void> setAccuracy(Accuracy accuracy) async {
    final now = await future;
    await ref.read(settingsRepositoryProvider).setString(kAccuracyKey, accuracy.name);
    state = AsyncData(now.copyWith(accuracy: accuracy));
  }

  Future<void> setSpeakers(bool on) async {
    final now = await future;
    await ref.read(settingsRepositoryProvider).setBool(kSpeakerDetectionKey, on);
    state = AsyncData(now.copyWith(speakers: on));
  }
}

/// What Auto goes by: memory and the CPU's dot-product instructions (which
/// make the bigger model several times faster).
@immutable
class PhoneClass {
  const PhoneClass({required this.totalRamBytes, required this.dotProduct});
  final int totalRamBytes;
  final bool dotProduct;

  /// "6 GB" phones report about 5.5 GiB.
  static const _bigRam = 11 * 1024 * 1024 * 1024 ~/ 2;

  EnglishModel get auto => dotProduct && totalRamBytes >= _bigRam ? EnglishModel.accurate : EnglishModel.faster;

  /// Whether the 4B task model ("More accurate") is offered: "8 GB" phones
  /// report about 7.3 GiB.
  bool get canRunLargeTaskAi => totalRamBytes >= 7 * 1024 * 1024 * 1024;
}

/// Whether `/proc/cpuinfo` lists ARM's dot-product instructions.
bool hasDotProduct(String cpuinfo) => RegExp(r'^Features\s*:.*\basimddp\b', multiLine: true).hasMatch(cpuinfo);

final phoneClassProvider = FutureProvider<PhoneClass>((ref) async {
  var ram = 0;
  var dot = false;
  try {
    ram = await const MethodChannel('voicedesk/device').invokeMethod<int>('totalRam') ?? 0;
    final cpu = File('/proc/cpuinfo');
    if (cpu.existsSync()) dot = hasDotProduct(await cpu.readAsString());
  } on Object {
    // Not a phone (or an old app shell): the lighter choice is always safe.
  }
  return PhoneClass(totalRamBytes: ram, dotProduct: dot);
});

/// The setup a recording made now gets: the settings, with Auto resolved.
final speechSetupProvider = FutureProvider<SpeechSetup>((ref) async {
  final s = await ref.watch(speechSettingsProvider.future);
  final english = switch (s.accuracy) {
    Accuracy.faster => EnglishModel.faster,
    Accuracy.accurate => EnglishModel.accurate,
    Accuracy.auto => (await ref.watch(phoneClassProvider.future)).auto,
  };
  return SpeechSetup(languages: s.languages, prefer: s.prefer, english: english, speakers: s.speakers);
});
