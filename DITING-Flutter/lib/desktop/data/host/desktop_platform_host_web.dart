/// Web host: Wails detection plus the browser file picker used by the login background dialog.
///
/// Wails injects its bindings as `window.go` (the desktop window binds `main.App`), so its presence is
/// what tells the desktop window apart from a browser that loaded the same bundle from the LAN web
/// console. The picker is plain DOM: a hidden `<input type="file">` whose `FileReader` result becomes
/// the `data:image/...;base64,` URL the service accepts.
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Whether the page was served by the Wails window rather than a browser.
bool get desktopHasWailsBindings => globalContext.has('go');

/// The origin the page was loaded from, which is also the API base for the web console.
Uri? get desktopPageOrigin => Uri.base;

/// Picks one image and returns it as a `data:image/...;base64,` URL; null when nothing was picked.
///
/// No client-side resizing: the service caps the payload at 10MB and validates the file header, so
/// the raw file is what gets sent (the old console shrank it with a canvas first).
Future<String?> pickDesktopImageDataUrl() {
  final completer = Completer<String?>();
  final document = globalContext.getProperty<JSObject>('document'.toJS);
  final body = document.getProperty<JSObject?>('body'.toJS);
  final input = document.callMethod<JSObject>(
    'createElement'.toJS,
    'input'.toJS,
  );
  input.setProperty('type'.toJS, 'file'.toJS);
  input.setProperty('accept'.toJS, 'image/*'.toJS);
  input.setProperty('style'.toJS, 'display:none'.toJS);
  body?.callMethod<JSAny?>('appendChild'.toJS, input);

  void cleanup() {
    body?.callMethod<JSAny?>('removeChild'.toJS, input);
  }

  void finish(String? value) {
    cleanup();
    if (!completer.isCompleted) completer.complete(value);
  }

  input.setProperty(
    'onchange'.toJS,
    ((JSAny? _) {
      final files = input.getProperty<JSObject?>('files'.toJS);
      final file = files?.getProperty<JSObject?>('0'.toJS);
      if (file == null) {
        finish(null);
        return;
      }
      final reader = globalContext
          .getProperty<JSFunction>('FileReader'.toJS)
          .callAsConstructor<JSObject>();
      reader.setProperty(
        'onload'.toJS,
        ((JSAny? _) {
          finish(reader.getProperty<JSString?>('result'.toJS)?.toDart);
        }).toJS,
      );
      reader.setProperty(
        'onerror'.toJS,
        ((JSAny? _) {
          finish(null);
        }).toJS,
      );
      reader.callMethod<JSAny?>('readAsDataURL'.toJS, file);
    }).toJS,
  );
  // A cancelled picker never fires `change`; without this the dialog would wait forever.
  input.setProperty(
    'oncancel'.toJS,
    ((JSAny? _) {
      finish(null);
    }).toJS,
  );
  input.callMethod<JSAny?>('click'.toJS);
  return completer.future;
}
