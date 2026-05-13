import 'package:flutter/foundation.dart';

import 'package:medisom_console/utils/portal_launcher_stub.dart'
    if (dart.library.js_interop) 'package:medisom_console/utils/portal_launcher_web.dart' as impl;

/// Opens a URL in a way that mimics `location.replace(...)` on Web.
///
/// - **Web**: uses `window.location.replace(url)` (replaces current page).
/// - **Mobile/Desktop**: opens the system browser (external application).
Future<void> openPortalReplace(String url) async {
  try {
    await impl.openPortalReplace(url);
  } catch (e) {
    debugPrint('openPortalReplace failed: $e');
    rethrow;
  }
}
