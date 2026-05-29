import 'dart:js_interop';
import 'dart:js_util' as js_util;

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

typedef FullscreenDisposer = VoidCallback;

bool fullscreenIsSupportedImpl() {
  try {
    // Prefer feature detection via JS properties.
    final enabled = js_util.getProperty<Object?>(web.document, 'fullscreenEnabled');
    if (enabled is bool) return enabled;
    if (enabled == null) return false;
    return enabled.toString() == 'true';
  } catch (_) {
    return false;
  }
}

bool fullscreenIsActiveImpl() {
  try {
    final el = js_util.getProperty<Object?>(web.document, 'fullscreenElement');
    return el != null;
  } catch (_) {
    return false;
  }
}

Future<void> fullscreenEnterImpl() async {
  try {
    final root = web.document.documentElement;
    if (root == null) return;
    final promise = js_util.callMethod<Object?>(root, 'requestFullscreen', const <Object?>[]);
    if (promise == null) return;
    await js_util.promiseToFuture<void>(promise as Object);
  } catch (e) {
    // Fullscreen requests can fail due to browser restrictions (must be user gesture).
    debugPrint('Fullscreen: requestFullscreen failed: $e');
  }
}

Future<void> fullscreenExitImpl() async {
  try {
    final promise = js_util.callMethod<Object?>(web.document, 'exitFullscreen', const <Object?>[]);
    if (promise == null) return;
    await js_util.promiseToFuture<void>(promise as Object);
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
