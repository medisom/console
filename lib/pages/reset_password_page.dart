import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:medisom_console/auth/auth_controller.dart';
import 'package:medisom_console/nav.dart';
import 'package:medisom_console/theme.dart';
import 'package:medisom_console/widgets/primary_button.dart';
import 'package:medisom_console/widgets/responsive_auth_scaffold.dart';

class ResetPasswordPage extends StatefulWidget {
  final String? initialEmail;

  const ResetPasswordPage({super.key, this.initialEmail});

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _email;
  final _token = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _inlineError;

  @override
  void initState() {
    super.initState();
    _email = TextEditingController(text: widget.initialEmail ?? '');
  }

  @override
  void dispose() {
    _email.dispose();
    _token.dispose();
    _password.dispose();
    super.dispose();
  }

  bool get _meetsRequirements {
    final p = _password.text;
    if (p.length < 6 || p.length > 20) return false;
    final hasLetter = RegExp(r'[A-Za-z]').hasMatch(p);
    // Note: use raw "\d" to match digits; "\\d" would look for a literal "\d".
    final hasNumber = RegExp(r'\d').hasMatch(p);
    return hasLetter && hasNumber;
  }

  Future<void> _submit() async {
    setState(() => _inlineError = null);
    if (!_formKey.currentState!.validate()) return;
    if (!_meetsRequirements) {
      setState(() => _inlineError = 'Use de 6 a 20 caracteres, misturando letras e números');
      return;
    }

    setState(() => _loading = true);
    try {
      await context.read<AuthController>().resetPassword(
            email: _email.text.trim(),
            resetToken: _token.text.trim(),
            newPassword: _password.text,
          );
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Senha redefinida com sucesso.')));
      final encodedEmail = Uri.encodeQueryComponent(_email.text.trim());
      context.go('${AppRoutes.login}?email=$encodedEmail');
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      setState(() => _inlineError = msg);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ResponsiveAuthScaffold(
      title: 'Redefinir senha',
      subtitle: 'Informe o código enviado por e-mail e escolha uma nova senha.',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () {
                    if (context.canPop()) {
                      context.pop();
                    } else {
                      context.go(AppRoutes.forgotPassword);
                    }
                  },
                  icon: Icon(Icons.arrow_back, color: cs.onSurface),
                  tooltip: 'Voltar',
                ),
                const SizedBox(width: 8),
                Expanded(child: Text('Redefinir', style: context.textStyles.titleLarge)),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
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
              controller: _token,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
              decoration: const InputDecoration(labelText: 'Código recebido por e-mail', prefixIcon: Icon(Icons.password_outlined), counterText: ''),
              validator: (v) {
                final value = (v ?? '').trim();
                if (value.isEmpty) return 'Informe o código.';
                if (value.length != 6) return 'Código inválido.';
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _password,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: 'Nova senha',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off, color: cs.onSurfaceVariant),
                  tooltip: _obscure ? 'Mostrar' : 'Ocultar',
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            if (_inlineError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: Text(_inlineError!, style: context.textStyles.bodySmall?.copyWith(color: cs.error, height: 1.35)),
              ),
            PrimaryButton(
              onPressed: _submit,
              label: 'Redefinir senha',
              icon: Icons.check_circle_outline,
              isLoading: _loading,
            ),
          ],
        ),
      ),
    );
  }
}
