import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import 'package:mobile_backend/data/providers.dart';
import 'package:mobile_backend/data/recording.dart';
import 'package:mobile_backend/data/recordings_repository.dart' show NoAudio;
import 'package:mobile_backend/data/speakers_repository.dart';
import 'package:mobile_backend/data/transcript.dart';
import 'package:mobile_backend/data/transcript_repository.dart';
import 'package:mobile_backend/data/transcript_text.dart';
import 'package:mobile_backend/engine/audio/player.dart';
import 'package:mobile_backend/engine/models/catalogue.dart';
import 'package:mobile_backend/engine/models/speech_model.dart';
import 'package:mobile_backend/engine/pipeline/processor.dart';
import 'package:mobile_backend/engine/speakers/grouping.dart';
import 'package:mobile_backend/engine/speakers/voice_training.dart';
import 'package:mobile_backend/engine/speech/speech_setup.dart';
import 'package:mobile_backend/engine/audio/recording_notification.dart' show clock;

import '../record/recording_tile.dart' show statusBadge;
import '../theme.dart';
import '../widgets/badge.dart';
import '../wording.dart';
import 'recording_tasks.dart';

/// Hands text to Android's share sheet (tests replace it).
final shareTextProvider = Provider<Future<void> Function(String text)>(
  (ref) => (text) async {
    await SharePlus.instance.share(ShareParams(text: text));
  },
);

/// One recording: rename, play, delete, copy or share, its summary and tasks,
/// its transcript (words light up as they are played; long-press a line to
/// fix its words; who said it above each change of speaker, tap the name to
/// rename them).
class RecordingDetailScreen extends ConsumerStatefulWidget {
  const RecordingDetailScreen({super.key, required this.recordingId, this.playFromMs});

  final int recordingId;

  /// Opened from a task's "Where it was said": plays from there.
  final int? playFromMs;

  @override
  ConsumerState<RecordingDetailScreen> createState() => _RecordingDetailScreenState();
}

class _RecordingDetailScreenState extends ConsumerState<RecordingDetailScreen> {
  final _title = TextEditingController();
  final _titleFocus = FocusNode();
  String? _shownTitle;
  Duration? _length;
  Duration _at = Duration.zero;
  bool _playing = false;

  /// Each transcript line (by its start), to scroll the playing word into view.
  final _lineKeys = <int, GlobalKey>{};
  int? _followed;

  /// Keeps the player alive while this screen is open (the provider is
  /// autoDispose: a plain read would let it be disposed right away).
  late final ProviderSubscription<Player> _player;

  @override
  void initState() {
    super.initState();
    _titleFocus.addListener(() {
      if (!_titleFocus.hasFocus) _rename();
    });
    _player = ref.listenManual(playerProvider, (_, _) {});
    final player = _player.read();
    player.position.listen((p) => mounted ? setState(() => _at = p) : null);
    player.playing.listen((p) => mounted ? setState(() => _playing = p) : null);
    if (widget.playFromMs case final ms?) WidgetsBinding.instance.addPostFrameCallback((_) => _playFrom(ms));
  }

  /// Plays from [ms] once the recording is known, if its audio is still here.
  Future<void> _playFrom(int ms) async {
    final all = await ref.read(recordingsProvider.future);
    final r = all.where((r) => r.id == widget.recordingId).firstOrNull;
    if (!mounted || r == null || r.audioDeleted || r.status == RecordingStatus.recording) return;
    await _jumpTo(ms);
  }

  @override
  void dispose() {
    _title.dispose();
    _titleFocus.dispose();
    super.dispose();
  }

  /// The title last sent to be saved (Done and losing focus both save).
  String? _saved;

  void _rename() {
    final text = _title.text;
    if (text == _shownTitle || text == _saved) return;
    _saved = text;
    ref.read(recordingsRepositoryProvider).rename(widget.recordingId, text);
  }

  Future<void> _playPause() async {
    final player = _player.read();
    if (_playing) return player.pause();
    if (_length == null) {
      final length = await player.load(await ref.read(recordingsRepositoryProvider).pieces(widget.recordingId));
      setState(() => _length = length);
    }
    await player.play();
  }

