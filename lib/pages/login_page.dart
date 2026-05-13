import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:medisom_console/auth/auth_controller.dart';
import 'package:medisom_console/auth/biometric_credentials_service.dart';
import 'package:medisom_console/nav.dart';
import 'package:medisom_console/theme.dart';
import 'package:medisom_console/widgets/primary_button.dart';
import 'package:medisom_console/widgets/responsive_auth_scaffold.dart';

class LoginPage extends StatefulWidget {
  final String? initialEmail;
  final String? initialPassword;

  const LoginPage({super.key, this.initialEmail, this.initialPassword});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _email;
  late final TextEditingController _password;
  final BiometricCredentialsService _biometric = BiometricCredentialsService();
  bool _loading = false;
  bool _obscure = true;

  bool _biometricSupported = false;
  bool _hasSavedCredentials = false;
  bool _askedToSaveFromSignup = false;

  bool _saveBiometricOnThisDevice = false;
  bool _saveBiometricTouched = false;

  bool get _isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  String get _biometricTitleText => _isIOS ? 'Face ID' : 'Login biométrico';
  String get _biometricButtonText => _isIOS ? 'Face ID' : 'Entrar com biometria';

  @override
  void initState() {
    super.initState();
    final initial = (widget.initialEmail ?? '').trim();
    _email = TextEditingController(text: initial);
    _password = TextEditingController(text: widget.initialPassword ?? '');

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshBiometricState();
      _maybeAskToSaveCredentialsFromSignup();
    });
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await context.read<AuthController>().signIn(email: _email.text.trim(), password: _password.text);

      // If the user explicitly enabled biometric login on this screen, store
      // the credentials securely for later biometric retrieval.
      if (_biometricSupported) {
        if (_saveBiometricOnThisDevice) {
          try {
            await _biometric.enableAndSaveCredentials(email: _email.text.trim(), password: _password.text);
          } catch (e) {
            debugPrint('LoginPage failed to save biometric credentials: $e');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Não foi possível ativar o login biométrico neste aparelho.')),
              );
            }
          }
        } else if (_hasSavedCredentials) {
          // Respect user choice: if previously enabled, disable it.
          await _biometric.disable();
        }
        if (mounted) await _refreshBiometricState();
      }
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refreshBiometricState() async {
    try {
      final supported = await _biometric.isSupported();
      final has = supported ? await _biometric.hasSavedCredentials() : false;
      if (!mounted) return;
      setState(() {
        _biometricSupported = supported;
        _hasSavedCredentials = has;

        // Default the toggle to current state unless the user already changed it.
        if (!_saveBiometricTouched) _saveBiometricOnThisDevice = has;
      });
    } catch (e) {
      debugPrint('LoginPage._refreshBiometricState failed: $e');
    }
  }

  Future<void> _maybeAskToSaveCredentialsFromSignup() async {
    if (_askedToSaveFromSignup) return;
    final initialEmail = (widget.initialEmail ?? '').trim();
    final initialPassword = widget.initialPassword ?? '';
    if (initialEmail.isEmpty || initialPassword.isEmpty) return;

    // Only prompt if biometrics is available and not already enabled.
    final supported = await _biometric.isSupported();
    if (!supported) return;
    final already = await _biometric.hasSavedCredentials();
    if (already) return;

    if (!mounted) return;
    setState(() => _askedToSaveFromSignup = true);

    final cs = Theme.of(context).colorScheme;
    final enable = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          backgroundColor: Colors.transparent,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.45)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Ativar login biométrico?', style: context.textStyles.titleMedium),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Podemos salvar suas credenciais com segurança neste aparelho para você entrar com Face ID/Biometria quando precisar logar novamente.',
                      style: context.textStyles.bodyMedium?.copyWith(color: cs.onSurfaceVariant, height: 1.35),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => context.pop(false),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.65)),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                            ),
                            child: Text('Agora não', style: TextStyle(color: cs.onSurface)),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: FilledButton(
                            onPressed: () => context.pop(true),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                              backgroundColor: cs.primary,
                              foregroundColor: cs.onPrimary,
                            ),
                            child: const Text('Ativar'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    if (enable != true || !mounted) return;
    try {
      await _biometric.enableAndSaveCredentials(email: initialEmail, password: initialPassword);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Login biométrico ativado neste aparelho.')));
    } catch (e) {
      debugPrint('Failed to save biometric credentials: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não foi possível ativar o login biométrico.')));
    } finally {
      if (mounted) _refreshBiometricState();
    }
  }

  Future<void> _loginWithBiometrics() async {
    setState(() => _loading = true);
    try {
      final auth = context.read<AuthController>();
      final router = GoRouter.of(context);
      final creds = await _biometric.authenticateAndLoad(reason: 'Use sua biometria para entrar no Medisom Console.');
      if (creds == null) return;
      _email.text = creds.email;
      _password.text = creds.password;
      await auth.signIn(email: creds.email, password: creds.password);

      if (!mounted) return;

      // Ensure we leave the auth screen immediately after a successful biometric sign-in.
      // The router redirect will also enforce the correct destination, but this makes
      // the UX feel instant and avoids any “stuck on login” perception.
      router.go(AppRoutes.devices);
    } catch (e) {
      debugPrint('Login biométrico falhou: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ResponsiveAuthScaffold(
      title: 'Bem-vindo de volta',
      subtitle: '',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Entrar', style: context.textStyles.titleLarge),
            const SizedBox(height: AppSpacing.sm),
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.username, AutofillHints.email],
              decoration: const InputDecoration(labelText: 'E-mail', prefixIcon: Icon(Icons.alternate_email)),
              validator: (v) {
                final value = (v ?? '').trim();
                if (value.isEmpty) return 'Informe o e-mail.';
                if (!value.contains('@')) return 'E-mail inválido.';
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _password,
              obscureText: _obscure,
              autofillHints: const [AutofillHints.password],
              decoration: InputDecoration(
                labelText: 'Senha',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: cs.onSurfaceVariant),
                  tooltip: _obscure ? 'Mostrar senha' : 'Ocultar senha',
                ),
              ),
              validator: (v) => (v ?? '').isEmpty ? 'Informe a senha.' : null,
            ),
            if (_biometricSupported) ...[
              const SizedBox(height: AppSpacing.sm),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.45)),
                ),
                child: SwitchListTile.adaptive(
                  value: _saveBiometricOnThisDevice,
                  onChanged: _loading
                      ? null
                      : (v) {
                          setState(() {
                            _saveBiometricTouched = true;
                            _saveBiometricOnThisDevice = v;
                          });
                        },
                  title: Text(_biometricTitleText, style: context.textStyles.bodyMedium),
                  secondary: Icon(Icons.fingerprint, color: cs.primary),
                  thumbColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) return cs.onPrimary;
                    return cs.outlineVariant;
                  }),
                  trackColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) return cs.primary;
                    return cs.surfaceContainerHighest;
                  }),
                  contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 2),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(onPressed: _submit, label: 'Entrar', icon: Icons.login, isLoading: _loading),
            if (_biometricSupported && _hasSavedCredentials) ...[
              const SizedBox(height: AppSpacing.md),
              OutlinedButton.icon(
                onPressed: _loading ? null : _loginWithBiometrics,
                icon: Icon(Icons.fingerprint, color: cs.primary),
                  label: Text(_biometricButtonText, style: TextStyle(color: cs.primary)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: cs.primary.withValues(alpha: 0.35)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => context.push(AppRoutes.forgotPassword),
                    child: Text('Esqueci minha senha', style: TextStyle(color: cs.primary)),
                  ),
                ),
                Expanded(
                  child: TextButton(
                    onPressed: () => context.push(AppRoutes.register),
                    child: Text('Registrar', style: TextStyle(color: cs.primary)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
