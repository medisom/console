import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:medisom_console/auth/auth_controller.dart';
import 'package:medisom_console/nav.dart';
import 'package:medisom_console/theme.dart';
import 'package:medisom_console/utils/fullscreen_controller.dart';
import 'package:medisom_console/utils/open_portals_controller.dart';

/// Main entry point for the application
///
/// This sets up:
/// - go_router navigation
/// - Material 3 theming with light/dark modes
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Default to portrait, then adjust dynamically at runtime (tablet vs phone).
  // This prevents an initial orientation "jump" on app start.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  late final AuthController _auth;
  bool? _rotationEnabled;
  bool _orientationUpdateScheduled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _auth = AuthController()..initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _auth.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When resuming, re-check the persisted session so the app can automatically
    // return to the dashboard without requiring user interaction.
    if (state == AppLifecycleState.resumed) {
      _auth.refreshFromStorage(showLoading: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _auth),
        ChangeNotifierProvider(create: (_) => OpenPortalsController()),
        ChangeNotifierProvider(create: (_) => FullscreenController()..initialize()),
      ],
      child: Builder(
        builder: (context) {
          final auth = context.read<AuthController>();
          return MaterialApp.router(
            title: 'Medisom Console',
            debugShowCheckedModeBanner: false,
            theme: lightTheme,
            darkTheme: darkTheme,
            themeMode: ThemeMode.system,
            routerConfig: AppRouter.create(auth),
            builder: (context, child) {
              _scheduleOrientationPolicyUpdate(context);
              return child ?? const SizedBox.shrink();
            },
          );
        },
      ),
    );
  }

  void _scheduleOrientationPolicyUpdate(BuildContext context) {
    if (_orientationUpdateScheduled) return;
    _orientationUpdateScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _orientationUpdateScheduled = false;
      if (!mounted) return;

      final mq = MediaQuery.maybeOf(context);
      if (mq == null) return;

      // A common heuristic: >= 600dp shortestSide is considered a tablet.
      final shortestSide = mq.size.shortestSide;
      final isTablet = shortestSide >= 600;
      await _applyRotationPolicy(rotationEnabled: isTablet);
    });
  }

  Future<void> _applyRotationPolicy({required bool rotationEnabled}) async {
    if (_rotationEnabled == rotationEnabled) return;
    _rotationEnabled = rotationEnabled;

    try {
      if (rotationEnabled) {
        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      } else {
        await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      }
    } catch (e) {
      // Best-effort: orientation policy shouldn't crash the app.
      debugPrint('Failed to apply orientation policy: $e');
    }
  }
}