  /// Plays from a line (loading the audio first if needed).
  Future<void> _jumpTo(int ms) async {
    final player = _player.read();
    if (_length == null) {
      final length = await player.load(await ref.read(recordingsRepositoryProvider).pieces(widget.recordingId));
      setState(() => _length = length);
    }
    await player.seek(Duration(milliseconds: ms));
    if (!_playing) await player.play();
  }

  /// The transcript (lines with their times; the one playing in the accent
  /// colour), or why there is none.
  List<Widget> _transcript(Recording r, Duration at, bool live) {
    final vd = context.vd;
    final lines = ref.watch(transcriptProvider(widget.recordingId)).value ?? const <Phrase>[];
    Widget note(String text) => Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: vd.border),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(color: vd.muted),
      ),
    );
    final editable = r.status == RecordingStatus.done || r.status == RecordingStatus.error;
    // Kept up to date for renaming (how much speech each speaker had) and Said by….
    ref.watch(speakerGroupsProvider(widget.recordingId));
    ref.watch(peopleProvider);
    ref.watch(myVoiceProvider);
    return [
      if (r.compressFailed &&
          !r.audioDeleted &&
          !r.reprocessing &&
          (r.status == RecordingStatus.done || r.status == RecordingStatus.error)) ...[
        Text("Couldn't compress this recording's audio; it's kept as it was", style: TextStyle(color: vd.muted)),
        const SizedBox(height: 12),
      ],
      if (r.status == RecordingStatus.done && r.error == 'speakers_failed') ...[
        Text("Couldn't tell who said what in this recording.", style: TextStyle(color: vd.muted)),
        Align(
          alignment: Alignment.centerLeft,
          // Only the speakers step runs again: the text and its fixes stay.
          child: TextButton(
            onPressed: () => ref.read(processorProvider.notifier).retry(r.id),
            child: const Text('Try again'),
          ),
        ),
        const SizedBox(height: 4),
      ],
      if (r.status == RecordingStatus.error) ...[
        Text(
          r.reprocessing
              ? "Processing it again didn't finish. The text below is the earlier one; "
                  'Try again continues where it stopped.'
              : transcriptErrorText(r.error),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            onPressed: () => ref.read(processorProvider.notifier).retry(r.id),
            child: const Text('Try again'),
          ),
        ),
        const SizedBox(height: 16),
      ],
      if (lines.isEmpty && r.status == RecordingStatus.done)
        note('No speech found in this recording.')
      else if (lines.isEmpty && r.status != RecordingStatus.error)
        note('The transcript appears here as the recording is turned into text.')
      else
        for (final (i, line) in lines.indexed) ...[
          if (line.speaker != null && (i == 0 || lines[i - 1].speaker != line.speaker)) _speaker(line, editable),
          _line(line, at, live, editable),
        ],
    ];
  }

  /// Who said the lines from here on (bold, in the accent colour); tap it to rename them.
  Widget _speaker(Phrase line, bool editable) => Align(
    alignment: Alignment.centerLeft,
    child: InkWell(
      onTap: editable ? () => _renameSpeaker(line) : null,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 10, 8, 2),
        child: Text(
          line.speaker!,
          style: TextStyle(fontWeight: FontWeight.w700, color: context.vd.accent),
        ),
      ),
    ),
  );

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    _say('Copied to clipboard');
  }

  /// The header's Share menu: the whole transcript, copied or shared as text.
  Widget _shareMenu(Recording r, List<Phrase> lines) => PopupMenuButton<String>(
    key: const Key('share-button'),
    tooltip: 'Share',
    icon: const Icon(Icons.share_outlined),
    onSelected: (choice) async {
      final text = transcriptText(r, lines);
      if (choice == 'copy') return _copy(text);
      await ref.read(shareTextProvider)(text);
    },
    itemBuilder: (_) => const [
      PopupMenuItem(value: 'copy', child: Text('Copy transcript')),
      PopupMenuItem(value: 'share', child: Text('Share…')),
    ],
  );

  void _say(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  /// Renames a speaker of this recording (all their lines), and remembers their voice if asked.
  Future<void> _renameSpeaker(Phrase line) async {
    if (line.speaker == kMeLabel) return _say("Your own lines can't be renamed");
    final groups = ref.read(speakerGroupsProvider(widget.recordingId)).value ?? const <SpeakerGroup>[];
    final group = groups.where((g) => g.id == line.speakerGroup).firstOrNull;
    if (group == null) return;
    final answer = await showModalBottomSheet<(String, bool)>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _RenameSheet(group),
    );
    if (answer == null) return;
    final (name, remember) = answer;
    final speakers = ref.read(speakersRepositoryProvider);
    try {
      try {
        await speakers.rename(widget.recordingId, group.id, name, remember: remember);
        _say(remember ? "Renamed — $name's voice will be recognised in future recordings" : 'Renamed to $name');
      } on NotEnoughSpeech {
        // Their lines were moved to others since: the name still changes.
        await speakers.rename(widget.recordingId, group.id, name, remember: false);
        _say('Renamed to $name. Not enough of their speech to remember the voice (needs 2 s or more)');
      }
    } on CantRenameMe {
      _say("Your own lines can't be renamed");
    } on RecordingGone {
      _say('That recording is no longer there');
    }
  }

  /// What can be done with a line (long-press).
  Future<void> _lineMenu(Phrase line) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Fix the words'),
              onTap: () => Navigator.pop(context, 'fix'),
            ),
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const Text('Copy this line'),
              onTap: () => Navigator.pop(context, 'copy'),
            ),
            if (line.speaker != null)
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: const Text('Said by…'),
                onTap: () => Navigator.pop(context, 'said'),
              ),
          ],
        ),
      ),
    );
    if (choice == 'fix') await _fixWords(line);
    if (choice == 'said') await _saidBy(line);
    if (choice == 'copy') await _copy(line.text);
  }

  /// "Said by…": only this line goes to Me, one of this recording's speakers,
  /// a remembered person or someone else; no voice is learned from it.
  Future<void> _saidBy(Phrase line) async {
    final groups = ref.read(speakerGroupsProvider(widget.recordingId)).value ?? const <SpeakerGroup>[];
    final people = ref.read(peopleProvider).value ?? const [];
    final trained = ref.read(myVoiceProvider).value?.$1 != null;
    SpeakerGroup? named(String label) =>
        groups.where((g) => g.label.toLowerCase() == label.toLowerCase()).firstOrNull;
    final choices = <(int?, String)>[
      if (trained || named(kMeLabel) != null) (named(kMeLabel)?.id, kMeLabel),
      for (final g in groups)
        if (g.label != kMeLabel) (g.id, g.label),
      for (final p in people)
        if (named(p.name) == null) (null, p.name),
    ];
    final choice = await showModalBottomSheet<(int?, String)?>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final c in choices)
                ListTile(
                  title: Text(c.$2),
                  trailing: c.$2 == line.speaker ? const Icon(Icons.check) : null,
                  onTap: () => Navigator.pop(context, c),
                ),
              ListTile(
                leading: const Icon(Icons.person_add_alt),
                title: const Text('Someone else…'),
                onTap: () => Navigator.pop(context, (null, '')),
              ),
            ],
          ),
        ),
      ),
    );
    if (choice == null || !mounted) return;
    var (groupId, label) = choice;
    if (label.isEmpty) {
      final name = await showDialog<String>(context: context, builder: (_) => const _SomeoneElseDialog());
      if (name == null) return;
      // One of this recording's speakers: their group, spelled as they are.
      groupId = named(name)?.id;
      label = named(name)?.label ?? name;
    }
    if (label == line.speaker && groupId == line.speakerGroup) return;
    try {
      await ref.read(speakersRepositoryProvider).moveLine(line.id!, groupId: groupId, label: label);
    } on LineGone {
      _say('That line is no longer there');
    }
  }

  /// The line's text to correct; saved as typed (words that stay keep their times).
  Future<void> _fixWords(Phrase line) async {
    final fixed = await showDialog<String>(context: context, builder: (_) => _FixWordsDialog(line.text));
    if (fixed == null || fixed.trim() == line.text) return;
    try {
      await ref.read(transcriptRepositoryProvider).editLine(line.id!, fixed);
    } on LineGone {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('That line is no longer there')));
    } on ArgumentError {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("A line can't be empty")));
    }
  }

  /// A line: its time, then its words — the one being spoken lit up (as on the
  /// desktop); tap a word to play from it, or the time to play the line; long-
  /// press it to fix its words ([editable]: the recording is done or failed).
  Widget _line(Phrase line, Duration at, bool live, bool editable) {
    final vd = context.vd;
    final ms = at.inMilliseconds;
    bool speaking(int start, int end) => _length != null && ms >= start && ms < end;
    if (speaking(line.startMs, line.endMs)) _follow(line.startMs);
    return InkWell(
      key: _lineKeys.putIfAbsent(line.startMs, GlobalKey.new),
      onTap: live ? null : () => _jumpTo(line.startMs),
      onLongPress: editable && line.id != null ? () => _lineMenu(line) : null,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 52,
              child: Text(
                clock(Duration(milliseconds: line.startMs)),
                style: TextStyle(color: vd.faint, fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ),
            Expanded(
              child: line.words.isEmpty
                  ? Text(line.text, style: TextStyle(color: speaking(line.startMs, line.endMs) ? vd.accent : null))
                  : Wrap(
                      spacing: 2,
                      runSpacing: 2,
                      children: [
                        for (final w in line.words)
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: live ? null : () => _jumpTo(w.startMs),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 2),
                              decoration: speaking(w.startMs, w.endMs)
                                  ? BoxDecoration(
                                      color: vd.accent.withValues(alpha: 0.18),
                                      borderRadius: BorderRadius.circular(4),
                                    )
                                  : null,
                              child: Text(
                                w.text,
                                style: TextStyle(color: speaking(w.startMs, w.endMs) ? vd.accent : null),
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// Keeps the line being played on screen (once per line, after this frame).
  void _follow(int lineStart) {
    if (_followed == lineStart) return;
    _followed = lineStart;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _lineKeys[lineStart]?.currentContext;
      if (target != null && target.mounted) {
        Scrollable.ensureVisible(target, alignment: 0.35, duration: const Duration(milliseconds: 250));
      }
    });
  }

  /// Turns the recording into text again, with the accuracy and languages chosen.
  Future<void> _processAgain(Recording r) async {
    final setup = await showDialog<SpeechSetup>(context: context, builder: (_) => _ProcessAgainDialog(r));
    if (setup == null) return;
    try {
      await ref.read(processorProvider.notifier).processAgain(r.id, setup);
    } on NoAudio {
      // "Keep recordings for" deleted it while the dialog was open.
      _say('The audio for this recording is no longer available.');
    }
  }

  /// Its pieces became one FLAC while loaded: the player loads that, at the same place.
  Future<void> _reloadAudio() async {
    final player = _player.read();
    final at = _at;
    final wasPlaying = _playing;
    if (wasPlaying) await player.pause();
    final length = await player.load(await ref.read(recordingsRepositoryProvider).pieces(widget.recordingId));
    if (!mounted) return;
    setState(() => _length = length);
    await player.seek(at);
    if (wasPlaying) await player.play();
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this recording?'),
        content: const Text('Its audio is removed from the phone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(recordingsRepositoryProvider).delete(widget.recordingId);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(recordingsProvider, (before, now) {
      String? audio(AsyncValue<List<Recording>>? v) =>
          v?.value?.where((r) => r.id == widget.recordingId).firstOrNull?.audioPath;
      if (_length != null && audio(now) != null && audio(now) != audio(before)) _reloadAudio();
    });
    final recordings = ref.watch(recordingsProvider).value ?? const <Recording>[];
    final r = recordings.where((r) => r.id == widget.recordingId).firstOrNull;
    if (r != null && r.title != _shownTitle && !_titleFocus.hasFocus) {
      _shownTitle = r.title;
      _title.text = r.title;
    }
    // Still being recorded: its audio isn't finished, so no playing or deleting yet.
    final live = r?.status == RecordingStatus.recording;
    // Its audio deleted by "Keep recordings for": the text only.
    final textOnly = r?.audioDeleted ?? false;
    final length = _length ?? r?.duration ?? Duration.zero;
    final at = _at > length ? length : _at;
    final lines = ref.watch(transcriptProvider(widget.recordingId)).value ?? const <Phrase>[];
    return Scaffold(
      appBar: AppBar(
        actions: [
          if (r != null && lines.isNotEmpty) _shareMenu(r, lines),
          IconButton(
            key: const Key('process-again'),
            tooltip: 'Process again',
            icon: const Icon(Icons.refresh),
            // Finished, failed, or waiting (e.g. for a model chosen for it): not
            // while it is being recorded or processed.
            onPressed: r != null &&
                    !textOnly &&
                    const {RecordingStatus.done, RecordingStatus.error, RecordingStatus.queued, RecordingStatus.waitingCharge}
                        .contains(r.status) &&
                    ref.watch(processorProvider).recordingId != r.id
                ? () => _processAgain(r)
                : null,
          ),
          IconButton(
            key: const Key('delete-button'),
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline),
            onPressed: live ? null : _delete,
          ),
        ],
      ),
      body: r == null
          ? const SizedBox.shrink()
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    key: const Key('title-edit'),
                    controller: _title,
                    focusNode: _titleFocus,
                    textInputAction: TextInputAction.done,
                    style: Theme.of(context).textTheme.titleLarge,
                    // A heading you can edit, not a form box: the theme's filled,
                    // outlined fields (enabledBorder wins over border) are turned off.
                    decoration: const InputDecoration(
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 4),
                    ),
                    onSubmitted: (_) => _rename(),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          DateFormat('dd MMM yyyy, HH:mm').format(r.startedAt),
                          style: TextStyle(color: context.vd.muted),
                        ),
                      ),
                      VdBadge(recordingBadgeText(r), kind: statusBadge(r.status)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (textOnly)
                    Text('The audio for this recording is no longer available.', style: TextStyle(color: context.vd.muted))
                  else
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        child: Row(
                          children: [
                            IconButton.filled(
                              key: const Key('play-button'),
                              icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                              onPressed: live ? null : _playPause,
                            ),
                            Expanded(
                              child: Slider(
                                value: length.inMilliseconds == 0 ? 0 : at.inMilliseconds / length.inMilliseconds,
                                onChanged: _length == null
                                    ? null
                                    : (v) => _player.read().seek(
                                        Duration(milliseconds: (v * length.inMilliseconds).round()),
                                      ),
                              ),
                            ),
                            Text('${clock(at)} / ${clock(length)}'),
                            const SizedBox(width: 8),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  RecordingTasks(
                    recording: r,
                    lines: lines,
                    onWhere: (t) => textOnly ? null : _jumpTo(t.quoteMs ?? 0),
                  ),
                  ..._transcript(r, at, live || textOnly),
                ],
              ),
            ),
    );
  }
}

