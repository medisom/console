import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

class SavedCredentials {
  final String email;
  final String password;

  const SavedCredentials({required this.email, required this.password});
}

/// Handles biometric-gated retrieval of stored credentials.
///
/// Notes:
/// - Credentials are stored in OS secure storage (Keychain/Keystore).
/// - Retrieval is protected by a biometric prompt via `local_auth`.
/// - On Web (or unsupported devices), operations gracefully no-op.
class BiometricCredentialsService {
  static const _kEmailKey = 'biometric_login.email.v1';
  static const _kPasswordKey = 'biometric_login.password.v1';
  static const _kEnabledKey = 'biometric_login.enabled.v1';

  final LocalAuthentication _auth;
  final FlutterSecureStorage _storage;

  BiometricCredentialsService({LocalAuthentication? auth, FlutterSecureStorage? storage})
      : _auth = auth ?? LocalAuthentication(),
        _storage = storage ?? const FlutterSecureStorage();

  Future<bool> isSupported() async {
    if (kIsWeb) return false;
    try {
      final supported = await _auth.isDeviceSupported();
      final canCheck = await _auth.canCheckBiometrics;
      return supported && canCheck;
    } catch (e) {
      debugPrint('BiometricCredentialsService.isSupported failed: $e');
      return false;
    }
  }

  Future<bool> hasSavedCredentials() async {
    if (kIsWeb) return false;
    try {
      final enabled = (await _storage.read(key: _kEnabledKey)) == 'true';
      if (!enabled) return false;
      final email = await _storage.read(key: _kEmailKey);
      final password = await _storage.read(key: _kPasswordKey);
      return (email != null && email.trim().isNotEmpty) && (password != null && password.isNotEmpty);
    } catch (e) {
      debugPrint('BiometricCredentialsService.hasSavedCredentials failed: $e');
      return false;
    }
  }

  Future<void> enableAndSaveCredentials({required String email, required String password}) async {
    if (kIsWeb) return;
    try {
      await _storage.write(key: _kEmailKey, value: email.trim());
      await _storage.write(key: _kPasswordKey, value: password);
      await _storage.write(key: _kEnabledKey, value: 'true');
    } catch (e) {
      debugPrint('BiometricCredentialsService.enableAndSaveCredentials failed: $e');
      rethrow;
    }
  }

  Future<void> disable() async {
    if (kIsWeb) return;
    try {
      await _storage.write(key: _kEnabledKey, value: 'false');
    } catch (e) {
      debugPrint('BiometricCredentialsService.disable failed: $e');
    }
  }

  Future<SavedCredentials?> authenticateAndLoad({String? reason}) async {
    if (kIsWeb) return null;
    try {
      final has = await hasSavedCredentials();
      if (!has) return null;

      // On Android, some devices show an extra confirmation step (“Validado. Toque em Confirmar…”)
      // when the prompt is treated as a *sensitive transaction*.
      // We explicitly disable that so biometrics returns success immediately.
      final ok = await _auth.authenticate(
        localizedReason: (reason?.trim().isNotEmpty ?? false)
            ? reason!.trim()
            : 'Confirme sua identidade para entrar automaticamente.',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: false,
          sensitiveTransaction: false,
        ),
      );
      if (!ok) return null;

      final email = (await _storage.read(key: _kEmailKey) ?? '').trim();
      final password = (await _storage.read(key: _kPasswordKey) ?? '');
      if (email.isEmpty || password.isEmpty) return null;
      return SavedCredentials(email: email, password: password);
    } catch (e) {
      debugPrint('BiometricCredentialsService.authenticateAndLoad failed: $e');
      return null;
    }
  }
}
