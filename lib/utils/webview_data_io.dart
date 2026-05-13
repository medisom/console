import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Clears shared WebView cookies/session data.
///
/// This helps avoid leaking authenticated web sessions between different
/// app accounts when the app uses WebViews for authenticated portals.
Future<void> clearWebViewData() async {
  try {
    final cleared = await WebViewCookieManager().clearCookies();
    debugPrint('clearWebViewData: cookiesCleared=$cleared');
  } catch (e) {
    debugPrint('clearWebViewData failed: $e');
  }
}
