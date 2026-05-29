import 'dart:js_interop';
import 'dart:js_util' as js_util;

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

typedef PortalBridgeDisposer = VoidCallback;

// Matches the user requirement: forward to `window.Nativo.postMessage('fecharWebView')` when possible.
void _tryForwardToNativoClose() {
  try {
    final w = web.window;
    final nativo = js_util.getProperty<Object?>(w, 'Nativo');
    if (nativo == null) {
      debugPrint('PortalPostMessageBridge: close received, but window.Nativo is not available.');
      return;
    }

    // Try `Nativo.postMessage('fecharWebView')`.
    js_util.callMethod<Object?>(nativo, 'postMessage', <Object?>['fecharWebView']);
  } catch (e) {
    debugPrint('PortalPostMessageBridge: failed to forward close to window.Nativo: $e');
  }
}

// Matches the user requirement: forward to `window.Nativo.postMessage('deleteWebView')` when possible.
void _tryForwardToNativoDelete() {
  try {
    final w = web.window;
    final nativo = js_util.getProperty<Object?>(w, 'Nativo');
    if (nativo == null) {
      debugPrint('PortalPostMessageBridge: delete received, but window.Nativo is not available.');
      return;
    }

    js_util.callMethod<Object?>(nativo, 'postMessage', <Object?>['deleteWebView']);
  } catch (e) {
    debugPrint('PortalPostMessageBridge: failed to forward delete to window.Nativo: $e');
  }
}

String? _extractAcao(Object? data) {
  try {
    if (data == null) return null;
    if (!js_util.hasProperty(data, 'acao')) return null;
    final acao = js_util.getProperty<Object?>(data, 'acao');
    if (acao is String) return acao;
    return acao?.toString();
  } catch (_) {
    return null;
  }
}

PortalBridgeDisposer registerPortalPostMessageBridgeImpl({required VoidCallback onCloseRequested, required VoidCallback onDeleteRequested}) {
  // Keep a stable listener reference so we can remove it on dispose.
  final web.EventListener listener = ((web.Event event) {
    if (event is! web.MessageEvent) return;
    final acao = _extractAcao(event.data);
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
