import 'package:flutter/material.dart';

import 'package:medisom_console/theme.dart';

/// Simple modern panel used across auth pages.
class GlassPanel extends StatelessWidget {
  const GlassPanel({super.key, required this.child, this.padding});
  final Widget child;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: padding ?? AppSpacing.paddingLg,
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: cs.outline.withValues(alpha: 0.16)),
      ),
      child: child,
    );
  }
}
