import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppIdentity {
  static const appVersion = '1.0.0';

  static Random _random() {
    // Random.secure() is not supported on some platforms (notably Web), and can
    // throw at runtime. We gracefully fall back to Random() in that case.
    try {
      if (kIsWeb) return Random();
      return Random.secure();
    } catch (e) {
      debugPrint('AppIdentity: Random.secure unavailable, falling back to Random(): $e');
      return Random();
    }
  }

  static Future<String> getOrCreateDeviceId() async {
    const key = 'device_id';
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getString(key);
      if (existing != null && existing.trim().isNotEmpty) return existing;

      final random = _random();
      final bytes = List<int>.generate(16, (_) => random.nextInt(256));
      final id = base64Url.encode(bytes).replaceAll('=', '');
      await prefs.setString(key, id);
      return id;
    } catch (e) {
      debugPrint('AppIdentity.getOrCreateDeviceId failed: $e');
      return '';
    }
  }

  static Future<String> getOrCreateUserId() async {
    const key = 'user_id';
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getString(key);
      if (existing != null && existing.trim().isNotEmpty) return existing;

      final id = _uuidV4();
      await prefs.setString(key, id);
      return id;
    } catch (e) {
      debugPrint('AppIdentity.getOrCreateUserId failed: $e');
      // fallback (ephemeral)
      try {
        return _uuidV4();
      } catch (e2) {
        debugPrint('AppIdentity.getOrCreateUserId fallback _uuidV4 failed: $e2');
        // Last resort: timestamp-based id (not a UUID, but stable enough to keep the flow running)
        final r = Random();
        // IMPORTANT (Web/dart2js): `1 << 32` becomes 0 because JS bitwise ops are 32-bit.
        // Use 2x 31-bit chunks instead.
        final a = r.nextInt(1 << 31);
        final b = r.nextInt(1 << 31);
        return 'web-${DateTime.now().millisecondsSinceEpoch}-$a$b';
      }
    }
  }

  static String _uuidV4() {
    // IMPORTANT (Web/dart2js): avoid `1 << 32`/bit-shifts beyond 31 bits, because
    // JS bitwise ops are 32-bit and shifts of 32 can yield 0.
    // We generate 16 random bytes and then set UUID v4 bits.
    final r = _random();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));

    // Version 4
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    // Variant RFC 4122
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    String b(int v) => v.toRadixString(16).padLeft(2, '0');
    final parts = <String>[
      bytes.sublist(0, 4).map(b).join(),
      bytes.sublist(4, 6).map(b).join(),
      bytes.sublist(6, 8).map(b).join(),
      bytes.sublist(8, 10).map(b).join(),
      bytes.sublist(10, 16).map(b).join(),
    ];
    return parts.join('-');
  }
}
