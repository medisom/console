import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:medisom_console/auth/auth_controller.dart';
import 'package:medisom_console/nav.dart';
import 'package:medisom_console/sensors/models/sensor.dart';
import 'package:medisom_console/sensors/sensor_service.dart';
import 'package:medisom_console/theme.dart';
import 'package:medisom_console/utils/open_portals_controller.dart';
import 'package:medisom_console/utils/app_identity.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with WidgetsBindingObserver, RouteAware {
  final SensorService _sensorService = SensorService();

  String _currentEmail = '';

  Timer? _refreshTimer;
  bool _isRefreshingAll = false;

  bool _isRouteVisible = false;
  bool _isAppResumed = true;

  bool _isLoading = true;
  bool _isAdding = false;
  String? _error;
  List<Sensor> _sensors = const [];

  bool _cameraPermissionGranted = true;
  bool _checkingCameraPermission = false;

  late final VoidCallback _sensorsRevisionListener;

  static const String _prefsKeyCameraPromptShown =
      'camera_permission_prompt_shown_v1';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // When sensors are changed from another tab/page (e.g. import on Account tab),
    // refresh the list immediately so user doesn't need to close the app.
    _sensorsRevisionListener = () {
      if (!mounted) return;
      final email = (context.read<AuthController>().user?.email ?? '').trim();
      if (email.isEmpty) return;
      _loadInternal(showLoading: false);
    };
    SensorService.sensorsRevision.addListener(_sensorsRevisionListener);

    _load();

    // Ensure we only show dialogs after the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndMaybePromptCameraPermission();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SensorService.sensorsRevision.removeListener(_sensorsRevisionListener);
    try {
      appRouteObserver.unsubscribe(this);
    } catch (_) {
      // ignore
    }
    _refreshTimer?.cancel();
    _refreshTimer = null;
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // If the logged user changes (logout/login), refresh the local list for that account.
    final auth = context.watch<AuthController>();
    final nextEmail = (auth.user?.email ?? '').trim().toLowerCase();
    if (nextEmail != _currentEmail) {
      _currentEmail = nextEmail;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _load();
      });
    }

    final route = ModalRoute.of(context);
    if (route != null) {
      appRouteObserver.subscribe(this, route);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isAppResumed = state == AppLifecycleState.resumed;
    _syncAutoRefresh();
  }

  @override
  void didPush() {
    _isRouteVisible = true;
    _syncAutoRefresh(triggerImmediate: true);
  }

  @override
  void didPopNext() {
    // Returned to dashboard from another route.
    _isRouteVisible = true;
    _syncAutoRefresh(triggerImmediate: true);
  }

  @override
  void didPushNext() {
    // Another route covered the dashboard (e.g., Portal WebView).
    _isRouteVisible = false;
    _syncAutoRefresh();
  }

  @override
  void didPop() {
    _isRouteVisible = false;
    _syncAutoRefresh();
  }

  bool get _canAutoRefresh => mounted && _isRouteVisible && _isAppResumed;

  void _syncAutoRefresh({bool triggerImmediate = false}) {
    if (!_canAutoRefresh) {
      _refreshTimer?.cancel();
      _refreshTimer = null;
      return;
    }

    _refreshTimer ??= Timer.periodic(const Duration(minutes: 1), (_) {
      if (!_canAutoRefresh) return;
      _refreshAllSensors();
    });

    if (triggerImmediate) {
      // Refresh when arriving at dashboard (or coming back) to keep values fresh.
      _refreshAllSensors();
    }
  }

  Future<void> _checkAndMaybePromptCameraPermission() async {
    if (kIsWeb) return; // Web handles camera permissions differently.
    if (_checkingCameraPermission) return;
    _checkingCameraPermission = true;

    try {
      final status = await Permission.camera.status;
      final isGranted = status.isGranted;

      if (mounted) {
        setState(() => _cameraPermissionGranted = isGranted);
      }

      if (isGranted || !mounted) return;

      // Avoid nagging: show the explanatory dialog only once per install.
      final prefs = await SharedPreferences.getInstance();
      final alreadyShown = prefs.getBool(_prefsKeyCameraPromptShown) ?? false;
      if (alreadyShown) return;

      if (!mounted) return;

      final shouldRequest = await showDialog<bool>(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) {
          final cs = Theme.of(dialogContext).colorScheme;
          return AlertDialog(
            title: const Text('Permitir câmera?'),
            content: Text(
              'A câmera será usada para ler QR Codes dos dispositivos Medisom.',
              style: dialogContext.textStyles.bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant, height: 1.45),
            ),
            actions: [
              TextButton(
                  onPressed: () => dialogContext.pop(false),
                  child: const Text('Agora não')),
              FilledButton(
                onPressed: () => dialogContext.pop(true),
                style: FilledButton.styleFrom(backgroundColor: cs.primary),
                child: Text('Permitir', style: TextStyle(color: cs.onPrimary)),
              ),
            ],
          );
        },
      );

      await prefs.setBool(_prefsKeyCameraPromptShown, true);
      if (shouldRequest != true || !mounted) return;

      final requestStatus = await Permission.camera.request();
      if (!mounted) return;
      setState(() => _cameraPermissionGranted = requestStatus.isGranted);
    } catch (e) {
      debugPrint(
          'DashboardPage._checkAndMaybePromptCameraPermission failed: $e');
      // If permission checks fail (plugin issues), don't block dashboard usage.
      if (mounted) setState(() => _cameraPermissionGranted = true);
    } finally {
      _checkingCameraPermission = false;
    }
  }

  Future<void> _requestCameraPermissionFromBanner() async {
    if (kIsWeb) return;
    try {
      final status = await Permission.camera.request();
      if (!mounted) return;
      setState(() => _cameraPermissionGranted = status.isGranted);

      if (!status.isGranted && status.isPermanentlyDenied) {
        final ok = await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            final cs = Theme.of(dialogContext).colorScheme;
            return AlertDialog(
              title: const Text('Câmera bloqueada'),
              content: Text(
                'A permissão de câmera está bloqueada nas configurações do sistema.\n\nAbra as configurações do app para liberar a câmera e conseguir escanear QR Codes.',
                style: dialogContext.textStyles.bodyMedium
                    ?.copyWith(color: cs.onSurfaceVariant, height: 1.45),
              ),
              actions: [
                TextButton(
                    onPressed: () => dialogContext.pop(false),
                    child: const Text('Fechar')),
                FilledButton(
                  onPressed: () => dialogContext.pop(true),
                  style: FilledButton.styleFrom(backgroundColor: cs.primary),
                  child: Text('Abrir configurações',
                      style: TextStyle(color: cs.onPrimary)),
                ),
              ],
            );
          },
        );
        if (ok == true) {
          final opened = await openAppSettings();
          debugPrint('openAppSettings result: $opened');
        }
      }
    } catch (e) {
      debugPrint('DashboardPage._requestCameraPermissionFromBanner failed: $e');
    }
  }

  Future<void> _load() => _loadInternal(showLoading: true);

  Future<void> _loadInternal({required bool showLoading}) async {
    final email = (context.read<AuthController>().user?.email ?? '').trim();
    if (showLoading) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    } else {
      _error = null;
    }
    try {
      if (email.isEmpty) {
        if (!mounted) return;
        setState(() => _sensors = const []);
        return;
      }

      final items = await _sensorService.listSensors(email: email);
      if (!mounted) return;
      setState(() => _sensors = items);

      // Requirement: refresh when user enters the dashboard.
      // Only do it when the dashboard is actually visible and app is foreground.
      if (_canAutoRefresh) {
        _refreshAllSensors();
      }
    } catch (e) {
      debugPrint('DashboardPage._load failed: $e');
      if (!mounted) return;
      setState(() => _error = 'Não foi possível carregar os sensores.');
    } finally {
      if (mounted && showLoading) setState(() => _isLoading = false);
    }
  }

  bool _isSensorOnline(Sensor s) {
    final last = s.lastUpdate;
    if (last == null) return false;
    try {
      final diff = DateTime.now().difference(last.toLocal());
      // Online if last transmission happened within the last 2 minutes.
      return diff.inSeconds <= 120;
    } catch (_) {
      return false;
    }
  }

  Future<void> _refreshAllSensors() async {
    if (_isRefreshingAll) return;
    if (!mounted) return;
    if (!_canAutoRefresh) return;
    if (_sensors.isEmpty) return;

    setState(() => _isRefreshingAll = true);
    try {
      final auth = context.read<AuthController>();
      final email = auth.user?.email ?? '';
      final userId = auth.user?.id;

      if (email.trim().isEmpty) return;

      final deviceId = await AppIdentity.getOrCreateDeviceId();
      final finalUserId = (userId != null && userId.trim().isNotEmpty)
          ? userId.trim()
          : await AppIdentity.getOrCreateUserId();

      // Sequential POSTs: one by one.
      for (final existing in List<Sensor>.from(_sensors)) {
        if (!mounted) return;
        try {
          final result = await _sensorService.addSensor(
            sensorId: existing.sensorId,
            userId: finalUserId,
            deviceId: deviceId,
            email: email,
            appVersion: AppIdentity.appVersion,
            insert: false,
          );

          final now = DateTime.now();
          final updated = existing.copyWith(
            sensorId: result.sensorId.isNotEmpty
                ? result.sensorId
                : existing.sensorId,
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
            updatedAt: now,
          );
          await _sensorService.upsertSensor(email: email, sensor: updated);
        } catch (e) {
          // Keep refreshing the remaining sensors even if one fails.
          debugPrint(
              'DashboardPage._refreshAllSensors failed for ${existing.sensorId}: $e');
        }
      }

      final refreshed = await _sensorService.listSensors(email: email);
      if (!mounted) return;
      setState(() => _sensors = refreshed);
    } catch (e) {
      debugPrint('DashboardPage._refreshAllSensors failed: $e');
    } finally {
      if (mounted) setState(() => _isRefreshingAll = false);
    }
  }

  Future<void> _openAddSensorSheet(BuildContext context) async {
    final cs = Theme.of(context).colorScheme;
    final router = GoRouter.of(context);

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: cs.surface,
      constraints: const BoxConstraints(maxWidth: 720),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Adicionar sensor',
                    style:
                        context.textStyles.titleMedium?.copyWith(height: 1.2)),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Escolha como você deseja cadastrar um novo sensor.',
                  style: context.textStyles.bodyMedium
                      ?.copyWith(color: cs.onSurfaceVariant, height: 1.45),
                ),
                const SizedBox(height: AppSpacing.md),
                _SheetActionTile(
                  icon: Icons.qr_code_scanner,
                  title: 'Escanear código QR',
                  subtitle: 'Use a câmera para ler o QR-code do sensor.',
                  onTap: () async {
                    // Close sheet first to avoid context issues.
                    router.pop();
                    final scanned = await _scanQr(router);
                    if (!context.mounted) return;
                    if (scanned == null || scanned.trim().isEmpty) return;
                    await _addSensorFromQr(scanned.trim());
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<String?> _scanQr(GoRouter router) async {
    try {
      return await router.push<String>(AppRoutes.qrScan);
    } catch (e) {
      debugPrint('DashboardPage._scanQr failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Não foi possível abrir o leitor de QR.')),
        );
      }
      return null;
    }
  }

  Future<void> _addSensorFromQr(String qrValue) async {
    final trimmedQr = qrValue.trim();
    if (trimmedQr.isEmpty) return;

    final auth = context.read<AuthController>();
    final email = (auth.user?.email ?? '').trim();
    final userId = auth.user?.id;
    if (email.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('E-mail da conta não encontrado.')));
      }
      return;
    }

    // Prevent adding a sensor that is already stored locally.
    try {
      final alreadyInMemory =
          _sensors.any((s) => s.sensorId.trim() == trimmedQr);
      if (alreadyInMemory) {
        if (!mounted) return;
        await _showSensorAlreadyExistsDialog(trimmedQr);
        return;
      }

      final stored = await _sensorService.listSensors(email: email);
      final alreadyStored = stored.any((s) => s.sensorId.trim() == trimmedQr);
      if (alreadyStored) {
        if (!mounted) return;
        await _showSensorAlreadyExistsDialog(trimmedQr);
        return;
      }
    } catch (e) {
      debugPrint('DashboardPage._addSensorFromQr duplicate check failed: $e');
      // If the check fails for any reason, keep the flow going.
    }

    if (_isAdding) return;
    setState(() {
      _isAdding = true;
      _error = null;
    });

    try {
      final deviceId = await AppIdentity.getOrCreateDeviceId();
      final finalUserId = (userId != null && userId.trim().isNotEmpty)
          ? userId.trim()
          : await AppIdentity.getOrCreateUserId();

      final result = await _sensorService.addSensor(
        sensorId: trimmedQr,
        userId: finalUserId,
        deviceId: deviceId,
        email: email,
        appVersion: AppIdentity.appVersion,
        insert: true,
      );

      final now = DateTime.now();
      final sensor = Sensor(
        sensorId: result.sensorId.isNotEmpty ? result.sensorId : trimmedQr,
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
      final refreshed = await _sensorService.listSensors(email: email);
      if (!mounted) return;
      setState(() => _sensors = refreshed);
    } on SensorException catch (e) {
      debugPrint(
          'DashboardPage._addSensorFromQr SensorException: ${e.message}');
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      debugPrint('DashboardPage._addSensorFromQr failed: $e');
      if (!mounted) return;
      setState(() => _error = 'Não foi possível adicionar o sensor.');
    } finally {
      if (mounted) setState(() => _isAdding = false);
    }
  }

  Future<void> _showSensorAlreadyExistsDialog(String sensorId) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Sensor já cadastrado'),
          content: Text(
            'Este sensor já está cadastrado no seu app.\n\n$sensorId',
            style: dialogContext.textStyles.bodyMedium?.copyWith(height: 1.45),
          ),
          actions: [
            TextButton(
              onPressed: () => dialogContext.pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openSensor(Sensor sensor) async {
    try {
      final url = sensor.portalUrl.trim();
      if (url.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Este sensor não possui URL de portal.')));
        return;
      }
      context.read<OpenPortalsController>().openOrActivate(
          sensorId: sensor.sensorId, url: url, title: sensor.clientId);
    } catch (e) {
      debugPrint('DashboardPage._openSensor failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Não foi possível abrir o sensor.')));
      }
    }
  }

  Future<void> _confirmAndDeleteSensor(Sensor sensor) async {
    final cs = Theme.of(context).colorScheme;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Excluir sensor?'),
          content: Text(
            'Deseja excluir este sensor do seu app?\n\n${sensor.clientId.isNotEmpty ? sensor.clientId : sensor.sensorId}',
            style: dialogContext.textStyles.bodyMedium?.copyWith(height: 1.45),
          ),
          actions: [
            TextButton(
              onPressed: () => dialogContext.pop(false),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => dialogContext.pop(true),
              style: TextButton.styleFrom(foregroundColor: cs.error),
              child: const Text('Excluir'),
            ),
          ],
        );
      },
    );

    if (ok != true) return;

    if (!mounted) return;

    try {
      final email = (context.read<AuthController>().user?.email ?? '').trim();
      if (email.isEmpty) return;
      await _sensorService.deleteSensor(
          email: email, sensorId: sensor.sensorId);
      final refreshed = await _sensorService.listSensors(email: email);
      if (!mounted) return;
      setState(() => _sensors = refreshed);
    } catch (e) {
      debugPrint('DashboardPage._confirmAndDeleteSensor failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível excluir o sensor.')));
    }
  }

  Future<void> _showSensorDetailsDialog(Sensor sensor) async {
    String formatPtBrDateTime(DateTime? dt) {
      if (dt == null) return '-';
      try {
        final local = dt.toLocal();
        String two(int n) => n.toString().padLeft(2, '0');
        return '${two(local.day)}/${two(local.month)}/${local.year} ${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
      } catch (_) {
        return '-';
      }
    }

    String formatNum(double? v) {
      if (v == null) return '-';
      final s = v.toString();
      if (s.endsWith('.0')) return s.substring(0, s.length - 2);
      return s;
    }

    String formatStatus(bool enabled) => enabled ? 'enable' : 'disable';

    String formatMonitor(String v) {
      final normalized = v.trim().toUpperCase();
      if (normalized == 'OFF') return 'Desligado';
      if (normalized == 'ON') return 'Ligado';
      return v.trim().isEmpty ? '-' : v.trim();
    }

    String formatWithUnit(double? v) {
      final base = formatNum(v);
      if (base == '-') return base;
      final unit = sensor.weighting.trim();
      return unit.isEmpty ? base : '$base $unit';
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final cs = Theme.of(dialogContext).colorScheme;
        final labelStyle = dialogContext.textStyles.bodySmall
            ?.copyWith(color: cs.onSurfaceVariant, height: 1.25);
        final valueStyle = dialogContext.textStyles.bodySmall?.copyWith(
            color: cs.onSurface, height: 1.25, fontWeight: FontWeight.w600);

        Widget row(String label, String value) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 140, child: Text(label, style: labelStyle)),
                const SizedBox(width: 10),
                Expanded(child: Text(value, style: valueStyle))
              ],
            ),
          );
        }

        return AlertDialog(
          title: const Text('Detalhes do sensor'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  row('Sensor:', sensor.sensorId),
                  row('Status:', formatStatus(sensor.enabled)),
                  row('Ultimo update:', formatPtBrDateTime(sensor.lastUpdate)),
                  row('Limite:', formatWithUnit(sensor.limit)),
                  row('% Acima do Limite:',
                      formatNum(sensor.percentAboveLimit)),
                  row('Leq(1min):', formatWithUnit(sensor.leq1Min)),
                  row('Monitor:', formatMonitor(sensor.monitor)),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => dialogContext.pop(), child: const Text('OK')),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sensores Medisom'),
        actions: [
          IconButton(
            tooltip: 'Adicionar sensor',
            onPressed: _isAdding ? null : () => _openAddSensorSheet(context),
            icon: Icon(Icons.add, color: cs.onSurface),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Padding(
            padding: AppSpacing.paddingLg,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!_cameraPermissionGranted) ...[
                  _CameraPermissionBanner(
                      onEnable: _requestCameraPermissionFromBanner),
                  const SizedBox(height: AppSpacing.md),
                ],
                if (_error != null) ...[
                  _InlineError(message: _error!),
                  const SizedBox(height: AppSpacing.md),
                ],
                Expanded(
                  child: _isLoading
                      ? Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.4, color: cs.primary),
                          ),
                        )
                      : _sensors.isEmpty
                          ? _EmptyState(isAdding: _isAdding)
                          : ListView.separated(
                              itemCount: _sensors.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: AppSpacing.md),
                              itemBuilder: (context, i) {
                                final s = _sensors[i];
                                return _SensorTile(
                                  sensor: s,
                                  isOnline: _isSensorOnline(s),
                                  onTap: () => _openSensor(s),
                                  onDetails: () => _showSensorDetailsDialog(s),
                                  onDelete: () => _confirmAndDeleteSensor(s),
                                );
                              },
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

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.isAdding});

  final bool isAdding;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.sensors, size: 44, color: cs.onSurfaceVariant),
            const SizedBox(height: AppSpacing.md),
            Text('Nenhum sensor cadastrado',
                style: context.textStyles.titleMedium,
                textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.sm),
            Text(
              isAdding
                  ? 'Estamos cadastrando o seu sensor...'
                  : 'Toque em "+" para adicionar um sensor',
              textAlign: TextAlign.center,
              style: context.textStyles.bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }
}

