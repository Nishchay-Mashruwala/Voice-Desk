import 'package:flutter/material.dart';

import 'package:mobile_backend/engine/models/catalogue.dart';
import 'package:mobile_backend/engine/models/speech_model.dart';

import '../wording.dart';

/// Asks before a download; true when the model is there or is being fetched.
Future<bool> askToDownload(BuildContext context, Models models, ModelId id) async {
  if (models.isReady(id)) return true;
  final yes = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('${modelName(id)} · ${megabytes(models.bytesToDownload(id))} MB'),
      content: const Text('Wi-Fi recommended.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Download')),
      ],
    ),
  );
  if (yes != true) return false;
  models.download(id);
  return true;
}
