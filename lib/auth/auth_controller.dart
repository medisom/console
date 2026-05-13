import 'package:flutter/foundation.dart';

import 'package:medisom_console/auth/local_auth_service.dart';
import 'package:medisom_console/auth/models/app_user.dart';
import 'package:medisom_console/company/company_service.dart';
import 'package:medisom_console/utils/webview_data.dart';

enum AuthStatus { loading, signedOut, needsEmailVerification, needsCompanySelection, signedInReady }

class AuthController extends ChangeNotifier {
  final LocalAuthService _auth = LocalAuthService();
  final CompanyService _companyService = CompanyService();

  AuthStatus _status = AuthStatus.loading;
  AuthStatus get status => _status;

  AppUser? _user;
  AppUser? get user => _user;

  String? _selectedCompanyId;
  String? get selectedCompanyId => _selectedCompanyId;

  Future<void> initialize() async {
    _status = AuthStatus.loading;
    notifyListeners();
    try {
      await _auth.seedIfNeeded();
      await refreshFromStorage(showLoading: false);
    } catch (e) {
      debugPrint('AuthController.initialize failed: $e');
      _user = null;
      _selectedCompanyId = null;
      _status = AuthStatus.signedOut;
      notifyListeners();
    }
  }

  /// Reloads the persisted session (if any) from local storage.
  ///
  /// This is used for:
  /// - app start (cold start)
  /// - returning from background (in case the controller was recreated)
  Future<void> refreshFromStorage({bool showLoading = false}) async {
    if (showLoading) {
      _status = AuthStatus.loading;
      notifyListeners();
    }

    try {
      _user = await _auth.getSessionUser();
      _selectedCompanyId = await _companyService.getSelectedCompanyId();
      _recomputeStatus();
    } catch (e) {
      debugPrint('AuthController.refreshFromStorage failed: $e');
      _user = null;
      _selectedCompanyId = null;
      _status = AuthStatus.signedOut;
    } finally {
      notifyListeners();
    }
  }

  Future<void> signIn({required String email, required String password}) async {
    _status = AuthStatus.loading;
    notifyListeners();
    try {
      _user = await _auth.signInWithEmailPassword(email: email, password: password);
      _selectedCompanyId = await _companyService.getSelectedCompanyId();
      _recomputeStatus();
    } catch (e) {
      // Important: when sign-in fails we must leave the loading state,
      // otherwise the router will redirect to /splash (loading) indefinitely.
      debugPrint('AuthController.signIn failed: $e');
      _user = null;
      _selectedCompanyId = null;
      _status = AuthStatus.signedOut;
      rethrow;
    } finally {
      notifyListeners();
    }
  }

  Future<void> register({required String email, required String password, required String displayName}) async {
    _status = AuthStatus.loading;
    notifyListeners();
    try {
      _user = await _auth.registerWithEmailPassword(email: email, password: password, displayName: displayName);
      _selectedCompanyId = await _companyService.getSelectedCompanyId();
      _recomputeStatus();
    } finally {
      notifyListeners();
    }
  }

  Future<void> confirmEmailVerified() async {
    final current = _user;
    if (current == null) return;

    _status = AuthStatus.loading;
    notifyListeners();
    try {
      _user = await _auth.markEmailVerified(userId: current.id);
      _recomputeStatus();
    } finally {
      notifyListeners();
    }
  }

  Future<String?> sendPasswordReset({required String email}) async {
    try {
      return await _auth.sendPasswordResetEmail(email: email);
    } catch (e) {
      debugPrint('AuthController.sendPasswordReset failed: $e');
      rethrow;
    }
  }

  Future<void> resetPassword({required String email, required String resetToken, required String newPassword}) async {
    try {
      await _auth.resetPassword(email: email, resetToken: resetToken, newPassword: newPassword);
    } catch (e) {
      debugPrint('AuthController.resetPassword failed: $e');
      rethrow;
    }
  }

  Future<void> selectCompany(String companyId) async {
    _selectedCompanyId = companyId;
    notifyListeners();
    await _companyService.setSelectedCompanyId(companyId);
    _recomputeStatus();
    notifyListeners();
  }

  Future<void> signOut() async {
    _status = AuthStatus.loading;
    notifyListeners();
    try {
      // Important: WebView cookies/session are shared across accounts on Android.
      // Clearing them avoids the "Medições" WebView reusing a previous account session.
      await clearWebViewData();
      await _auth.signOut();
      _user = null;
      _selectedCompanyId = null;
      _status = AuthStatus.signedOut;
    } finally {
      notifyListeners();
    }
  }

  void _recomputeStatus() {
    final u = _user;
    if (u == null) {
      _status = AuthStatus.signedOut;
      return;
    }
    if (!u.emailVerified) {
      _status = AuthStatus.needsEmailVerification;
      return;
    }
    if (u.companyIds.length > 1 && (_selectedCompanyId == null || _selectedCompanyId!.isEmpty)) {
      _status = AuthStatus.needsCompanySelection;
      return;
    }
    if (u.companyIds.isNotEmpty && (_selectedCompanyId == null || _selectedCompanyId!.isEmpty)) {
      _selectedCompanyId = u.companyIds.first;
      _companyService.setSelectedCompanyId(_selectedCompanyId!);
    }
    _status = AuthStatus.signedInReady;
  }
}
