import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:medisom_console/auth/auth_controller.dart';
import 'package:medisom_console/pages/company_picker_page.dart';
import 'package:medisom_console/pages/confirm_email_page.dart';
import 'package:medisom_console/pages/forgot_password_page.dart';
import 'package:medisom_console/pages/login_page.dart';
import 'package:medisom_console/pages/register_page.dart';
import 'package:medisom_console/pages/reset_password_page.dart';
import 'package:medisom_console/pages/set_password_page.dart';
import 'package:medisom_console/pages/splash_page.dart';
import 'package:medisom_console/pages/verify_code_page.dart';
import 'package:medisom_console/pages/qr_scanner_page.dart';
import 'package:medisom_console/pages/account_page.dart';
import 'package:medisom_console/pages/app_shell.dart';
import 'package:medisom_console/pages/devices_root_page.dart';
import 'package:medisom_console/pages/measurements_page.dart';

/// Used to detect route visibility (e.g., pause dashboard background refresh
/// when the user navigates to the Portal WebView).
final RouteObserver<ModalRoute<void>> appRouteObserver = RouteObserver<ModalRoute<void>>();

class AppRouter {
  static GoRouter create(AuthController auth) {
    return GoRouter(
      initialLocation: AppRoutes.splash,
      refreshListenable: auth,
      observers: [appRouteObserver],
      redirect: (context, state) {
        final status = auth.status;
        final loc = state.uri.toString();

        final isAuthRoute = loc.startsWith(AppRoutes.login) ||
            loc.startsWith(AppRoutes.register) ||
            loc.startsWith(AppRoutes.forgotPassword) ||
            loc.startsWith(AppRoutes.resetPassword) ||
            loc.startsWith(AppRoutes.confirmEmail) ||
            loc.startsWith(AppRoutes.verifyCode) ||
            loc.startsWith(AppRoutes.setPassword);

        if (status == AuthStatus.loading) return AppRoutes.splash;

        // When signed out, keep the user on Splash as a lightweight landing page
        // (with explicit actions: Login / Register). Auth pages remain accessible.
        if (status == AuthStatus.signedOut) {
          if (loc == AppRoutes.splash || isAuthRoute) return null;
          return AppRoutes.splash;
        }
        if (status == AuthStatus.needsEmailVerification) return loc == AppRoutes.confirmEmail ? null : AppRoutes.confirmEmail;
        if (status == AuthStatus.needsCompanySelection) return loc == AppRoutes.companyPicker ? null : AppRoutes.companyPicker;
        if (status == AuthStatus.signedInReady) {
          if (loc == AppRoutes.splash || isAuthRoute || loc == AppRoutes.companyPicker || loc == AppRoutes.confirmEmail) {
            return AppRoutes.devices;
          }
          if (loc == AppRoutes.dashboard) return AppRoutes.devices;
          return null;
        }
        return null;
      },
      routes: [
        GoRoute(path: AppRoutes.splash, pageBuilder: (context, state) => _fade(state, const SplashPage())),
        GoRoute(
          path: AppRoutes.login,
          pageBuilder: (context, state) {
            final initialEmail = state.uri.queryParameters['email'];
            final initialPassword = state.uri.queryParameters['password'];
            return _fade(state, LoginPage(initialEmail: initialEmail, initialPassword: initialPassword));
          },
        ),
        GoRoute(path: AppRoutes.register, pageBuilder: (context, state) => _fade(state, const RegisterPage())),
        GoRoute(
          path: AppRoutes.verifyCode,
          pageBuilder: (context, state) {
            // IMPORTANT: GoRouter `extra` is not persisted if the OS kills/restores the app
            // (this happens more often on iOS). To make this flow resilient, we also accept
            // required fields via query params.
            final extra = state.extra ?? state.uri.queryParameters;
            return _fade(state, VerifyCodePage(extra: extra));
          },
        ),
        GoRoute(
          path: AppRoutes.setPassword,
          pageBuilder: (context, state) {
            // Same resilience strategy as /verify-code.
            final extra = state.extra ?? state.uri.queryParameters;
            return _fade(state, SetPasswordPage(extra: extra));
          },
        ),
        GoRoute(path: AppRoutes.forgotPassword, pageBuilder: (context, state) => _fade(state, const ForgotPasswordPage())),
        GoRoute(
          path: AppRoutes.resetPassword,
          pageBuilder: (context, state) {
            final initialEmail = state.uri.queryParameters['email'];
            return _fade(state, ResetPasswordPage(initialEmail: initialEmail));
          },
        ),
        GoRoute(path: AppRoutes.confirmEmail, pageBuilder: (context, state) => _fade(state, const ConfirmEmailPage())),
        GoRoute(path: AppRoutes.companyPicker, pageBuilder: (context, state) => _fade(state, const CompanyPickerPage())),

        /// App shell (bottom tabs) - only used when signed in.
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) => AppShell(navigationShell: navigationShell),
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: AppRoutes.devices,
                  pageBuilder: (context, state) => _fade(state, const DevicesRootPage()),
                  routes: [
                    GoRoute(path: 'qr-scan', pageBuilder: (context, state) => _fade(state, const QrScannerPage())),
                  ],
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(path: AppRoutes.measurements, pageBuilder: (context, state) => _fade(state, const MeasurementsPage())),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(path: AppRoutes.account, pageBuilder: (context, state) => _fade(state, const AccountPage())),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

CustomTransitionPage<void> _fade(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.02), end: Offset.zero).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class AppRoutes {
  static const splash = '/splash';
  static const login = '/login';
  static const register = '/register';
  static const verifyCode = '/verify-code';
  static const setPassword = '/set-password';
  static const forgotPassword = '/forgot-password';
  static const resetPassword = '/reset-password';
  static const confirmEmail = '/confirm-email';
  static const companyPicker = '/company';
  static const dashboard = '/dashboard'; // legacy

  // Tab routes
  static const devices = '/app/devices';
  static const measurements = '/app/measurements';
  static const account = '/app/account';

  // Nested tab routes
  static const qrScan = '/app/devices/qr-scan';
}
