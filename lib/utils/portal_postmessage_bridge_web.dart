import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

typedef PortalBridgeDisposer = VoidCallback;

// Matches the user requirement: forward to `window.Nativo.postMessage('fecharWebView')` when possible.
void _tryForwardToNativoClose() {
  try {
    final w = web.window as JSObject;
    final nativo = w.getProperty('Nativo'.toJS);
    if (nativo == null || nativo.isUndefinedOrNull) {
      debugPrint('PortalPostMessageBridge: close received, but window.Nativo is not available.');
      return;
    }

    // Try `Nativo.postMessage('fecharWebView')`.
    (nativo as JSObject).callMethod('postMessage'.toJS, <JSAny?>['fecharWebView'.toJS].toJS);
  } catch (e) {
    debugPrint('PortalPostMessageBridge: failed to forward close to window.Nativo: $e');
  }
}

// Matches the user requirement: forward to `window.Nativo.postMessage('deleteWebView')` when possible.
void _tryForwardToNativoDelete() {
  try {
    final w = web.window as JSObject;
    final nativo = w.getProperty('Nativo'.toJS);
    if (nativo == null || nativo.isUndefinedOrNull) {
      debugPrint('PortalPostMessageBridge: delete received, but window.Nativo is not available.');
      return;
    }

    (nativo as JSObject).callMethod('postMessage'.toJS, <JSAny?>['deleteWebView'.toJS].toJS);
  } catch (e) {
    debugPrint('PortalPostMessageBridge: failed to forward delete to window.Nativo: $e');
  }
}

String? _extractAcao(Object? data) {
  try {
    if (data == null) return null;
    final js = data as JSAny?;
    if (js == null || js.isUndefinedOrNull) return null;
    if (js is! JSObject) return null;
    final acao = js.getProperty('acao'.toJS);
    if (acao == null || acao.isUndefinedOrNull) return null;
    // If it's a JS string, `toDart` gives us a Dart string. Otherwise, fallback.
    if (acao is JSString) return (acao).toDart;
    return acao.toString();
  } catch (_) {
    return null;
  }
}

PortalBridgeDisposer registerPortalPostMessageBridgeImpl({required VoidCallback onCloseRequested, required VoidCallback onDeleteRequested}) {
  // Keep a stable listener reference so we can remove it on dispose.
  final web.EventListener listener = ((web.Event event) {
    // We're attached to the 'message' event, so this cast is expected.
    final messageEvent = event as web.MessageEvent;
    final acao = _extractAcao(messageEvent.data);
    if (acao == null) return;

    if (acao == 'fechar_webview_flutter') {
      debugPrint('PortalPostMessageBridge: received fechar_webview_flutter via postMessage');
      _tryForwardToNativoClose();
      onCloseRequested();
      return;
    }

    if (acao == 'delete_webview_flutter' || acao == 'deletar_webview_flutter') {
      debugPrint('PortalPostMessageBridge: received $acao via postMessage');
      _tryForwardToNativoDelete();
      onDeleteRequested();
      return;
    }
  }).toJS;

  web.window.addEventListener('message', listener);

  return () {
    try {
      web.window.removeEventListener('message', listener);
    } catch (e) {
      debugPrint('PortalPostMessageBridge: removeEventListener failed: $e');
    }
  };
}
