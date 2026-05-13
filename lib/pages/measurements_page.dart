import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:medisom_console/auth/auth_controller.dart';
import 'package:medisom_console/nav.dart';
import 'package:medisom_console/theme.dart';
import 'package:medisom_console/utils/portal_launcher.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

class MeasurementsPage extends StatefulWidget {
  const MeasurementsPage({super.key});

  @override
  State<MeasurementsPage> createState() => _MeasurementsPageState();
}

class _MeasurementsPageState extends State<MeasurementsPage> with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  WebViewController? _controller;
  bool _isLoading = true;
  String? _error;
  String? _activeEmail;
  bool _syncScheduled = false;
  bool _isInForeground = true;
  bool _resumeReloadPending = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isInForeground = state == AppLifecycleState.resumed;

    // When the app returns from background, Android WebView can be killed or
    // drop network state. Proactively reload to avoid a stuck error state.
    if (state == AppLifecycleState.resumed) {
      unawaited(_handleResume());
    }
  }

  Future<void> _handleResume() async {
    if (!mounted) return;

    // If we previously saw a web resource error while backgrounded, clear it and
    // attempt a reload.
    if (_resumeReloadPending) {
      _resumeReloadPending = false;
      if (mounted) {
        setState(() {
          _error = null;
          _isLoading = true;
        });
      }
    }

    final c = _controller;
    if (c != null) {
      try {
        await c.reload();
        return;
      } catch (e) {
        debugPrint('MeasurementsPage reload failed on resume: $e');
        // fall-through to full re-init
      }
    }

    final email = (_activeEmail ?? '').trim();
    if (email.isNotEmpty) {
      await _initForEmail(email);
    }
  }

  String _buildConsoleUrl({required String email}) {
    // Backend expects: https://medisom.com.br/iot/console?email=email_da_conta_atual
    final base = Uri.parse('https://medisom.com.br/iot/console');
    return base.replace(queryParameters: {'email': email}).toString();
  }

  void _closeToDevices() {
    if (!mounted) return;
    context.go(AppRoutes.devices);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // NOTE: do not read AuthController here with `read()`.
    // We must react to user changes (logout/login) even when this tab is kept
    // alive inside a StatefulShellRoute IndexedStack.
    _scheduleSyncWithAuth();
  }

  void _scheduleSyncWithAuth() {
    if (_syncScheduled) return;
    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      if (!mounted) return;
      final email = (context.read<AuthController>().user?.email ?? '').trim().toLowerCase();
      unawaited(_syncForEmail(email));
    });
  }

  Future<void> _syncForEmail(String email) async {
    if (email.isEmpty) {
      if (!mounted) return;
      setState(() {
        _activeEmail = null;
        _controller = null;
        _isLoading = false;
        _error = 'Nenhum e-mail logado.';
      });
      return;
    }

    if (_activeEmail == email && _controller != null) return;
    _activeEmail = email;
    await _initForEmail(email);
  }

  Future<void> _initForEmail(String email) async {
    final url = _buildConsoleUrl(email: email);
    setState(() {
      _controller = null;
      _isLoading = true;
      _error = null;
    });

    // WebView inside the app is not available on Flutter Web.
    if (kIsWeb) {
      try {
        await openPortalReplace(url);
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _error = 'Abrindo no navegador…';
        });
      } catch (e) {
        debugPrint('MeasurementsPage openPortalReplace failed: $e');
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _error = 'Não foi possível abrir Medições.';
        });
      }
      return;
    }

    try {
      final uri = Uri.tryParse(url);
      if (uri == null) {
        setState(() {
          _isLoading = false;
          _error = 'URL inválida.';
        });
        return;
      }

      final c = WebViewController();
      c.setJavaScriptMode(JavaScriptMode.unrestricted);
      c.addJavaScriptChannel(
        'Nativo',
        onMessageReceived: (msg) {
          final message = msg.message.trim();
          debugPrint('MeasurementsPage JS[Nativo]: $message');
          if (!mounted) return;
          if (message == 'fecharWebView') {
            _closeToDevices();
            return;
          }
        },
      );
      c.setBackgroundColor(Colors.black);
      c.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final url = request.url.trim();
            final lower = url.toLowerCase();
            final shouldExternal = lower.startsWith('whatsapp://') || lower.startsWith('tel:') || lower.startsWith('mailto:');
            if (!shouldExternal) return NavigationDecision.navigate;

            final uri = Uri.tryParse(url);
            if (uri == null) {
              debugPrint('MeasurementsPage invalid external URL: $url');
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
            setState(() => _isLoading = false);
          },
          onWebResourceError: (err) {
            debugPrint('MeasurementsPage web error: ${err.errorCode} ${err.description}');
            if (!mounted) return;

            // When backgrounding on Android, WebView can report transient errors.
            // Avoid locking the UI into an error state; instead, reload when the
            // app returns to foreground.
            if (!_isInForeground) {
              _resumeReloadPending = true;
              return;
            }

            setState(() {
              _isLoading = false;
              _error = 'Falha ao carregar Medições.';
            });
          },
        ),
      );
      await c.loadRequest(uri);

      if (!mounted) return;
      setState(() => _controller = c);
    } catch (e) {
      debugPrint('MeasurementsPage controller init failed: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Não foi possível abrir Medições.';
        });
      }
    }
  }

  Future<void> _launchExternal(Uri uri) async {
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) debugPrint('MeasurementsPage could not launch externally: $uri');
    } catch (e) {
      debugPrint('MeasurementsPage external launch failed ($uri): $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // This makes the widget rebuild whenever the logged user changes.
    // The actual sync work is scheduled post-frame to avoid setState during build.
    context.watch<AuthController>();
    _scheduleSyncWithAuth();
    final cs = Theme.of(context).colorScheme;

    final isIOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    final topInset = isIOS ? MediaQuery.paddingOf(context).top : 0.0;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (_, __) => _closeToDevices(),
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
                    ? _MeasurementsErrorState(message: _error!, onBack: _closeToDevices)
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

class _MeasurementsErrorState extends StatelessWidget {
  const _MeasurementsErrorState({required this.message, required this.onBack});

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
              color: cs.surfaceContainerHighest.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.35)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.analytics_outlined, color: cs.onSurfaceVariant, size: 40),
                const SizedBox(height: AppSpacing.md),
                Text('Medições indisponíveis', style: context.textStyles.titleMedium?.copyWith(color: Colors.white), textAlign: TextAlign.center),
                const SizedBox(height: AppSpacing.sm),
                Text(message, style: context.textStyles.bodyMedium?.copyWith(color: Colors.white, height: 1.35), textAlign: TextAlign.center),
                const SizedBox(height: AppSpacing.md),
                FilledButton(
                  onPressed: onBack,
                  style: FilledButton.styleFrom(backgroundColor: cs.primary, foregroundColor: cs.onPrimary),
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
