import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:mobile_backend/data/recording.dart';
import 'package:mobile_backend/engine/audio/recording_notification.dart' show clock;

import '../theme.dart';
import '../widgets/badge.dart';
import '../wording.dart';

/// One recording in the list, as a card: title, when and how long, and its status.
class RecordingTile extends StatelessWidget {
  const RecordingTile({super.key, required this.recording, this.onTap});

  final Recording recording;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final r = recording;
    final when = DateFormat('dd MMM, HH:mm').format(r.startedAt);
    final vd = context.vd;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            children: [
              Icon(r.kind == 'call' ? Icons.call : Icons.graphic_eq, color: vd.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      r.duration == null ? when : '$when · ${clock(r.duration!)}',
                      style: TextStyle(fontSize: 12.5, color: vd.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              VdBadge(recordingBadgeText(r), kind: statusBadge(r.status)),
            ],
          ),
        ),
      ),
    );
  }
}

/// The badge colour for each status, as the desktop's badges.
BadgeKind statusBadge(RecordingStatus s) => switch (s) {
  RecordingStatus.recording => BadgeKind.rec,
  RecordingStatus.queued => BadgeKind.neutral,
  RecordingStatus.processing => BadgeKind.accent,
  RecordingStatus.waitingCharge => BadgeKind.warn,
  RecordingStatus.done => BadgeKind.ok,
  RecordingStatus.error => BadgeKind.rec,
};
