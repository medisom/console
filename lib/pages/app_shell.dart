import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:medisom_console/theme.dart';
import 'package:medisom_console/utils/fullscreen_controller.dart';
import 'package:medisom_console/utils/open_portals_controller.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final currentIndex = navigationShell.currentIndex;
    final fullscreen = context.watch<FullscreenController>();

    final navBarTheme = NavigationBarThemeData(
      indicatorColor: cs.primaryContainer.withValues(alpha: 0.65),
      backgroundColor: cs.surface,
      // Keep the footer more compact (roughly 30% shorter than before).
      height: 54,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return IconThemeData(color: cs.primary, size: 24);
        }
        return IconThemeData(color: cs.onSurfaceVariant.withValues(alpha: 0.9), size: 24);
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final base = Theme.of(context).textTheme.labelMedium ?? const TextStyle(fontSize: 12);
        if (states.contains(WidgetState.selected)) {
          return base.copyWith(color: cs.primary, fontWeight: FontWeight.w600);
        }
        return base.copyWith(color: cs.onSurfaceVariant.withValues(alpha: 0.9), fontWeight: FontWeight.w500);
      }),
    );

    return Scaffold(
      body: navigationShell,
      floatingActionButton: fullscreen.isSupported
          ? Theme(
              data: Theme.of(context).copyWith(
                splashFactory: NoSplash.splashFactory,
                highlightColor: Colors.transparent,
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) => ScaleTransition(
                  scale: Tween<double>(begin: 0.92, end: 1).animate(animation),
                  child: FadeTransition(opacity: animation, child: child),
                ),
                child: FloatingActionButton(
                  key: ValueKey(fullscreen.isFullscreen),
                  tooltip: fullscreen.isFullscreen ? 'Sair da tela cheia' : 'Tela cheia',
                  onPressed: fullscreen.toggle,
                  backgroundColor: cs.primary,
                  foregroundColor: cs.onPrimary,
                  elevation: 0,
                  child: Icon(fullscreen.isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen),
                ),
              ),
            )
          : null,
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: cs.surface,
          border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.35))),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.sm, 4, AppSpacing.sm, 4),
            child: NavigationBarTheme(
              data: navBarTheme,
              child: NavigationBar(
                selectedIndex: currentIndex,
                onDestinationSelected: (index) {
                  // Important behavior:
                  // - Tapping "Dispositivos" should ALWAYS show the sensor list (Dashboard),
                  //   even if a WebView portal is currently active.
                  // - Switching tabs should not accidentally resurrect a portal view.
                  switch (index) {
                    case 0:
                      context.read<OpenPortalsController>().showDashboard();
                      navigationShell.goBranch(0, initialLocation: true);
                      return;
                    case 1:
                      navigationShell.goBranch(1, initialLocation: true);
                      return;
                    case 2:
                      navigationShell.goBranch(2, initialLocation: true);
                      return;
                  }
                },
                destinations: const [
                  NavigationDestination(icon: Icon(Icons.devices_other), label: 'Dispositivos'),
                  NavigationDestination(icon: Icon(Icons.analytics_outlined), label: 'Medições'),
                  NavigationDestination(icon: Icon(Icons.manage_accounts_outlined), label: 'Conta'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
