class Sensor {
  const Sensor({
    required this.sensorId,
    required this.clientId,
    required this.email,
    required this.portalUrl,
    this.local = '',
    this.enabled = false,
    this.lastUpdate,
    this.limit,
    this.weighting = '',
    this.percentAboveLimit,
    this.leq1Min,
    this.monitor = '',
    required this.createdAt,
    required this.updatedAt,
  });

  final String sensorId;
  final String clientId;
  final String email;
  final String portalUrl;
  final String local;
  final bool enabled;
  final DateTime? lastUpdate;
  final double? limit;
  final String weighting;
  final double? percentAboveLimit;
  final double? leq1Min;
  final String monitor;
  final DateTime createdAt;
  final DateTime updatedAt;

  Sensor copyWith({
    String? sensorId,
    String? clientId,
    String? email,
    String? portalUrl,
    String? local,
    bool? enabled,
    DateTime? lastUpdate,
    double? limit,
    String? weighting,
    double? percentAboveLimit,
    double? leq1Min,
    String? monitor,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Sensor(
      sensorId: sensorId ?? this.sensorId,
      clientId: clientId ?? this.clientId,
      email: email ?? this.email,
      portalUrl: portalUrl ?? this.portalUrl,
      local: local ?? this.local,
      enabled: enabled ?? this.enabled,
      lastUpdate: lastUpdate ?? this.lastUpdate,
      limit: limit ?? this.limit,
      weighting: weighting ?? this.weighting,
      percentAboveLimit: percentAboveLimit ?? this.percentAboveLimit,
      leq1Min: leq1Min ?? this.leq1Min,
      monitor: monitor ?? this.monitor,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'sensor_id': sensorId,
      'client_id': clientId,
      'e_mail': email,
      'url': portalUrl,
      'local': local,
      'enable': enabled,
      'ultimo_update': lastUpdate?.toUtc().toIso8601String(),
      'limite': limit,
      'ponderacao': weighting,
      'percentual': percentAboveLimit,
      'laeq': leq1Min,
      'monitor': monitor,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  static Sensor fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic v) {
      if (v is String && v.trim().isNotEmpty) {
        final parsed = DateTime.tryParse(v);
        if (parsed != null) return parsed;
      }
      return DateTime.now();
    }

    DateTime? parseNullableDate(dynamic v) {
      if (v is String && v.trim().isNotEmpty) {
        return DateTime.tryParse(v.trim());
      }
      return null;
    }

    bool parseBool(dynamic v) {
      if (v is bool) return v;
      final s = v?.toString().trim().toLowerCase();
      if (s == 'true' || s == '1' || s == 'on') return true;
      return false;
    }

    double? parseNullableDouble(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      final s = v.toString().trim();
      if (s.isEmpty) return null;
      return double.tryParse(s.replaceAll(',', '.'));
    }

    return Sensor(
      sensorId: (json['sensor_id'] ?? json['sensorId'] ?? '').toString(),
      clientId: (json['client_id'] ?? json['clientId'] ?? '').toString(),
      email: (json['e_mail'] ?? json['email'] ?? '').toString(),
      portalUrl: (json['url'] ?? json['portal_url'] ?? json['portalUrl'] ?? '').toString(),
      local: (json['local'] ?? '').toString(),
      enabled: parseBool(json['enable'] ?? json['enabled']),
      lastUpdate: parseNullableDate(json['ultimo_update'] ?? json['last_update'] ?? json['ultimoUpdate']),
      limit: parseNullableDouble(json['limite'] ?? json['limit']),
      weighting: (json['ponderacao'] ?? json['weighting'] ?? '').toString(),
      percentAboveLimit: parseNullableDouble(json['percentual'] ?? json['percent_above_limit'] ?? json['percentAboveLimit']),
      leq1Min: parseNullableDouble(json['laeq'] ?? json['leq_1min'] ?? json['leq1Min']),
      monitor: (json['monitor'] ?? '').toString(),
      createdAt: parseDate(json['created_at'] ?? json['createdAt']),
      updatedAt: parseDate(json['updated_at'] ?? json['updatedAt']),
    );
  }
}
