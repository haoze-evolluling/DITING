/// The 53-port diagnosis: `/api/v1/portcheck` and its autofix.
///
/// The old desktop console's `DiagnosticsPanel.vue` port section is the blueprint. Every field is
/// the platform probe's own wording: the page neither guesses which process holds the port nor
/// decides that a conflict is harmless.
library;

bool _bool(Object? value) => value == true;

int _int(Object? value) => switch (value) {
  num() => value.toInt(),
  String() => int.tryParse(value) ?? 0,
  _ => 0,
};

Map<String, Object?> _map(Object? value) =>
    value is Map ? value.cast<String, Object?>() : const {};

/// One process listening on the DNS port.
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

  /// The Windows ICS / Linux resolved stub, the two the service knows how to stop.
  final bool isICS;

  /// Whether the listener is the DITING service itself.
  final bool isSelf;
  final String diagnosis;
}

/// `GET /api/v1/portcheck`.
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

  /// A system-level listener that the autofix can stop.
  final bool hasICS;
  final bool canAutofix;

  /// The probe's combined report and advice; shown verbatim.
  final String diagnostic;

  bool get canRepair => !available && (canAutofix || hasICS);
}
