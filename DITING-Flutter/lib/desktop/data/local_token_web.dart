import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Reads the credential key used by the previous desktop frontend. Both UI
/// generations run on the same Wails origin, so existing installs stay valid.
String readLegacyIpcToken() {
  try {
    final storage = globalContext.getProperty<JSObject?>('localStorage'.toJS);
    if (storage == null) return '';
    final value = storage.callMethod<JSAny?>(
      'getItem'.toJS,
      'diting_ipc_token'.toJS,
    );
    if (value.isA<JSString>()) {
      return (value as JSString).toDart;
    }
    return '';
  } on Object {
    return '';
  }
}
