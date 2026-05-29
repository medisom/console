import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

typedef FullscreenDisposer = VoidCallback;

bool fullscreenIsSupportedImpl() {
  try {
    // Feature detection (typed bindings when available).
    final enabled = web.document.fullscreenEnabled;
    return enabled == true;
  } catch (_) {
    return false;
  }
}

bool fullscreenIsActiveImpl() {
  try {
    return web.document.fullscreenElement != null;
  } catch (_) {
    return false;
  }
}

Future<void> fullscreenEnterImpl() async {
  try {
    final root = web.document.documentElement;
    if (root == null) return;
    // Some browsers return a Promise; we intentionally don't await to avoid
    // depending on dart:js_util (which isn't available in all toolchains).
    root.requestFullscreen();
  } catch (e) {
    // Fullscreen requests can fail due to browser restrictions (must be user gesture).
    debugPrint('Fullscreen: requestFullscreen failed: $e');
  }
}

Future<void> fullscreenExitImpl() async {
  try {
    web.document.exitFullscreen();
  } catch (e) {
    debugPrint('Fullscreen: exitFullscreen failed: $e');
  }
}

FullscreenDisposer registerFullscreenListenerImpl({required VoidCallback onChanged}) {
  final web.EventListener listener = ((web.Event _) {
    onChanged();
  }).toJS;

  try {
    web.document.addEventListener('fullscreenchange', listener);
  } catch (e) {
    debugPrint('Fullscreen: addEventListener(fullscreenchange) failed: $e');
  }

  return () {
    try {
      web.document.removeEventListener('fullscreenchange', listener);
    } catch (e) {
      debugPrint('Fullscreen: removeEventListener(fullscreenchange) failed: $e');
    }
  };
}
