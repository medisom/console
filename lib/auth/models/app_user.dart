class AppUser {
  const AppUser({
    required this.id,
    required this.email,
    required this.displayName,
    required this.emailVerified,
    required this.companyIds,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String email;
  final String displayName;
  final bool emailVerified;
  final List<String> companyIds;
  final DateTime createdAt;
  final DateTime updatedAt;

  AppUser copyWith({
    String? id,
    String? email,
    String? displayName,
    bool? emailVerified,
    List<String>? companyIds,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AppUser(
      id: id ?? this.id,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      emailVerified: emailVerified ?? this.emailVerified,
      companyIds: companyIds ?? this.companyIds,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'displayName': displayName,
      'emailVerified': emailVerified,
      'companyIds': companyIds,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  static AppUser fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: (json['id'] ?? '') as String,
      email: (json['email'] ?? '') as String,
      displayName: (json['displayName'] ?? '') as String,
      emailVerified: (json['emailVerified'] ?? false) as bool,
      companyIds: ((json['companyIds'] as List?) ?? const []).cast<String>(),
      createdAt: DateTime.tryParse((json['createdAt'] ?? '') as String) ?? DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: DateTime.tryParse((json['updatedAt'] ?? '') as String) ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
