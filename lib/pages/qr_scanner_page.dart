import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:medisom_console/theme.dart';

/// Simple QR scanner page.
///
/// Returns the scanned QR content string via `context.pop(result)`.
class QrScannerPage extends StatefulWidget {
  const QrScannerPage({super.key});

  @override
  State<QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<QrScannerPage> {
  late final MobileScannerController _controller;
  bool _hasPopped = false;
  String? _lastError;
  bool _torchOn = false;
  bool _isHandlingDetection = false;
  String? _lastDetectedValue;
  DateTime? _lastDetectedAt;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      formats: const [BarcodeFormat.qrCode],
      facing: CameraFacing.back,
      torchEnabled: false,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleDetection(BarcodeCapture capture) {
    // `onDetect` is sync; we bridge into async handling safely.
    if (_hasPopped || _isHandlingDetection) return;
    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;
    final raw = barcodes.first.rawValue;
    if (raw == null) return;
    final value = raw.trim();
    if (value.isEmpty) return;

    final now = DateTime.now();
    if (_lastDetectedValue == value && _lastDetectedAt != null && now.difference(_lastDetectedAt!) < const Duration(seconds: 2)) {
      return;
    }
    _lastDetectedValue = value;
    _lastDetectedAt = now;

    _isHandlingDetection = true;
    Future<void>(() async {
      try {
        await _processDetectedValue(value);
      } finally {
        _isHandlingDetection = false;
      }
    });
  }

  Future<void> _processDetectedValue(String value) async {
    if (!mounted || _hasPopped) return;

    if (!value.startsWith('MEDISOM_')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('QR-code inválido. O código deve começar com "MEDISOM_".')),
      );
      return;
    }

    // Pause scanning while we ask for confirmation.
    try {
      await _controller.stop();
    } catch (e) {
      debugPrint('QrScannerPage: failed to stop scanner: $e');
    }

    if (!mounted || _hasPopped) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final cs = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          title: const Text('Confirmar sensor'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Código lido:', style: dialogContext.textStyles.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              const SizedBox(height: 8),
              SelectableText(
                value,
                style: dialogContext.textStyles.titleSmall?.copyWith(height: 1.2),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => dialogContext.pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => dialogContext.pop(true),
              style: FilledButton.styleFrom(backgroundColor: cs.primary),
              child: Text('Confirmar', style: TextStyle(color: cs.onPrimary)),
            ),
          ],
        );
      },
    );

    if (!mounted || _hasPopped) return;

    if (ok == true) {
      _hasPopped = true;
      context.pop<String>(value);
      return;
    }

    // User cancelled: resume scanning.
    try {
      await _controller.start();
    } catch (e) {
      debugPrint('QrScannerPage: failed to start scanner: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Escanear código QR'),
        actions: [
          IconButton(
            tooltip: 'Alternar flash',
            onPressed: () {
              _controller.toggleTorch();
              setState(() => _torchOn = !_torchOn);
            },
            icon: Icon(_torchOn ? Icons.flash_on : Icons.flash_off),
          ),
          IconButton(
            tooltip: 'Trocar câmera',
            onPressed: () => _controller.switchCamera(),
            icon: const Icon(Icons.cameraswitch),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _handleDetection,
            errorBuilder: (context, error) {
              debugPrint('MobileScanner error: $error');
              _lastError ??= error.errorDetails?.message ?? error.toString();
              return _ScannerErrorState(message: _lastError!);
            },
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const _ScannerOverlayCard(title: 'Aponte para o QR-code do sensor'),
                    const SizedBox(height: AppSpacing.md),
                    FilledButton.icon(
                      onPressed: () => context.pop<String?>(null),
                      icon: Icon(Icons.close, color: cs.onPrimary),
                      label: Text('Cancelar', style: TextStyle(color: cs.onPrimary)),
                      style: FilledButton.styleFrom(
                        backgroundColor: cs.primary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IgnorePointer(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 340),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppRadius.xl),
                      border: Border.all(color: cs.primary.withValues(alpha: 0.85), width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 18,
                          spreadRadius: 0,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScannerOverlayCard extends StatelessWidget {
  const _ScannerOverlayCard({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: context.textStyles.titleSmall?.copyWith(height: 1.2)),
        ],
      ),
    );
  }
}

class _ScannerErrorState extends StatelessWidget {
  const _ScannerErrorState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surface,
      padding: AppSpacing.paddingLg,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.camera_alt, size: 42, color: cs.onSurfaceVariant),
              const SizedBox(height: AppSpacing.md),
              Text('Não foi possível acessar a câmera', style: context.textStyles.titleMedium, textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.sm),
              Text(
                message,
                style: context.textStyles.bodyMedium?.copyWith(color: cs.onSurfaceVariant, height: 1.45),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton(
                onPressed: () => context.pop<String?>(null),
                style: FilledButton.styleFrom(
                  backgroundColor: cs.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
                ),
                child: Text('Voltar', style: TextStyle(color: cs.onPrimary)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
