import 'package:flutter/material.dart';
import 'package:medisom_console/pages/cached_portal_view.dart';
import 'package:medisom_console/theme.dart';
import 'package:medisom_console/utils/open_portals_controller.dart';
import 'package:provider/provider.dart';

/// Hosts multiple portals (one per sensor) and keeps them alive.
///
/// This uses an [IndexedStack] so previously opened WebViews remain mounted in
/// the background and can be re-shown instantly.
class PortalStackPage extends StatelessWidget {
  const PortalStackPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final controller = context.watch<OpenPortalsController>();
    final opened = controller.opened;
    final activeId = controller.activeSensorId;

    // IMPORTANT: Never drop already-opened portals from the widget tree.
    // If we remove the [CachedPortalView] widgets (e.g., when activeId == null),
    // the WebViews get disposed and will reload from zero next time.
    if (opened.isEmpty) {
      return Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Padding(
              padding: AppSpacing.paddingLg,
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.public, color: cs.onSurfaceVariant, size: 40),
                    const SizedBox(height: AppSpacing.md),
                    Text('Nenhum sensor aberto', style: context.textStyles.titleMedium, textAlign: TextAlign.center),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Abra um sensor pela lista de dispositivos para visualizar o portal.',
                      style: context.textStyles.bodyMedium?.copyWith(color: cs.onSurfaceVariant, height: 1.45),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    final activeIndex = (activeId == null) ? 0 : opened.indexWhere((e) => e.sensorId == activeId);
    return IndexedStack(
      index: activeIndex < 0 ? 0 : activeIndex,
      children: [
        for (final entry in opened)
          CachedPortalView(
            key: ValueKey('portal:${entry.sensorId}'),
            sensorId: entry.sensorId,
            url: entry.url,
            title: entry.title,
            // When the portal requests to close (back button, error state,
            // or JS -> `Nativo.postMessage('fecharWebView')`), remove it from
            // the cache and return to Dashboard.
            onRequestClose: () => context.read<OpenPortalsController>().closePortal(entry.sensorId),
          ),
      ],
    );
  }
}
