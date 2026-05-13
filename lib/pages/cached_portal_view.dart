import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:medisom_console/auth/auth_controller.dart';
import 'package:medisom_console/sensors/sensor_service.dart';
import 'package:medisom_console/theme.dart';
import 'package:medisom_console/utils/portal_launcher.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// A WebView portal that is meant to be kept alive inside an IndexedStack.
///
/// Important: the state (and thus the WebView instance) is preserved as long as
/// this widget stays mounted (which the PortalStackPage guarantees).
class CachedPortalView extends StatefulWidget {
  const CachedPortalView({super.key, required this.sensorId, required this.url, this.title, required this.onRequestClose});

  final String sensorId;
  final String url;
  final String? title;
  final VoidCallback onRequestClose;

  @override
  State<CachedPortalView> createState() => _CachedPortalViewState();
}

class _CachedPortalViewState extends State<CachedPortalView> with AutomaticKeepAliveClientMixin {
  WebViewController? _controller;
  bool _isLoading = true;
  String? _error;

  Future<void> _handleDeleteWebViewRequest() async {
    try {
      final email = (context.read<AuthController>().user?.email ?? '').trim().toLowerCase();
      if (email.isEmpty) {
        debugPrint('CachedPortalView(${widget.sensorId}) deleteWebView: no logged email; closing portal only');
      } else {
        await SensorService().deleteSensor(email: email, sensorId: widget.sensorId);
        debugPrint('CachedPortalView(${widget.sensorId}) deleteWebView: sensor deleted for $email');
      }
    } catch (e) {
      debugPrint('CachedPortalView(${widget.sensorId}) deleteWebView failed: $e');
    } finally {
      if (mounted) {
        // Also close the portal (same behavior as `fecharWebView`).
        widget.onRequestClose();
      }
    }
  }

  static const String _disableUserDragJs = """
(function() {
  try {
    const style = document.createElement('style');
    style.type = 'text/css';
    style.innerHTML = `
      html, body {
        overscroll-behavior: none !important;
        -webkit-overflow-scrolling: auto !important;
        overflow: hidden !important;
        touch-action: none !important;
      }
      * {
        -webkit-user-select: none !important;
        user-select: none !important;
      }
    `;
    document.head && document.head.appendChild(style);

    const prevent = function(e) { e.preventDefault(); };
    window.addEventListener('touchmove', prevent, { passive: false });
    window.addEventListener('scroll', function() { window.scrollTo(0, 0); });
  } catch (e) {
    // Ignore
  }
})();
""";

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void didUpdateWidget(covariant CachedPortalView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the URL changes for an already-opened portal, reload in-place.
    if (oldWidget.url.trim() != widget.url.trim() && widget.url.trim().isNotEmpty) {
      unawaited(_reloadUrl(widget.url.trim()));
    }
  }

