class ConflictFieldSnapshot {
  const ConflictFieldSnapshot({
    required this.field,
    this.base,
    this.local,
    this.server,
  });

  final String field;
  final Object? base;
  final Object? local;
  final Object? server;

  Map<String, Object?> toJson() => {
        'field': field,
        'base': base,
        'local': local,
        'server': server,
      };
}

class ConflictSnapshot {
  const ConflictSnapshot({
    required this.conflictId,
    required this.objectType,
    required this.serverId,
    required this.baseVersion,
    required this.localVersion,
    required this.serverVersion,
    required this.fields,
  });

  final String conflictId;
  final String objectType;
  final String serverId;
  final int? baseVersion;
  final int localVersion;
  final int serverVersion;
  final List<ConflictFieldSnapshot> fields;

  Map<String, Object?> toJson() => {
        'conflictId': conflictId,
        'objectType': objectType,
        'serverId': serverId,
        'baseVersion': baseVersion,
        'localVersion': localVersion,
        'serverVersion': serverVersion,
        'fields': fields.map((field) => field.toJson()).toList(),
      };
}
