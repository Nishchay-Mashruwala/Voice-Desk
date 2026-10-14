import 'package:flutter/material.dart';

import '../theme.dart';

/// A page's big heading with one word in the gradient, and a muted line below
/// (the desktop's "Speak, and it writes.").
class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.lead, required this.highlight, this.tail = '', this.subtitle});

  final String lead;
  final String highlight;
  final String tail;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.headlineSmall!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            style: style,
            children: [
              TextSpan(text: lead),
              WidgetSpan(
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
                child: ShaderMask(
                  blendMode: BlendMode.srcIn,
                  shaderCallback: VdColors.grad.createShader,
                  child: Text(highlight, style: style),
                ),
              ),
              TextSpan(text: tail),
            ],
          ),
          semanticsLabel: '$lead$highlight$tail',
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(subtitle!, style: TextStyle(color: context.vd.muted)),
        ],
      ],
    );
  }
}
