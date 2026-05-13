import 'package:flutter/material.dart';
import 'package:medisom_console/pages/dashboard_page.dart';
import 'package:medisom_console/pages/portal_stack_page.dart';
import 'package:medisom_console/utils/open_portals_controller.dart';
import 'package:provider/provider.dart';

/// Root for the "Dispositivos" tab.
///
/// It contains:
/// - Dashboard (sensor list)
/// - Portal stack (one WebView per opened sensor)
///
/// Both are kept alive using an [IndexedStack] so switching back and forth does
/// not destroy the opened WebViews.
class DevicesRootPage extends StatelessWidget {
  const DevicesRootPage({super.key});

  @override
  Widget build(BuildContext context) {
    final hasActivePortal = context.select<OpenPortalsController, bool>((c) => c.hasActivePortal);
    return IndexedStack(index: hasActivePortal ? 1 : 0, children: const [DashboardPage(), PortalStackPage()]);
  }
}
