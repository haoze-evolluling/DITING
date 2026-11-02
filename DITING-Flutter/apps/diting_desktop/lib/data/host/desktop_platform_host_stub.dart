/// Off-web host: there are no Wails bindings, no page origin and no file picker.
///
/// Tests and the (non-existent) IO build use this, so the desktop window keeps taking the
/// `127.0.0.1` IPC path and the login gate stays out of the way.
library;

/// Whether the page was served by the Wails window rather than a browser.
bool get desktopHasWailsBindings => false;

/// The origin the page was loaded from; null when there is no page.
Uri? get desktopPageOrigin => null;

/// Picks one image and returns it as a `data:image/...;base64,` URL; null when nothing was picked.
Future<String?> pickDesktopImageDataUrl() async => null;

/// Shrinks a picked image before it is sent; off the web there is nothing to shrink it with, so the
/// payload is passed through unchanged (the service still validates and caps it).
Future<String?> compressDesktopImageDataUrl(String dataUrl) async => dataUrl;
