import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:medisom_console/auth/models/app_user.dart';
import 'package:medisom_console/utils/app_identity.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalAuthService {
  static const usersKey = 'auth.users.v1';
  static const sessionKey = 'auth.session.userId.v1';
  static const sessionUserKey = 'auth.session.user.v2';

  Future<void> seedIfNeeded() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(usersKey);
      if (raw != null && raw.isNotEmpty) return;

      // Sem usuário inicial pré-criado.
      await prefs.setString(usersKey, jsonEncode(<Map<String, dynamic>>[]));
    } catch (e) {
      debugPrint('LocalAuthService.seedIfNeeded failed: $e');
    }
  }

  Future<AppUser?> getSessionUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();

       // New format: store the full session user payload.
       final sessionUserRaw = prefs.getString(sessionUserKey);
       if (sessionUserRaw != null && sessionUserRaw.trim().isNotEmpty) {
         try {
           final decoded = jsonDecode(sessionUserRaw);
           if (decoded is Map<String, dynamic>) return AppUser.fromJson(decoded);
         } catch (e) {
           debugPrint('LocalAuthService.getSessionUser sessionUser decode failed: $e');
         }
       }

      final userId = prefs.getString(sessionKey);
      if (userId == null || userId.isEmpty) return null;
      final users = await _loadUsers(prefs);
      final record = users.cast<Map<String, dynamic>?>().firstWhere(
        (r) => (r?['user'] as Map?)?['id'] == userId,
        orElse: () => null,
      );
      if (record == null) return null;
      return AppUser.fromJson((record['user'] as Map).cast<String, dynamic>());
    } catch (e) {
      debugPrint('LocalAuthService.getSessionUser failed: $e');
      return null;
    }
  }

  Future<void> signOut() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(sessionKey);
      await prefs.remove(sessionUserKey);
    } catch (e) {
      debugPrint('LocalAuthService.signOut failed: $e');
    }
  }

  Future<AppUser> signInWithEmailPassword({required String email, required String password}) async {
    final prefs = await SharedPreferences.getInstance();
    final deviceId = await AppIdentity.getOrCreateDeviceId();

    final payload = <String, dynamic>{
      'e_mail': email.trim(),
      'password': password,
      if (deviceId.trim().isNotEmpty) 'device_id': deviceId.trim(),
      'app_version': AppIdentity.appVersion,
    };

    final uri = Uri.https('medisom.com.br', '/iot/app/login');
    http.Response resp;
    try {
      resp = await http
          .post(
            uri,
            headers: const {
              'content-type': 'application/json; charset=utf-8',
              'accept': 'application/json',
            },
            body: jsonEncode(payload),
            encoding: utf8,
          )
          .timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('LocalAuthService.signInWithEmailPassword network failed: $e');
      throw const AuthException('Falha de conexão com o servidor.');
    }

    final bodyText = _decodeResponseBody(resp);

    Map<String, dynamic>? decoded;
    try {
      decoded = _tryParseApiMap(bodyText);
    } catch (_) {
      decoded = null;
    }

    // Alguns endpoints podem encapsular a resposta em { payload: {...} }.
    final api = _unwrapApiPayload(decoded);

    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      final success = api?['success'] == true || api?['success']?.toString() == 'true';
      final code = (api?['code'] ?? '').toString();
      if (success && code == 'LOGIN_OK') {
        final userId = (api?['user_id'] ?? api?['userId'] ?? '').toString();
        final eMail = (api?['e_mail'] ?? api?['email'] ?? email).toString();
        final emailVerified = (api?['email_verified'] ?? api?['emailVerified'] ?? false) == true;

        final now = DateTime.now();
        final user = AppUser(
          id: userId.isNotEmpty ? userId : 'u_${now.millisecondsSinceEpoch}',
          email: eMail,
          displayName: eMail,
          emailVerified: emailVerified,
          companyIds: const [],
          createdAt: now,
          updatedAt: now,
        );

        await prefs.setString(sessionKey, user.id);
        await prefs.setString(sessionUserKey, jsonEncode(user.toJson()));
        return user;
      }
    }

    final apiMsg = (api?['message'] ?? api?['mensagem'])?.toString();
    if (apiMsg != null && apiMsg.trim().isNotEmpty) throw AuthException(apiMsg.trim());

    // Fallbacks by known codes.
    final code = (api?['code'] ?? '').toString();
    if (code == 'INVALID_CREDENTIALS') throw const AuthException('E-mail ou senha inválidos.');
    throw AuthException('Não foi possível entrar. (${resp.statusCode})');
  }

  Map<String, dynamic>? _unwrapApiPayload(Map<String, dynamic>? decoded) {
    if (decoded == null) return null;
    final payload = decoded['payload'];
    if (payload is Map) return payload.cast<String, dynamic>();
    final data = decoded['data'];
    if (data is Map) return data.cast<String, dynamic>();
    return decoded;
  }

  String _decodeResponseBody(http.Response resp) {
    try {
      return utf8.decode(resp.bodyBytes, allowMalformed: true);
    } catch (e) {
      debugPrint('LocalAuthService._decodeResponseBody failed: $e');
      return resp.body;
    }
  }

  Map<String, dynamic>? _tryParseApiMap(String body) {
    try {
      var sanitized = body.trim();
      if (sanitized.startsWith('\ufeff')) sanitized = sanitized.substring(1).trimLeft();
      if (!sanitized.startsWith('{') && !sanitized.startsWith('[')) {
        final objIdx = sanitized.indexOf('{');
        final arrIdx = sanitized.indexOf('[');
        final idx = (objIdx == -1)
            ? arrIdx
            : (arrIdx == -1)
                ? objIdx
                : (objIdx < arrIdx ? objIdx : arrIdx);
        if (idx > 0) sanitized = sanitized.substring(idx);
      }
      final decoded = jsonDecode(sanitized);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      // ignore
    }
    return null;
  }

  Future<AppUser> registerWithEmailPassword({required String email, required String password, required String displayName}) async {
    final prefs = await SharedPreferences.getInstance();
    final users = await _loadUsers(prefs);

    final exists = users.any((raw) {
      final record = (raw as Map).cast<String, dynamic>();
      final userJson = (record['user'] as Map).cast<String, dynamic>();
      final storedEmail = (userJson['email'] ?? '') as String;
      return storedEmail.toLowerCase() == email.toLowerCase();
    });
    if (exists) throw const AuthException('Este e-mail já está cadastrado.');

    final now = DateTime.now();
    final user = AppUser(
      id: 'u_${now.millisecondsSinceEpoch}',
      email: email,
      displayName: displayName,
      emailVerified: false,
      companyIds: const ['acme'],
      createdAt: now,
      updatedAt: now,
    );

    users.add({'user': user.toJson(), 'password': password});
    await prefs.setString(usersKey, jsonEncode(users));
    await prefs.setString(sessionKey, user.id);
    return user;
  }

  Future<AppUser> markEmailVerified({required String userId}) async {
    final prefs = await SharedPreferences.getInstance();
    final users = await _loadUsers(prefs);
    final updated = <Map<String, dynamic>>[];
    AppUser? result;

    for (final raw in users) {
      final record = (raw as Map).cast<String, dynamic>();
      final userJson = (record['user'] as Map).cast<String, dynamic>();
      if ((userJson['id'] ?? '') == userId) {
        final user = AppUser.fromJson(userJson).copyWith(emailVerified: true, updatedAt: DateTime.now());
        record['user'] = user.toJson();
        result = user;
      }
      updated.add(record);
    }
    if (result == null) throw const AuthException('Usuário não encontrado.');
    await prefs.setString(usersKey, jsonEncode(updated));
    return result;
  }

  /// Sends a password reset request.
  ///
  /// Returns the backend message (usually a generic message like
  /// "Se o e-mail existir, ...") when available.
  Future<String?> sendPasswordResetEmail({required String email}) async {
    final uri = Uri.https('medisom.com.br', '/iot/app/forgot-password');
    final payload = <String, dynamic>{'e_mail': email.trim()};

    http.Response resp;
    try {
      resp = await http
          .post(
            uri,
            headers: const {
              'content-type': 'application/json; charset=utf-8',
              'accept': 'application/json',
            },
            body: jsonEncode(payload),
            encoding: utf8,
          )
          .timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('LocalAuthService.sendPasswordResetEmail network failed: $e');
      throw const AuthException('Falha de conexão com o servidor.');
    }

    final bodyText = _decodeResponseBody(resp);
    final decoded = _tryParseApiMap(bodyText);
    final api = _unwrapApiPayload(decoded);

    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      final apiMsg = (api?['message'] ?? api?['mensagem'])?.toString();
      if (apiMsg != null && apiMsg.trim().isNotEmpty) return apiMsg.trim();
      return null;
    }

    final apiMsg = (api?['message'] ?? api?['mensagem'])?.toString();
    if (apiMsg != null && apiMsg.trim().isNotEmpty) throw AuthException(apiMsg.trim());
    throw AuthException('Não foi possível enviar as instruções. (${resp.statusCode})');
  }

  Future<void> resetPassword({required String email, required String resetToken, required String newPassword}) async {
    final uri = Uri.https('medisom.com.br', '/iot/app/reset-password');
    final payload = <String, dynamic>{
      'e_mail': email.trim(),
      'reset_token': resetToken.trim(),
      'new_password': newPassword,
    };

    http.Response resp;
    try {
      resp = await http
          .post(
            uri,
            headers: const {
              'content-type': 'application/json; charset=utf-8',
              'accept': 'application/json',
            },
            body: jsonEncode(payload),
            encoding: utf8,
          )
          .timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('LocalAuthService.resetPassword network failed: $e');
      throw const AuthException('Falha de conexão com o servidor.');
    }

    final bodyText = _decodeResponseBody(resp);
    final decoded = _tryParseApiMap(bodyText);
    final api = _unwrapApiPayload(decoded);

    if (resp.statusCode >= 200 && resp.statusCode < 300) return;

    final apiMsg = (api?['message'] ?? api?['mensagem'])?.toString();
    if (apiMsg != null && apiMsg.trim().isNotEmpty) throw AuthException(apiMsg.trim());
    throw AuthException('Não foi possível redefinir a senha. (${resp.statusCode})');
  }

  Future<List<dynamic>> _loadUsers(SharedPreferences prefs) async {
    try {
      final raw = prefs.getString(usersKey);
      if (raw == null || raw.isEmpty) return [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded;
    } catch (e) {
      debugPrint('LocalAuthService._loadUsers failed: $e');
      return [];
    }
  }
}

class AuthException implements Exception {
  const AuthException(this.message);
  final String message;
  @override
  String toString() => message;
}
