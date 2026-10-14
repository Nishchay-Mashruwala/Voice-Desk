import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../audio/recording_notification.dart';

/// The "Processing · 40% · about 3 min left" notification, which also keeps
/// the app running while it works.
abstract class ProcessingNotice {
  Future<void> show(String title, double progress, Duration? left);

  /// Waiting to go on ([why]: `charge` or `cool`). Stays up so the app keeps
  /// running and continues by itself when the phone is plugged in or cools.
  Future<void> showWaiting(String title, String why);
  Future<void> hide();
}

/// Shares the one foreground service with the recording notification.
final processingNoticeProvider = Provider<ProcessingNotice>((ref) => ref.watch(foregroundServiceProvider).processing);
