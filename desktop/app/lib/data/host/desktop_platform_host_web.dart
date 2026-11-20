library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'desktop_image_size.dart';

Uri? get desktopPageOrigin => Uri.base;

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
  input.setProperty(
    'oncancel'.toJS,
    ((JSAny? _) {
      finish(null);
    }).toJS,
  );
  input.callMethod<JSAny?>('click'.toJS);
  return completer.future;
}

Future<String?> compressDesktopImageDataUrl(String dataUrl) {
  if (dataUrl.startsWith('data:image/svg')) {
    return Future.value(dataUrl);
  }
  final completer = Completer<String?>();
  final document = globalContext.getProperty<JSObject>('document'.toJS);
  final image = globalContext
      .getProperty<JSFunction>('Image'.toJS)
      .callAsConstructor<JSObject>();

  void fallback() {
    if (!completer.isCompleted) completer.complete(dataUrl);
  }

  image.setProperty(
    'onload'.toJS,
    ((JSAny? _) {
      try {
        final width =
            image.getProperty<JSNumber?>('naturalWidth'.toJS)?.toDartInt ?? 0;
        final height =
            image.getProperty<JSNumber?>('naturalHeight'.toJS)?.toDartInt ?? 0;
        final first = desktopBackgroundSize(width, height);
        if (first.width <= 0 || first.height <= 0) {
          fallback();
          return;
        }
        final canvas = document.callMethod<JSObject>(
          'createElement'.toJS,
          'canvas'.toJS,
        );
        canvas.setProperty('width'.toJS, first.width.toJS);
        canvas.setProperty('height'.toJS, first.height.toJS);
        final context = canvas.callMethod<JSObject?>(
          'getContext'.toJS,
          '2d'.toJS,
        );
        if (context == null) {
          fallback();
          return;
        }
        context.callMethodVarArgs<JSAny?>('drawImage'.toJS, [
          image,
          0.toJS,
          0.toJS,
          first.width.toJS,
          first.height.toJS,
        ]);
        var encoded = _encode(canvas, 0.82);
        if (encoded.length > desktopBackgroundPayloadLimit) {
          final second = desktopBackgroundShrinkSize(first.width, first.height);
          final shrunk = document.callMethod<JSObject>(
            'createElement'.toJS,
            'canvas'.toJS,
          );
          shrunk.setProperty('width'.toJS, second.width.toJS);
          shrunk.setProperty('height'.toJS, second.height.toJS);
          final shrunkContext = shrunk.callMethod<JSObject?>(
            'getContext'.toJS,
            '2d'.toJS,
          );
          if (shrunkContext != null) {
            shrunkContext.callMethodVarArgs<JSAny?>('drawImage'.toJS, [
              canvas,
              0.toJS,
              0.toJS,
              second.width.toJS,
              second.height.toJS,
            ]);
            encoded = _encode(shrunk, 0.72);
          }
        }
        if (!completer.isCompleted) completer.complete(encoded);
      } catch (_) {
        fallback();
      }
    }).toJS,
  );
  image.setProperty(
    'onerror'.toJS,
    ((JSAny? _) {
      fallback();
    }).toJS,
  );
  image.setProperty('src'.toJS, dataUrl.toJS);
  return completer.future;
}

String _encode(JSObject canvas, double quality) {
  for (final type in const ['image/webp', 'image/jpeg']) {
    final encoded = canvas
        .callMethod<JSString>(
          'toDataURL'.toJS,
          type.toJS,
          quality.toJS,
        )
        .toDart;
    if (encoded.startsWith('data:$type')) return encoded;
  }
  return canvas.callMethod<JSString>('toDataURL'.toJS).toDart;
}
