/// Number text for the log branch. Figures only; every word comes from the ARB.
library;

/// `14:03:41` for a row's timestamp. The service stores epoch millis; the log reads in the host's
/// own time zone, because that is when the user saw the query happen.
String desktopClock(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
}
