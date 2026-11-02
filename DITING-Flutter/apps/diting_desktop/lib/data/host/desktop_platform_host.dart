/// What the Flutter web build can ask of its host: the page origin and whether it can open a file
/// picker for the login background.
///
/// The web build is only served to a browser as the LAN web console; the native Windows window uses
/// the stub. Everything else here is a no-op off the web.
library;

export 'desktop_platform_host_stub.dart'
    if (dart.library.js_interop) 'desktop_platform_host_web.dart';

export 'desktop_image_size.dart';
