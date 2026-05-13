import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:medisom_console/theme.dart';
import 'package:medisom_console/widgets/brand_logo.dart';
import 'package:medisom_console/widgets/glass_panel.dart';

class ResponsiveAuthScaffold extends StatelessWidget {
  const ResponsiveAuthScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.footer,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [cs.primaryContainer, cs.surface, cs.surface],
            stops: const [0.0, 0.55, 1.0],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 980;
              final panelMax = math.min(520.0, constraints.maxWidth);
              final padding = isWide ? AppSpacing.paddingXl : AppSpacing.paddingLg;

              return Center(
                child: SingleChildScrollView(
                  padding: padding,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: isWide ? 980 : panelMax),
                    child: isWide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: _HeroBlock(title: title, subtitle: subtitle)),
                              const SizedBox(width: AppSpacing.xl),
                              SizedBox(
                                width: 520,
                                child: GlassPanel(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [child, if (footer != null) ...[const SizedBox(height: AppSpacing.lg), footer!]],
                                  ),
                                ),
                              ),
                            ],
                          )
                        : GlassPanel(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _HeroBlock(title: title, subtitle: subtitle, compact: true),
                                const SizedBox(height: AppSpacing.lg),
                                child,
                                if (footer != null) ...[const SizedBox(height: AppSpacing.lg), footer!],
                              ],
                            ),
                          ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _HeroBlock extends StatelessWidget {
  const _HeroBlock({required this.title, required this.subtitle, this.compact = false});
  final String title;
  final String subtitle;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final titleStyle = context.textStyles.headlineMedium?.copyWith(height: 1.08);
    final subStyle = context.textStyles.bodyLarge?.copyWith(color: cs.onSurfaceVariant, height: 1.4);
    final hasSubtitle = subtitle.trim().isNotEmpty;

    return Padding(
      padding: compact ? EdgeInsets.zero : const EdgeInsets.only(top: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BrandLogo(size: compact ? 64 : 80),
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: cs.primary.withValues(alpha: 0.18)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const BrandLogo(size: 18),
                const SizedBox(width: 8),
                Text('Controle de ruído', style: context.textStyles.labelLarge?.copyWith(color: cs.primary)),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(title, style: titleStyle),
          if (hasSubtitle) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(subtitle, style: subStyle),
          ],
        ],
      ),
    );
  }
}
