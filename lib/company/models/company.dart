class Company {
  const Company({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;

  Company copyWith({String? id, String? name, DateTime? createdAt, DateTime? updatedAt}) {
    return Company(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  static Company fromJson(Map<String, dynamic> json) {
    return Company(
      id: (json['id'] ?? '') as String,
      name: (json['name'] ?? '') as String,
      createdAt: DateTime.tryParse((json['createdAt'] ?? '') as String) ?? DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: DateTime.tryParse((json['updatedAt'] ?? '') as String) ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
