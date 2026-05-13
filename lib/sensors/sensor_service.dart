import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:medisom_console/sensors/models/sensor.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SensorException implements Exception {
  const SensorException(this.message);
  final String message;

  @override
  String toString() => message;
}

class AddSensorResult {
  const AddSensorResult({
    required this.sensorId,
    required this.userId,
    required this.clientId,
    required this.userLevel,
    required this.portalUrl,
    required this.enabled,
    required this.local,
    required this.lastUpdate,
    required this.limit,
    required this.weighting,
    required this.percentAboveLimit,
    required this.leq1Min,
    required this.monitor,
  });

  final String sensorId;
  final String userId;
  final String clientId;
  final int userLevel;
  final String portalUrl;
  final bool enabled;
  final String local;
  final DateTime? lastUpdate;
  final double? limit;
  final String weighting;
  final double? percentAboveLimit;
  final double? leq1Min;
  final String monitor;

  static AddSensorResult fromJson(Map<String, dynamic> json) {
    int parseInt(dynamic v) {
      if (v is int) return v;
      return int.tryParse(v?.toString() ?? '') ?? 0;
    }

    bool parseBool(dynamic v) {
      if (v is bool) return v;
      final s = v?.toString().trim().toLowerCase();
      if (s == 'true' || s == '1' || s == 'on') return true;
      return false;
    }

    DateTime? parseNullableDate(dynamic v) {
      if (v is String && v.trim().isNotEmpty) {
        return DateTime.tryParse(v.trim());
      }
      return null;
    }

    double? parseNullableDouble(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      final s = v.toString().trim();
      if (s.isEmpty) return null;
      return double.tryParse(s.replaceAll(',', '.'));
    }

    return AddSensorResult(
      sensorId: (json['sensor_id'] ?? json['sensorId'] ?? '').toString(),
      userId: (json['user_id'] ?? json['userId'] ?? '').toString(),
      clientId: (json['client_id'] ?? json['clientId'] ?? '').toString(),
      userLevel: parseInt(json['user_level'] ?? json['userLevel']),
      portalUrl: (json['url'] ?? json['portal_url'] ?? json['portalUrl'] ?? '').toString(),
      enabled: parseBool(json['enable'] ?? json['enabled']),
      local: (json['local'] ?? '').toString(),
      lastUpdate: parseNullableDate(json['ultimo_update'] ?? json['last_update'] ?? json['ultimoUpdate']),
      limit: parseNullableDouble(json['limite'] ?? json['limit']),
      weighting: (json['ponderacao'] ?? json['weighting'] ?? '').toString(),
      percentAboveLimit: parseNullableDouble(json['percentual'] ?? json['percent_above_limit'] ?? json['percentAboveLimit']),
      leq1Min: parseNullableDouble(json['laeq'] ?? json['leq_1min'] ?? json['leq1Min']),
      monitor: (json['monitor'] ?? '').toString(),
    );
  }
}

class SensorService {
  static const _legacySensorsKey = 'sensors.v1';
  static const _sensorsKeyPrefix = 'sensors.v2.';

  /// Notifier used by UI to refresh when the local sensors list changes.
  ///
  /// This is intentionally static so multiple instances of [SensorService]
  /// (created in different pages) can still broadcast changes.
  static final ValueNotifier<int> sensorsRevision = ValueNotifier<int>(0);

  static final Uri _importSensorsUri = Uri.https('medisom.com.br', '/iot/app/import');

  String _normalizeEmailKey(String email) {
    final e = email.trim().toLowerCase();
    // SharedPreferences keys are safe with most characters, but keep it conservative.
    return e.replaceAll(RegExp(r'[^a-z0-9@._-]'), '_');
  }

  String _keyForEmail(String email) => '$_sensorsKeyPrefix${_normalizeEmailKey(email)}';

