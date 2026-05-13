import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:medisom_console/auth/auth_controller.dart';
import 'package:medisom_console/theme.dart';
import 'package:medisom_console/widgets/primary_button.dart';
import 'package:medisom_console/widgets/responsive_auth_scaffold.dart';

class ConfirmEmailPage extends StatefulWidget {
  const ConfirmEmailPage({super.key});

  @override
  State<ConfirmEmailPage> createState() => _ConfirmEmailPageState();
}

class _ConfirmEmailPageState extends State<ConfirmEmailPage> {
  bool _loading = false;

  Future<void> _confirm() async {
    setState(() => _loading = true);
    try {
      await context.read<AuthController>().confirmEmailVerified();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final user = context.watch<AuthController>().user;
    return ResponsiveAuthScaffold(
      title: 'Confirme sua conta',
      subtitle: 'Validação de e-mail e confirmação de conta fazem parte do fluxo de segurança.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Confirmação', style: context.textStyles.titleLarge),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'E-mail: ${user?.email ?? '-'}',
            style: context.textStyles.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.lg),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cs.outline.withValues(alpha: 0.16)),
            ),
            child: Row(
              children: [
                Icon(Icons.mark_email_read_outlined, size: 18, color: cs.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Modo local: clique em “Confirmar e-mail” para simular a validação. Com Firebase/Supabase, isso vira um link real enviado por e-mail.',
                    style: context.textStyles.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.35),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(onPressed: _confirm, label: 'Confirmar e-mail', icon: Icons.verified_outlined, isLoading: _loading),
        ],
      ),
    );
  }
}
