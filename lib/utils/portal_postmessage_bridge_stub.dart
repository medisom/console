import 'package:flutter/foundation.dart';

typedef PortalBridgeDisposer = VoidCallback;

PortalBridgeDisposer registerPortalPostMessageBridgeImpl({required VoidCallback onCloseRequested, required VoidCallback onDeleteRequested}) {
  return () {};
}
