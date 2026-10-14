import 'package:flutter/material.dart';

import '../theme.dart';

enum BadgeKind { neutral, accent, rec, ok, warn }

/// A small rounded label, coloured by kind (the desktop's `.badge`).
class VdBadge extends StatelessWidget {
  const VdBadge(this.text, {super.key, this.kind = BadgeKind.neutral});

  final String text;
  final BadgeKind kind;

  @override
  Widget build(BuildContext context) {
    final vd = context.vd;
    final color = switch (kind) {
      BadgeKind.neutral => vd.muted,
      BadgeKind.accent => vd.accent,
      BadgeKind.rec => VdColors.rec,
      BadgeKind.ok => VdColors.ok,
      BadgeKind.warn => VdColors.warn,
    };
    final neutral = kind == BadgeKind.neutral;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
      decoration: BoxDecoration(
        color: neutral ? vd.sunken : color.withValues(alpha: 0.1),
        border: Border.all(color: neutral ? vd.border : color.withValues(alpha: 0.25)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}
