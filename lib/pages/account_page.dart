import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:medisom_console/auth/auth_controller.dart';
import 'package:medisom_console/sensors/models/sensor.dart';
import 'package:medisom_console/sensors/sensor_service.dart';
import 'package:medisom_console/theme.dart';
import 'package:medisom_console/utils/app_identity.dart';
import 'package:medisom_console/utils/open_portals_controller.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  final SensorService _sensorService = SensorService();
  bool _isImporting = false;

  Future<void> _importSensors() async {
    if (_isImporting) return;

    final auth = context.read<AuthController>();
    final email = (auth.user?.email ?? '').trim();
    final userId = auth.user?.id;
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('E-mail da conta não encontrado.')));
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Importar sensores'),
          content: Text(
            'Vamos buscar no servidor os sensores cadastrados para este e-mail e importar apenas os que ainda não existem no app.\n\n$email',
            style: dialogContext.textStyles.bodyMedium?.copyWith(height: 1.45),
          ),
          actions: [
            TextButton(onPressed: () => dialogContext.pop(false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => dialogContext.pop(true), child: const Text('Importar')),
          ],
        );
      },
    );

    if (ok != true || !mounted) return;

    setState(() => _isImporting = true);

    int imported = 0;
    int skipped = 0;
    int failed = 0;

    try {
      final existingSensors = await _sensorService.listSensors(email: email);
      final existingIds = existingSensors.map((s) => s.sensorId.trim()).where((s) => s.isNotEmpty).toSet();

      final ids = await _sensorService.importSensorIdsForEmail(email: email);
      if (ids.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nenhum sensor encontrado para este e-mail.')));
        return;
      }

      final deviceId = await AppIdentity.getOrCreateDeviceId();
      final finalUserId = (userId != null && userId.trim().isNotEmpty) ? userId.trim() : await AppIdentity.getOrCreateUserId();

      // Sequential import to keep server load small and simplify error handling.
      for (final rawId in ids) {
        if (!mounted) return;
        final sensorId = rawId.trim();
        if (sensorId.isEmpty) continue;
        if (existingIds.contains(sensorId)) {
          skipped++;
          continue;
        }

        try {
          final result = await _sensorService.addSensor(
            sensorId: sensorId,
            userId: finalUserId,
            deviceId: deviceId,
            email: email,
            appVersion: AppIdentity.appVersion,
            insert: true,
          );

          final now = DateTime.now();
          final sensor = Sensor(
            sensorId: result.sensorId.isNotEmpty ? result.sensorId : sensorId,
            clientId: result.clientId,
            email: email,
            portalUrl: result.portalUrl,
            local: result.local,
            enabled: result.enabled,
            lastUpdate: result.lastUpdate,
            limit: result.limit,
            weighting: result.weighting,
            percentAboveLimit: result.percentAboveLimit,
            leq1Min: result.leq1Min,
            monitor: result.monitor,
            createdAt: now,
            updatedAt: now,
          );
          await _sensorService.upsertSensor(email: email, sensor: sensor);
          existingIds.add(sensor.sensorId.trim());
          imported++;
        } catch (e) {
          failed++;
          debugPrint('AccountPage import failed for $sensorId: $e');
        }
      }

      if (!mounted) return;
      final text = 'Importação concluída: $imported importado(s), $skipped já existia(m)${failed > 0 ? ', $failed falhou(aram)' : ''}.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    } on SensorException catch (e) {
      debugPrint('AccountPage._importSensors SensorException: ${e.message}');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      debugPrint('AccountPage._importSensors failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não foi possível importar sensores.')));
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final auth = context.watch<AuthController>();

    return Scaffold(
      appBar: AppBar(title: const Text('Conta')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Padding(
            padding: AppSpacing.paddingLg,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(14)),
                        alignment: Alignment.center,
                        child: Icon(Icons.person_outline, color: cs.onPrimaryContainer),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Usuário', style: context.textStyles.titleSmall?.copyWith(height: 1.15)),
                            const SizedBox(height: 2),
                            Text(
                              auth.user?.email ?? '-',
                              style: context.textStyles.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.3),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Container(
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        leading: Icon(Icons.cloud_download_outlined, color: cs.primary),
                        title: const Text('Importar sensores'),
                        subtitle: const Text('Busca no servidor os sensores cadastrados no seu e-mail.'),
                        trailing: _isImporting
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
                              )
                            : const Icon(Icons.chevron_right),
                        onTap: _isImporting ? null : _importSensors,
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: Icon(Icons.logout, color: cs.error),
                        title: const Text('Sair'),
                        onTap: _isImporting
                            ? null
                            : () {
                                // Close any opened sensor portals so nothing stays alive between accounts.
                                context.read<OpenPortalsController>().clear();
                                context.read<AuthController>().signOut();
                              },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
