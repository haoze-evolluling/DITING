/// [totalPss] is whole-process PSS while [javaHeap] and [nativeHeap] are heap allocation only, so
/// they never sum to PSS; do not derive them from `summary.java-heap` / `summary.native-heap`
/// (always 0 on Android 14).
library;

class ProcessMemory {
  const ProcessMemory({
    this.totalPss = 0,
    this.javaHeap = 0,
    this.nativeHeap = 0,
    this.systemTotal = 0,
    this.systemAvail = 0,
    this.available = false,
  });

  final int totalPss;

  final int javaHeap;

  final int nativeHeap;

  final int systemTotal;

  final int systemAvail;

  final bool available;

  double get systemShare => available && systemTotal > 0
      ? (totalPss / systemTotal).clamp(0.0, 1.0)
      : 0;

  /// The native side sends KB integers; convert to bytes here.
  static ProcessMemory fromMap(Object? raw) {
    if (raw is! Map) return const ProcessMemory();
    int kb(String key) => ((raw[key] as num?)?.toInt() ?? 0) * 1024;
    return ProcessMemory(
      totalPss: kb('totalPss'),
      javaHeap: kb('javaHeap'),
      nativeHeap: kb('nativeHeap'),
      systemTotal: kb('systemTotal'),
      systemAvail: kb('systemAvail'),
      available: raw['available'] == true,
    );
  }

  /// Value equality so the 2 s poller can skip a tick that would repaint the same numbers.
  @override
  bool operator ==(Object other) =>
      other is ProcessMemory &&
      other.totalPss == totalPss &&
      other.javaHeap == javaHeap &&
      other.nativeHeap == nativeHeap &&
      other.systemTotal == systemTotal &&
      other.systemAvail == systemAvail &&
      other.available == available;

  @override
  int get hashCode => Object.hash(
    totalPss,
    javaHeap,
    nativeHeap,
    systemTotal,
    systemAvail,
    available,
  );
}
