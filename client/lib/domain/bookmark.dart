class Bookmark {
  final String id;
  final String url;
  final String? title;
  final List<String> tags;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Bookmark({
    required this.id,
    required this.url,
    this.title,
    this.tags = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  Bookmark copyWith({
    String? id,
    String? url,
    String? title,
    List<String>? tags,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Bookmark(
    id: id ?? this.id,
    url: url ?? this.url,
    title: title ?? this.title,
    tags: tags ?? this.tags,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  /// Deserialize from the API JSON (ISO-8601 dates, comma-separated tags).
  factory Bookmark.fromJson(Map<String, dynamic> json) {
    final tagsRaw = json['tags'];
    List<String> tags;
    if (tagsRaw is String && tagsRaw.isNotEmpty) {
      // Comma-separated from the API
      tags = tagsRaw.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
    } else if (tagsRaw is List) {
      tags = List<String>.from(tagsRaw);
    } else {
      tags = [];
    }

    return Bookmark(
      id: json['id'] as String,
      url: json['url'] as String,
      title: json['title'] as String?,
      tags: tags,
      createdAt: _parseDateTime(json['created_at']),
      updatedAt: _parseDateTime(json['updated_at'] ?? json['created_at']),
    );
  }

  /// Serialize for local SQLite storage.
  Map<String, dynamic> toRow() => {
    'id': id,
    'url': url,
    'title': title,
    'tags': tags.join(','),
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  /// Deserialize from local SQLite row.
  factory Bookmark.fromRow(Map<String, dynamic> row) {
    final tagsRaw = row['tags'];
    List<String> tags;
    if (tagsRaw is String && tagsRaw.isNotEmpty) {
      tags = tagsRaw.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
    } else {
      tags = [];
    }

    return Bookmark(
      id: row['id'] as String,
      url: row['url'] as String,
      title: row['title'] as String?,
      tags: tags,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }

  static DateTime _parseDateTime(dynamic v) {
    if (v is String) return DateTime.parse(v);
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v * 1000);
    return DateTime.now();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Bookmark && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Bookmark(id: $id, url: $url, title: $title)';
}
