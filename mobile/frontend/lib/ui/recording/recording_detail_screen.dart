import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:mobile_backend/data/providers.dart';
import 'package:mobile_backend/data/recording.dart';
import 'package:mobile_backend/data/transcript.dart';
import 'package:mobile_backend/engine/audio/player.dart';
import 'package:mobile_backend/engine/pipeline/processor.dart';
import 'package:mobile_backend/engine/audio/recording_notification.dart' show clock;

import '../record/recording_tile.dart' show statusBadge;
import '../theme.dart';
import '../widgets/badge.dart';
import '../wording.dart';

/// One recording: rename, play, delete. (Transcript, speakers and tasks come
/// with processing in later plans.)
class RecordingDetailScreen extends ConsumerStatefulWidget {
  const RecordingDetailScreen({super.key, required this.recordingId});

  final int recordingId;

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
    return [
      if (r.status == RecordingStatus.error) ...[
        Text(transcriptErrorText(r.error)),
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
        for (final line in lines) _line(line, at, live),
    ];
  }

  /// A line: its time, then its words — the one being spoken lit up (as on the
  /// desktop); tap a word to play from it, or the time to play the line.
  Widget _line(Phrase line, Duration at, bool live) {
    final vd = context.vd;
    final ms = at.inMilliseconds;
    bool speaking(int start, int end) => _length != null && ms >= start && ms < end;
    if (speaking(line.startMs, line.endMs)) _follow(line.startMs);
    return InkWell(
      key: _lineKeys.putIfAbsent(line.startMs, GlobalKey.new),
      onTap: live ? null : () => _jumpTo(line.startMs),
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
    final recordings = ref.watch(recordingsProvider).value ?? const <Recording>[];
    final r = recordings.where((r) => r.id == widget.recordingId).firstOrNull;
    if (r != null && r.title != _shownTitle && !_titleFocus.hasFocus) {
      _shownTitle = r.title;
      _title.text = r.title;
    }
    // Still being recorded: its audio isn't finished, so no playing or deleting yet.
    final live = r?.status == RecordingStatus.recording;
    final length = _length ?? r?.duration ?? Duration.zero;
    final at = _at > length ? length : _at;
    return Scaffold(
      appBar: AppBar(
        actions: [
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
                  ..._transcript(r, at, live),
                ],
              ),
            ),
    );
  }
}
