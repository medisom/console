import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:medisom_console/auth/auth_controller.dart';
import 'package:medisom_console/nav.dart';
import 'package:medisom_console/theme.dart';
import 'package:medisom_console/widgets/brand_logo.dart';
import 'package:medisom_console/widgets/primary_button.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  static const _introDuration = Duration(seconds: 3);
  bool _showIntro = true;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(_introDuration).then((_) {
      if (!mounted) return;
      setState(() => _showIntro = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final status = context.watch<AuthController>().status;

    final Widget content;
    if (_showIntro) {
      content = const _SplashIntro();
    } else {
      content = status == AuthStatus.loading ? const _SplashLoading() : const _SplashLanding();
    }

    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [cs.primaryContainer, cs.surface, cs.surface],
            stops: const [0.0, 0.55, 1.0],
          ),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Padding(
              padding: AppSpacing.paddingLg,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeOutCubic,
                child: content,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SplashIntro extends StatelessWidget {
  const _SplashIntro();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      key: const ValueKey('intro'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 108,
          height: 108,
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: cs.primary.withValues(alpha: 0.16)),
          ),
          child: const Padding(
            padding: EdgeInsets.all(16),
            child: BrandLogo(size: 74),
          ),
        ),
      ],
    );
  }
}

class _SplashLoading extends StatelessWidget {
  const _SplashLoading();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      key: const ValueKey('loading'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: cs.primary.withValues(alpha: 0.18)),
          ),
          child: const Padding(
            padding: EdgeInsets.all(10),
            child: BrandLogo(size: 44),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.2, color: cs.primary)),
        const SizedBox(height: AppSpacing.md),
        Text('Carregando…', style: context.textStyles.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
      ],
    );
  }
}

class _SplashLanding extends StatelessWidget {
  const _SplashLanding();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      key: const ValueKey('landing'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.center,
          child: Container(
            width: 86,
            height: 86,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: cs.primary.withValues(alpha: 0.16)),
            ),
            child: const Padding(
              padding: EdgeInsets.all(14),
              child: BrandLogo(size: 58),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('Medisom Console', textAlign: TextAlign.center, style: context.textStyles.headlineSmall),
        const SizedBox(height: 10),
        Text(
          'Medir para melhorar',
          textAlign: TextAlign.center,
          style: context.textStyles.bodyMedium?.copyWith(color: cs.onSurfaceVariant, height: 1.45),
        ),
        const SizedBox(height: AppSpacing.xl),
        PrimaryButton(
          onPressed: () => context.go(AppRoutes.login),
          label: 'Fazer login com uma conta existente',
          icon: Icons.login,
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => context.go(AppRoutes.register),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            side: BorderSide(color: cs.outline.withValues(alpha: 0.35)),
          ),
          icon: Icon(Icons.person_add_alt_1, size: 18, color: cs.primary),
          label: Text('Registrar', style: TextStyle(color: cs.primary)),
        ),
      ],
    );
  }
}
