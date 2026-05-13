import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:medisom_console/auth/auth_controller.dart';
import 'package:medisom_console/company/company_service.dart';
import 'package:medisom_console/company/models/company.dart';
import 'package:medisom_console/theme.dart';
import 'package:medisom_console/widgets/primary_button.dart';

class CompanyPickerPage extends StatefulWidget {
  const CompanyPickerPage({super.key});

  @override
  State<CompanyPickerPage> createState() => _CompanyPickerPageState();
}

class _CompanyPickerPageState extends State<CompanyPickerPage> {
  final CompanyService _companyService = CompanyService();
  String? _selected;
  bool _loading = false;

  Future<void> _continue() async {
    final selected = _selected;
    if (selected == null) return;
    setState(() => _loading = true);
    try {
      await context.read<AuthController>().selectCompany(selected);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final auth = context.watch<AuthController>();
    final allowedCompanyIds = auth.user?.companyIds ?? const <String>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Selecionar empresa'),
        actions: [
          TextButton(
            onPressed: () => context.read<AuthController>().signOut(),
            child: Text('Sair', style: TextStyle(color: cs.primary)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: FutureBuilder<List<Company>>(
        future: _companyService.listCompanies(),
        builder: (context, snapshot) {
          final all = snapshot.data ?? const <Company>[];
          final companies = all.where((c) => allowedCompanyIds.contains(c.id)).toList();

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Padding(
                padding: AppSpacing.paddingLg,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Você tem acesso a mais de uma empresa.', style: context.textStyles.titleLarge),
                    const SizedBox(height: AppSpacing.sm),
                    Text('Escolha uma para continuar.', style: context.textStyles.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                    const SizedBox(height: AppSpacing.lg),
                    Expanded(
                      child: ListView.separated(
                        itemCount: companies.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final c = companies[index];
                          final selected = _selected == c.id;
                          return _CompanyTile(
                            company: c,
                            selected: selected,
                            onTap: () => setState(() => _selected = c.id),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    PrimaryButton(
                      onPressed: _selected == null ? null : _continue,
                      label: 'Continuar',
                      icon: Icons.arrow_forward,
                      isLoading: _loading,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CompanyTile extends StatelessWidget {
  const _CompanyTile({required this.company, required this.selected, required this.onTap});
  final Company company;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? cs.primary.withValues(alpha: 0.10) : cs.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: selected ? cs.primary.withValues(alpha: 0.35) : cs.outline.withValues(alpha: 0.16)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.business_outlined, color: cs.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(company.name, style: context.textStyles.titleMedium),
                  const SizedBox(height: 2),
                  Text('Ambientes • Setores • Dispositivos', style: context.textStyles.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Icon(selected ? Icons.check_circle : Icons.circle_outlined, color: selected ? cs.primary : cs.outline),
          ],
        ),
      ),
    );
  }
}