  Future<void> _init() async {
    final url = widget.url.trim();
    if (url.isEmpty) {
      setState(() {
        _isLoading = false;
        _error = 'URL do portal inválida.';
      });
      return;
    }

    // WebView inside the app is not available on Flutter Web.
    if (kIsWeb) {
      try {
        await openPortalReplace(url);
      } catch (e) {
        debugPrint('CachedPortalView openPortalReplace failed: $e');
        if (mounted) {
          setState(() {
            _isLoading = false;
            _error = 'Não foi possível abrir o portal.';
          });
        }
        return;
      }
      if (mounted) widget.onRequestClose();
      return;
    }

    try {
      final parsed = Uri.tryParse(url);
      if (parsed == null) {
        setState(() {
          _isLoading = false;
          _error = 'URL do portal inválida.';
        });
        return;
      }

      final c = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..addJavaScriptChannel(
          'Nativo',
          onMessageReceived: (msg) {
            final message = msg.message.trim();
            debugPrint('CachedPortalView(${widget.sensorId}) JS[Nativo]: $message');
            if (!mounted) return;
            if (message == 'fecharWebView') {
              debugPrint('CachedPortalView(${widget.sensorId}) requestClose triggered by JS');
              widget.onRequestClose();
              return;
            }

            if (message == 'deleteWebView') {
              debugPrint('CachedPortalView(${widget.sensorId}) delete requested by JS');
              unawaited(_handleDeleteWebViewRequest());
              return;
            }
          },
        )
        // The portal must sit on a fully black background (requested), including
        // the initial blank/paint phase while the page loads.
        ..setBackgroundColor(Colors.black)
        ..setNavigationDelegate(
          NavigationDelegate(
            onNavigationRequest: (request) {
              final url = request.url.trim();
              final lower = url.toLowerCase();
              final shouldExternal = lower.startsWith('whatsapp://') || lower.startsWith('tel:') || lower.startsWith('mailto:');
              if (!shouldExternal) return NavigationDecision.navigate;

              final uri = Uri.tryParse(url);
              if (uri == null) {
                debugPrint('CachedPortalView invalid external URL: $url');
                return NavigationDecision.prevent;
              }

              unawaited(_launchExternal(uri));
              return NavigationDecision.prevent;
            },
            onPageStarted: (_) {
              if (!mounted) return;
              setState(() {
                _isLoading = true;
                _error = null;
              });
            },
            onPageFinished: (_) {
              if (!mounted) return;
              // On iOS, prevent the typical "drag" / rubber-banding / scrolling.
              // This is requested for kiosk-like portal usage.
              if (defaultTargetPlatform == TargetPlatform.iOS) {
                unawaited(
                  _controller
                          ?.runJavaScript(_disableUserDragJs)
                          .catchError((e) => debugPrint('CachedPortalView iOS disable-drag JS failed: $e')) ??
                      Future<void>.value(),
                );
              }
              setState(() => _isLoading = false);
            },
            onWebResourceError: (err) {
              debugPrint('CachedPortalView web error: ${err.errorCode} ${err.description}');
              if (!mounted) return;
              setState(() {
                _isLoading = false;
                _error = 'Falha ao carregar o portal.';
              });
            },
          ),
        )
        ..loadRequest(parsed);

      if (!mounted) return;
      setState(() => _controller = c);
    } catch (e) {
      debugPrint('CachedPortalView controller init failed: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Não foi possível abrir o portal.';
        });
      }
    }
  }

  Future<void> _reloadUrl(String url) async {
    try {
      final c = _controller;
      final uri = Uri.tryParse(url);
      if (c == null || uri == null) return;
      setState(() {
        _isLoading = true;
        _error = null;
      });
      await c.loadRequest(uri);
    } catch (e) {
      debugPrint('CachedPortalView reload failed: $e');
    }
  }

  Future<void> _launchExternal(Uri uri) async {
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) debugPrint('CachedPortalView could not launch externally: $uri');
    } catch (e) {
      debugPrint('CachedPortalView external launch failed ($uri): $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final cs = Theme.of(context).colorScheme;
    final isIOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    final topInset = isIOS ? MediaQuery.paddingOf(context).top : 0.0;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (_, __) {
        widget.onRequestClose();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            const Positioned.fill(child: ColoredBox(color: Colors.black)),
            Positioned.fill(
              child: SafeArea(
                top: isIOS,
                bottom: false,
                child: _error != null
                    ? _PortalErrorState(message: _error!, onBack: widget.onRequestClose)
                    : (_controller == null)
                        ? const SizedBox.shrink()
                        : WebViewWidget(controller: _controller!),
              ),
            ),
            if (_isLoading)
              Positioned(
                left: 0,
                right: 0,
                top: topInset,
                child: LinearProgressIndicator(
                  minHeight: 2,
                  color: cs.primary,
                  backgroundColor: cs.surfaceContainerHighest.withValues(alpha: 0.35),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PortalErrorState extends StatelessWidget {
  const _PortalErrorState({required this.message, required this.onBack});

  final String message;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: AppSpacing.paddingLg,
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: cs.errorContainer.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: cs.error.withValues(alpha: 0.25)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.public_off, color: cs.onErrorContainer, size: 40),
                const SizedBox(height: AppSpacing.md),
                Text('Não foi possível abrir o portal', style: context.textStyles.titleMedium, textAlign: TextAlign.center),
                const SizedBox(height: AppSpacing.sm),
                Text(message, style: context.textStyles.bodyMedium?.copyWith(color: cs.onErrorContainer, height: 1.35), textAlign: TextAlign.center),
                const SizedBox(height: AppSpacing.md),
                FilledButton(
                  onPressed: onBack,
                  style: FilledButton.styleFrom(backgroundColor: cs.error, foregroundColor: cs.onError),
                  child: const Text('Voltar'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