/// "Rename Person 1 to": their name, and whether to recognise their voice
/// later (offered when there is enough of their speech).
class _RenameSheet extends StatefulWidget {
  const _RenameSheet(this.group);
  final SpeakerGroup group;

  @override
  State<_RenameSheet> createState() => _RenameSheetState();
}

class _RenameSheetState extends State<_RenameSheet> {
  late final _name = TextEditingController(text: widget.group.label.startsWith('Person ') ? '' : widget.group.label);
  late final bool _canRemember = widget.group.speechMs >= kRememberMinMs;
  late bool _remember = _canRemember;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _done() {
    final name = _name.text.trim();
    if (name.isEmpty || name.toLowerCase() == kMeLabel.toLowerCase()) return setState(() => _error = 'Type a name');
    Navigator.pop(context, (name, _remember));
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Rename ${widget.group.label} to', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        TextField(
          key: const Key('speaker-name'),
          controller: _name,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(hintText: 'Their name', errorText: _error),
          onSubmitted: (_) => _done(),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _remember,
          onChanged: _canRemember ? (v) => setState(() => _remember = v ?? false) : null,
          title: const Text('Recognise this voice in future recordings'),
          subtitle: Text(
            _canRemember
                ? 'Saved on this phone only'
                : 'Not enough of their speech to remember the voice (needs 2 s or more)',
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            const SizedBox(width: 8),
            FilledButton(onPressed: _done, child: const Text('Rename')),
          ],
        ),
      ],
    ),
  );
}

