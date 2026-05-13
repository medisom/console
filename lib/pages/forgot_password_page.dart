import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:medisom_console/auth/auth_controller.dart';
import 'package:medisom_console/nav.dart';
import 'package:medisom_console/theme.dart';
import 'package:medisom_console/widgets/primary_button.dart';
import 'package:medisom_console/widgets/responsive_auth_scaffold.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _loading = false;
  String? _inlineMessage;
  String? _inlineError;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _inlineMessage = null;
      _inlineError = null;
    });
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final msg = await context.read<AuthController>().sendPasswordReset(email: _email.text.trim());
      if (!mounted) return;

      final safeMsg = (msg ?? '').trim();
      if (safeMsg.isNotEmpty) {
        setState(() => _inlineMessage = safeMsg);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(safeMsg)));
      }
      final encodedEmail = Uri.encodeQueryComponent(_email.text.trim());
      context.go('${AppRoutes.resetPassword}?email=$encodedEmail');
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
      title: 'Recuperar senha',
      subtitle: 'Informe seu e-mail para receber instruções de recuperação.',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () {
                    // This page is often opened via `context.go()`, which does not
                    // necessarily create a back stack entry. In that case, `pop()`
                    // becomes a no-op, so we fall back to the Login route.
                    if (context.canPop()) {
                      context.pop();
                    } else {
                      context.go(AppRoutes.login);
                    }
                  },
                  icon: Icon(Icons.arrow_back, color: cs.onSurface),
                  tooltip: 'Voltar',
                ),
                const SizedBox(width: 8),
                Expanded(child: Text('Recuperação', style: context.textStyles.titleLarge)),
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
            const SizedBox(height: AppSpacing.lg),
            if (_inlineMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: Text(_inlineMessage!, style: context.textStyles.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.35)),
              ),
            if (_inlineError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: Text(_inlineError!, style: context.textStyles.bodySmall?.copyWith(color: cs.error, height: 1.35)),
              ),
            PrimaryButton(onPressed: _submit, label: 'Enviar instruções', icon: Icons.email_outlined, isLoading: _loading),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
  }
}
