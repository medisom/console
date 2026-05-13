import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppIdentity {
  static const appVersion = '1.0.0';

  static Future<String> getOrCreateDeviceId() async {
    const key = 'device_id';
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getString(key);
      if (existing != null && existing.trim().isNotEmpty) return existing;

      final random = Random.secure();
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
      return _uuidV4();
    }
  }

  static String _uuidV4() {
    final r = Random.secure();
    int nextInt(int bits) => r.nextInt(1 << bits);

    final timeLow = nextInt(32);
    final timeMid = nextInt(16);
    final timeHiAndVersion = (nextInt(12) | (4 << 12));
    final clkSeqHiRes = (nextInt(6) | 0x80);
    final clkSeqLow = nextInt(8);
    final node = List<int>.generate(6, (_) => nextInt(8));

    String hex(int value, int width) => value.toRadixString(16).padLeft(width, '0');
    final nodeHex = node.map((b) => hex(b, 2)).join();
    return '${hex(timeLow, 8)}-${hex(timeMid, 4)}-${hex(timeHiAndVersion, 4)}-${hex(clkSeqHiRes, 2)}${hex(clkSeqLow, 2)}-$nodeHex';
  }
}