class _SensorTile extends StatelessWidget {
  const _SensorTile(
      {required this.sensor,
      required this.isOnline,
      required this.onTap,
      required this.onDelete,
      required this.onDetails});

  final Sensor sensor;
  final bool isOnline;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(14)),
                alignment: Alignment.center,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Align(
                        child: Icon(Icons.wifi_tethering,
                            color: cs.onPrimaryContainer)),
                    if (isOnline)
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                            border: Border.all(color: cs.surface, width: 2),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sensor.clientId,
                      style:
                          context.textStyles.titleSmall?.copyWith(height: 1.15),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sensor.local.trim().isNotEmpty
                          ? sensor.local.trim()
                          : sensor.sensorId,
                      style: context.textStyles.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Opções',
                onSelected: (v) {
                  if (v == 'details') onDetails();
                  if (v == 'delete') onDelete();
                },
                itemBuilder: (context) {
                  return [
                    PopupMenuItem<String>(
                      value: 'details',
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: cs.onSurfaceVariant),
                          const SizedBox(width: 8),
                          const Text('Resumo'),
                        ],
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline, color: cs.error),
                          const SizedBox(width: 8),
                          const Text('Excluir'),
                        ],
                      ),
                    ),
                  ];
                },
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                  child: Icon(Icons.more_vert, color: cs.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: cs.errorContainer.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: cs.error.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: cs.onErrorContainer),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: context.textStyles.bodyMedium
                  ?.copyWith(color: cs.onErrorContainer, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraPermissionBanner extends StatelessWidget {
  const _CameraPermissionBanner({required this.onEnable});

  final VoidCallback onEnable;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.camera_alt_outlined, color: cs.onSurfaceVariant),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Câmera desativada',
                    style:
                        context.textStyles.titleSmall?.copyWith(height: 1.15)),
                const SizedBox(height: 4),
                Text(
                  'Para escanear o QR-code do sensor, o app precisa de acesso à câmera.',
                  style: context.textStyles.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant, height: 1.35),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          FilledButton(
            onPressed: onEnable,
            style: FilledButton.styleFrom(
              backgroundColor: cs.primary,
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md, vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.lg)),
            ),
            child: Text('Ativar', style: TextStyle(color: cs.onPrimary)),
          ),
        ],
      ),
    );
  }
}

class _SheetActionTile extends StatelessWidget {
  const _SheetActionTile(
      {required this.icon,
      required this.title,
      required this.subtitle,
      required this.onTap});

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        // Keep modern feel: no splash/highlight.
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: cs.onPrimaryContainer),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: context.textStyles.titleSmall
                            ?.copyWith(height: 1.15)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: context.textStyles.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant, height: 1.3)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
