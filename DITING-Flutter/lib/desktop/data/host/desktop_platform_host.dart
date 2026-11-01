/// What the Flutter web build can ask of its host: whether it is running inside the Wails window, and
/// whether it can open a file picker for the login background.
///
/// The same bundle is served by the Wails window and by the browser (the LAN web console), so the
/// host has to be told apart at runtime. Wails injects its bindings as `window.go`; the old console
/// used exactly that check (`utils/env.ts`). Everything else here is a no-op off the web.
library;

export 'desktop_platform_host_stub.dart'
    if (dart.library.js_interop) 'desktop_platform_host_web.dart';

export 'desktop_image_size.dart';
