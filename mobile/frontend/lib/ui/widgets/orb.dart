import 'package:flutter/material.dart';

import '../theme.dart';

enum OrbState { idle, recording, paused }

/// The desktop's round microphone button: purple gradient with a glow; red with
/// rings spreading out while recording (its inner circle follows the voice);
/// amber while paused.
class Orb extends StatefulWidget {
  const Orb({super.key, required this.state, required this.onPressed, this.level = 0, this.size = 116});

  final OrbState state;
  final VoidCallback onPressed;

  /// Loudness, 0..1.
  final double level;
  final double size;

  @override
  State<Orb> createState() => _OrbState();
}

class _OrbState extends State<Orb> with SingleTickerProviderStateMixin {
  late final _rings = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200));

  /// The phone's "remove animations" setting: no moving rings.
  bool _still = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _sync();
  }

  @override
  void didUpdateWidget(Orb old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.state == OrbState.recording && !_still) {
      if (!_rings.isAnimating) _rings.repeat();
    } else {
      _rings.stop();
    }
  }

  @override
  void dispose() {
    _rings.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (gradient, glow) = switch (widget.state) {
      OrbState.idle => (VdColors.grad, VdColors.glow),
      OrbState.recording => (VdColors.gradRec, VdColors.rec),
      OrbState.paused => (VdColors.gradPaused, VdColors.warn),
    };
    final active = widget.state != OrbState.idle;
    final size = widget.size;
    return Semantics(
      button: true,
      label: active ? 'Stop' : 'Record',
      excludeSemantics: true,
      child: SizedBox(
        width: size * 1.7,
        height: size * 1.7,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (widget.state == OrbState.recording && !_still)
              for (final delay in const [0.0, 0.5])
                AnimatedBuilder(
                  animation: _rings,
                  builder: (context, _) {
                    final t = (_rings.value + delay) % 1;
                    return Container(
                      width: size * (1 + 0.65 * Curves.easeOutQuint.transform(t)),
                      height: size * (1 + 0.65 * Curves.easeOutQuint.transform(t)),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: glow.withValues(alpha: 0.5 * (1 - t)), width: 2),
                      ),
                    );
                  },
                ),
            GestureDetector(
              onTap: widget.onPressed,
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: gradient,
                  boxShadow: [
                    BoxShadow(color: glow.withValues(alpha: 0.45), blurRadius: 36, offset: const Offset(0, 12)),
                  ],
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (active)
                      AnimatedScale(
                        scale: 0.85 + 0.15 * widget.level.clamp(0, 1),
                        duration: const Duration(milliseconds: 80),
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.16),
                          ),
                        ),
                      ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(active ? Icons.stop_rounded : Icons.mic, size: 40, color: Colors.white),
                        Text(
                          active ? 'Stop' : 'Record',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