  /// One-time migration from legacy key `sensors.v1` (single list for all users)
  /// into per-email keys `sensors.v2.<email>`.
  Future<void> _migrateLegacyIfNeeded(SharedPreferences prefs) async {
    try {
      if (!prefs.containsKey(_legacySensorsKey)) return;
      final raw = prefs.getString(_legacySensorsKey);
      if (raw == null || raw.trim().isEmpty) {
        await prefs.remove(_legacySensorsKey);
        return;
      }

      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        await prefs.remove(_legacySensorsKey);
        return;
      }

      final byEmail = <String, List<Sensor>>{};
      for (final item in decoded) {
        try {
          final map = (item is Map<String, dynamic>) ? item : (item is Map ? item.cast<String, dynamic>() : null);
          if (map == null) continue;
          final s = Sensor.fromJson(map);
          final email = s.email.trim().toLowerCase();
          if (email.isEmpty) continue;
          (byEmail[email] ??= <Sensor>[]).add(s);
        } catch (e) {
          debugPrint('SensorService._migrateLegacyIfNeeded item decode failed: $e');
        }
      }

      // Write per-email buckets. If a bucket already exists, merge (keeping existing).
      for (final entry in byEmail.entries) {
        final email = entry.key;
        final key = _keyForEmail(email);
        final existingRaw = prefs.getString(key);
        final merged = <Sensor>[];
        final seen = <String>{};

        void addAll(List<Sensor> items) {
          for (final s in items) {
            final id = s.sensorId.trim();
            if (id.isEmpty) continue;
            if (seen.add(id)) merged.add(s);
          }
        }

        if (existingRaw != null && existingRaw.trim().isNotEmpty) {
          try {
            final exDecoded = jsonDecode(existingRaw);
            if (exDecoded is List) {
              for (final exItem in exDecoded) {
                final exMap = (exItem is Map<String, dynamic>) ? exItem : (exItem is Map ? exItem.cast<String, dynamic>() : null);
                if (exMap == null) continue;
                final ex = Sensor.fromJson(exMap);
                addAll([ex]);
              }
            }
          } catch (e) {
            debugPrint('SensorService._migrateLegacyIfNeeded existing decode failed: $e');
          }
        }

        addAll(entry.value);
        await prefs.setString(key, jsonEncode(merged.map((s) => s.toJson()).toList()));
      }

      await prefs.remove(_legacySensorsKey);
    } catch (e) {
      debugPrint('SensorService._migrateLegacyIfNeeded failed: $e');
      // Don't block app usage if migration fails.
    }
  }

  Future<List<Sensor>> listSensors({required String email}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await _migrateLegacyIfNeeded(prefs);
      final key = _keyForEmail(email);
      final raw = prefs.getString(key);
      if (raw == null || raw.trim().isEmpty) return <Sensor>[];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <Sensor>[];

      final sensors = <Sensor>[];
      bool hasCorruption = false;
      for (final item in decoded) {
        try {
          final map = (item is Map<String, dynamic>) ? item : (item is Map ? item.cast<String, dynamic>() : null);
          if (map == null) {
            hasCorruption = true;
            continue;
          }
          final s = Sensor.fromJson(map);
          if (s.sensorId.trim().isEmpty || s.clientId.trim().isEmpty) {
            hasCorruption = true;
            continue;
          }
          sensors.add(s);
        } catch (e) {
          debugPrint('SensorService.listSensors item decode failed: $e');
          hasCorruption = true;
        }
      }

      // Always keep ordering consistent for UI.
      sensors.sort(_compareSensorsByClientName);

      if (hasCorruption) {
        await _saveSensors(prefs, key: key, sensors: sensors);
      }
      return sensors;
    } catch (e) {
      debugPrint('SensorService.listSensors failed: $e');
      return <Sensor>[];
    }
  }

  Future<void> upsertSensor({required String email, required Sensor sensor}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await _migrateLegacyIfNeeded(prefs);
      final key = _keyForEmail(email);
      final existing = await listSensors(email: email);
      final idx = existing.indexWhere((s) => s.sensorId == sensor.sensorId);
      if (idx >= 0) {
        existing[idx] = sensor;
      } else {
        existing.add(sensor);
      }
      await _saveSensors(prefs, key: key, sensors: existing);

      // Notify UI listeners that this email's list changed.
      sensorsRevision.value++;
    } catch (e) {
      debugPrint('SensorService.upsertSensor failed: $e');
      rethrow;
    }
  }

  Future<void> deleteSensor({required String email, required String sensorId}) async {
    try {
      final trimmed = sensorId.trim();
      if (trimmed.isEmpty) return;

      final prefs = await SharedPreferences.getInstance();
      await _migrateLegacyIfNeeded(prefs);
      final key = _keyForEmail(email);
      final existing = await listSensors(email: email);
      existing.removeWhere((s) => s.sensorId == trimmed);
      await _saveSensors(prefs, key: key, sensors: existing);

      sensorsRevision.value++;
    } catch (e) {
      debugPrint('SensorService.deleteSensor failed: $e');
      rethrow;
    }
  }

  Future<void> _saveSensors(SharedPreferences prefs, {required String key, required List<Sensor> sensors}) async {
    try {
      sensors.sort(_compareSensorsByClientName);
      final raw = jsonEncode(sensors.map((s) => s.toJson()).toList());
      await prefs.setString(key, raw);
    } catch (e) {
      debugPrint('SensorService._saveSensors failed: $e');
    }
  }

  int _compareSensorsByClientName(Sensor a, Sensor b) {
    // Primary: client name (clientId), fallback to sensorId.
    // NOTE: Dart does not provide locale-aware collation by default; this is a
    // simple case-insensitive sort which is usually good enough.
    String key(Sensor s) {
      final primary = s.clientId.trim();
      if (primary.isNotEmpty) return primary;
      return s.sensorId.trim();
    }

    final ka = key(a).toLowerCase();
    final kb = key(b).toLowerCase();
    final c = ka.compareTo(kb);
    if (c != 0) return c;
    // Deterministic tiebreaker.
    return a.sensorId.toLowerCase().compareTo(b.sensorId.toLowerCase());
  }

  /// Calls backend `/iot/app/import` and returns a list of sensor IDs for the given email.
  ///
  /// Expected response: a JSON array of strings, e.g. `["MEDISOM_5001", ...]`.
  ///
  /// Throws [SensorException] with a user-friendly message on errors.
  Future<List<String>> importSensorIdsForEmail({required String email}) async {
    final trimmedEmail = email.trim();
    if (trimmedEmail.isEmpty) throw const SensorException('E-mail inválido.');

    http.Response resp;
    try {
      resp = await http
          .post(
            _importSensorsUri,
            headers: const {
              'content-type': 'application/json; charset=utf-8',
              'accept': 'application/json',
            },
            body: jsonEncode(<String, dynamic>{'e_mail': trimmedEmail}),
            encoding: utf8,
          )
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('SensorService.importSensorIdsForEmail network failed: $e');
      throw const SensorException('Falha de conexão com o servidor.');
    }

    final bodyText = _decodeResponseBody(resp);
    if (resp.statusCode != 200) {
      // Try to parse any message from backend.
      final decoded = _tryParseApiMap(bodyText);
      final api = _unwrapApiPayload(decoded);
      final msg = (api?['message'] ?? api?['mensagem'] ?? decoded?['message'] ?? decoded?['mensagem'])?.toString();
      if (msg != null && msg.trim().isNotEmpty) throw SensorException(msg.trim());
      throw SensorException('Não foi possível importar sensores. (${resp.statusCode})');
    }

    try {
      dynamic decoded = jsonDecode(bodyText);
      // Some backends wrap the payload.
      if (decoded is Map) {
        final map = decoded.cast<String, dynamic>();
        final payload = map['payload'] ?? map['data'];
        if (payload != null) decoded = payload;
      }
      if (decoded is! List) throw const FormatException('Expected a list');

      final ids = <String>[];
      for (final item in decoded) {
        final id = item?.toString().trim() ?? '';
        if (id.isEmpty) continue;
        ids.add(id);
      }
      return ids;
    } catch (e) {
      debugPrint('SensorService.importSensorIdsForEmail decode failed: $e');
      throw const SensorException('Resposta inválida do servidor.');
    }
  }

  /// Calls backend `/iot/app/add-sensor`.
  ///
  /// Throws [SensorException] with a user-friendly message on any non-200 response.
  Future<AddSensorResult> addSensor({
    required String sensorId,
    required String userId,
    required String deviceId,
    required String email,
    required String appVersion,
    required bool insert,
  }) async {
    final uri = Uri.https('medisom.com.br', '/iot/app/add-sensor');
    final payload = <String, dynamic>{
      'sensor_id': sensorId.trim(),
      'user_id': userId.trim(),
      'device_id': deviceId.trim(),
      'e_mail': email.trim(),
      'app_version': appVersion,
      'insert': insert,
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
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('SensorService.addSensor network failed: $e');
      throw const SensorException('Falha de conexão com o servidor.');
    }

    final bodyText = _decodeResponseBody(resp);
    final decoded = _tryParseApiMap(bodyText);
    final api = _unwrapApiPayload(decoded);

    if (resp.statusCode == 200) {
      if (api == null) throw const SensorException('Resposta inválida do servidor.');
      return AddSensorResult.fromJson(api);
    }

    final msg = (api?['message'] ?? api?['mensagem'] ?? decoded?['message'] ?? decoded?['mensagem'])?.toString();
    if (msg != null && msg.trim().isNotEmpty) throw SensorException(msg.trim());
    throw SensorException('Não foi possível adicionar o sensor. (${resp.statusCode})');
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
      debugPrint('SensorService._decodeResponseBody failed: $e');
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
      if (decoded is Map) return decoded.cast<String, dynamic>();
    } catch (_) {
      // ignore
    }
    return null;
  }
}