/// "Said by… → Someone else…": their name ("Type a name" when empty).
class _SomeoneElseDialog extends StatefulWidget {
  const _SomeoneElseDialog();

  @override
  State<_SomeoneElseDialog> createState() => _SomeoneElseDialogState();
}

class _SomeoneElseDialogState extends State<_SomeoneElseDialog> {
  final _name = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _done() {
    final name = _name.text.trim();
    if (name.isEmpty) return setState(() => _error = 'Type a name');
    Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Said by'),
    content: TextField(
      key: const Key('said-by-name'),
      controller: _name,
      autofocus: true,
      textCapitalization: TextCapitalization.words,
      decoration: InputDecoration(hintText: 'Their name', errorText: _error),
      onSubmitted: (_) => _done(),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: _done, child: const Text('Save')),
    ],
  );
}

/// "Fix the words": the line's text in a box; Save while it isn't empty.
class _FixWordsDialog extends StatefulWidget {
  const _FixWordsDialog(this.text);
  final String text;

  @override
  State<_FixWordsDialog> createState() => _FixWordsDialogState();
}

class _FixWordsDialogState extends State<_FixWordsDialog> {
  late final _text = TextEditingController(text: widget.text);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Fix the words'),
    content: TextField(
      key: const Key('line-edit'),
      controller: _text,
      autofocus: true,
      minLines: 1,
      maxLines: 5,
      onChanged: (_) => setState(() {}),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(
        onPressed: _text.text.trim().isEmpty ? null : () => Navigator.pop(context, _text.text),
        child: const Text('Save'),
      ),
    ],
  );
}

