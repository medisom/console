import 'package:flutter/foundation.dart';

import 'package:medisom_console/utils/fullscreen_controller_stub.dart'
    if (dart.library.js_interop) 'package:medisom_console/utils/fullscreen_controller_web.dart';

/// Controls browser fullscreen mode.
///
/// - On Web: uses the Fullscreen API (documentElement.requestFullscreen).
/// - On non-Web: no-op (unsupported).
class FullscreenController extends ChangeNotifier {
  VoidCallback? _disposeListener;
  bool _initialized = false;

  bool get isSupported => fullscreenIsSupportedImpl();

  bool get isFullscreen => fullscreenIsActiveImpl();

  void initialize() {
    if (_initialized) return;
    _initialized = true;
    if (!isSupported) return;

    _disposeListener = registerFullscreenListenerImpl(onChanged: () {
      notifyListeners();
    });
  }

  Future<void> toggle() async {
    if (!isSupported) return;
    if (isFullscreen) {
      await fullscreenExitImpl();
    } else {
      await fullscreenEnterImpl();
    }
    // Even if fullscreenchange doesn't fire (rare), force a refresh.
    notifyListeners();
  }

  @override
  void dispose() {
    _disposeListener?.call();
    _disposeListener = null;
    super.dispose();
  }
}
