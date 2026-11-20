library;

bool _bool(Object? value) => value == true;

int _int(Object? value) => switch (value) {
  num() => value.toInt(),
  String() => int.tryParse(value) ?? 0,
  _ => 0,
};

Map<String, Object?> _map(Object? value) =>
    value is Map ? value.cast<String, Object?>() : const {};

class DesktopPortConflict {
  const DesktopPortConflict({
    required this.port,
    required this.protocol,
    required this.localAddress,
    required this.pid,
    required this.processName,
    required this.serviceName,
    required this.isICS,
    required this.isSelf,
    required this.diagnosis,
  });

  factory DesktopPortConflict.fromJson(Map<String, Object?> json) =>
      DesktopPortConflict(
        port: _int(json['port']),
        protocol: '${json['protocol'] ?? ''}',
        localAddress: '${json['localAddress'] ?? ''}',
        pid: _int(json['pid']),
        processName: '${json['processName'] ?? ''}',
        serviceName: '${json['serviceName'] ?? ''}',
        isICS: _bool(json['isICS']),
        isSelf: _bool(json['isSelf']),
        diagnosis: '${json['diagnosis'] ?? ''}',
      );

  final int port;
  final String protocol;
  final String localAddress;
  final int pid;
  final String processName;
  final String serviceName;

  final bool isICS;

  final bool isSelf;
  final String diagnosis;
}

class DesktopPortCheck {
  const DesktopPortCheck({
    required this.available,
    required this.conflicts,
    required this.hasICS,
    required this.canAutofix,
    required this.diagnostic,
  });

  factory DesktopPortCheck.fromJson(Map<String, Object?> json) =>
      DesktopPortCheck(
        available: _bool(json['available']),
        conflicts: switch (json['conflicts']) {
          List() => [
            for (final item in json['conflicts'] as List)
              if (item is Map) DesktopPortConflict.fromJson(_map(item)),
          ],
          _ => const [],
        },
        hasICS: _bool(json['hasICS']),
        canAutofix: _bool(json['canAutofix']),
        diagnostic: '${json['diagnostic'] ?? ''}',
      );

  static const empty = DesktopPortCheck(
    available: false,
    conflicts: [],
    hasICS: false,
    canAutofix: false,
    diagnostic: '',
  );

  final bool available;
  final List<DesktopPortConflict> conflicts;

  final bool hasICS;
  final bool canAutofix;

  final String diagnostic;

  bool get canRepair => !available && (canAutofix || hasICS);
}

class DesktopEmergencyRestore {
  const DesktopEmergencyRestore({required this.healed, required this.message});

  factory DesktopEmergencyRestore.fromJson(Map<String, Object?> json) =>
      DesktopEmergencyRestore(
        healed: json['healed'] == true,
        message: '${json['message'] ?? ''}',
      );

  final bool healed;
  final String message;
}
