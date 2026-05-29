import 'package:flutter/material.dart';

import 'package:medisom_console/widgets/iframe_portal_view_stub.dart'
    if (dart.library.js_interop) 'package:medisom_console/widgets/iframe_portal_view_web.dart' as impl;

/// Cross-platform portal view.
///
/// - On **Web**, renders the URL inside the app using an `<iframe>`.
/// - On **non-Web**, it renders a placeholder (use WebViewWidget there).
class IFramePortalView extends StatelessWidget {
  const IFramePortalView({super.key, required this.url, this.onLoad, this.backgroundColor});

  final String url;
  final VoidCallback? onLoad;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    try {
      return impl.IFramePortalViewImpl(url: url, onLoad: onLoad, backgroundColor: backgroundColor);
    } catch (e) {
      debugPrint('IFramePortalView build failed: $e');
      return const SizedBox.shrink();
    }
  }
}
