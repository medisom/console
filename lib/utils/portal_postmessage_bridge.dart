import 'package:flutter/foundation.dart';

import 'package:medisom_console/utils/portal_postmessage_bridge_stub.dart'
    if (dart.library.js_interop) 'package:medisom_console/utils/portal_postmessage_bridge_web.dart';

/// Registers a `window.message` listener to bridge iframe -> Flutter actions.
///
/// On Web, this listens for:
/// - `{ acao: 'fechar_webview_flutter' }` => invokes [onCloseRequested]
/// - `{ acao: 'delete_webview_flutter' }` => invokes [onDeleteRequested]
/// - `{ acao: 'deletar_webview_flutter' }` => invokes [onDeleteRequested]
///
/// It also tries to forward the close/delete events to `window.Nativo.postMessage`,
/// when the hosting page provides it.
///
/// Returns a disposer callback that MUST be called from `dispose()`.
@visibleForTesting
typedef PortalBridgeDisposer = VoidCallback;

PortalBridgeDisposer registerPortalPostMessageBridge({required VoidCallback onCloseRequested, required VoidCallback onDeleteRequested}) {
  return registerPortalPostMessageBridgeImpl(onCloseRequested: onCloseRequested, onDeleteRequested: onDeleteRequested);
}
