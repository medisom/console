import 'dart:ui_web' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

class IFramePortalViewImpl extends StatefulWidget {
  const IFramePortalViewImpl({super.key, required this.url, this.onLoad, this.backgroundColor});

  final String url;
  final VoidCallback? onLoad;
  final Color? backgroundColor;

  @override
  State<IFramePortalViewImpl> createState() => _IFramePortalViewImplState();
}

class _IFramePortalViewImplState extends State<IFramePortalViewImpl> {
  static int _seq = 0;
  late final String _viewType;
  String _registeredForUrl = '';

  @override
  void initState() {
    super.initState();
    _viewType = 'iframe_portal_view_${_seq++}';
    _registerForUrl(widget.url);
  }

  @override
  void didUpdateWidget(covariant IFramePortalViewImpl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url.trim() != widget.url.trim()) {
      _registerForUrl(widget.url);
    }
  }

  void _registerForUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return;
    if (_registeredForUrl == trimmed) return;
    _registeredForUrl = trimmed;

    // Registering multiple times with the same viewType throws. We generate a
    // unique viewType per widget instance, so this is safe.
    ui.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final iframe = web.HTMLIFrameElement()
        ..src = trimmed
        ..style.border = '0'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.backgroundColor = (widget.backgroundColor ?? Colors.black).toCssString();

      // Try to allow common capabilities; actual permissions depend on browser.
      iframe.allow = 'camera; microphone; fullscreen; geolocation; clipboard-read; clipboard-write';

      try {
        iframe.onLoad.listen((_) {
          debugPrint('IFramePortalView loaded: $trimmed');
          widget.onLoad?.call();
        });
        iframe.onError.listen((event) {
          debugPrint('IFramePortalView iframe error for: $trimmed ($event)');
        });

      } catch (e) {
        debugPrint('IFramePortalView onLoad listener attach failed: $e');
      }

      return iframe;
    });
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewType);
  }
}

extension on Color {
  String toCssString() => 'rgba($red,$green,$blue,${(a / 255).toStringAsFixed(3)})';
}