/// "Process again": this run's accuracy and languages (the name, other names,
/// vocabulary and Leave out are the settings' own).
class _ProcessAgainDialog extends ConsumerStatefulWidget {
  const _ProcessAgainDialog(this.recording);
  final Recording recording;

  @override
  ConsumerState<_ProcessAgainDialog> createState() => _ProcessAgainDialogState();
}

class _ProcessAgainDialogState extends ConsumerState<_ProcessAgainDialog> {
  var _english = EnglishModel.accurate;
  late final _languages = {...widget.recording.setup.languages};

  SpeechSetup get _setup => SpeechSetup(
        languages: {..._languages},
        prefer: widget.recording.setup.prefer,
        english: _english,
        // Who said what as the settings say now.
        speakers: ref.read(speechSettingsProvider).value?.speakers ?? true,
      );

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(color: context.vd.muted);
    ref.watch(modelsProvider);
    final models = ref.read(modelsProvider.notifier);
    // What the chosen run needs that isn't on the phone (it waits for it).
    final missing = [for (final id in _setup.models) if (!models.isReady(id)) kCatalogue[id]!.download.size];
    final toDownload = missing.fold(0, (a, b) => a + b);
    return AlertDialog(
      title: Text('Process “${widget.recording.title}” again?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'The same audio with the same settings gives the same words. '
              'To try for better ones, choose another accuracy or languages.',
              style: muted,
            ),
            const SizedBox(height: 16),
            SegmentedButton<EnglishModel>(
              segments: const [
                ButtonSegment(value: EnglishModel.faster, label: Text('Faster')),
                ButtonSegment(value: EnglishModel.accurate, label: Text('More accurate')),
              ],
              selected: {_english},
              // Only the English reader has a choice of model.
              onSelectionChanged: _languages.contains(Lang.en) ? (s) => setState(() => _english = s.single) : null,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final l in Lang.values)
                  FilterChip(
                    label: Text(languageName(l)),
                    selected: _languages.contains(l),
                    onSelected: (on) => setState(() {
                      if (on) {
                        _languages.add(l);
                      } else if (_languages.length > 1) {
                        _languages.remove(l);
                      }
                    }),
                  ),
              ],
            ),
            if (toDownload > 0) ...[
              const SizedBox(height: 12),
              Text('Downloads ${megabytes(toDownload)} MB first.'),
            ],
            const SizedBox(height: 12),
            Text('Your fixes to its lines will be replaced.', style: muted),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(context, _setup),
          child: const Text('Process again'),
        ),
      ],
    );
  }
}
