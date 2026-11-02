/// The size maths behind the login background's client-side shrink.
///
/// The old console picked these numbers in `utils/imageCompressor.ts` (canvas, 1920×1080 at quality
/// 0.82, then a second pass at ≤1280×720 / 0.72 when the payload is still larger than 1.5MB). Keeping
/// the arithmetic here rather than inside the JS interop makes it testable off the web.
library;

/// Minimum width the second pass is allowed to fall back to.
const desktopBackgroundMinWidth = 320;
const desktopBackgroundMinHeight = 180;

/// Payload length above which the console re-encoded at a smaller size (base64 characters).
const desktopBackgroundPayloadLimit = 1.5 * 1024 * 1024;

/// Proportional fit inside [maxWidth]×[maxHeight]; never upscales.
({int width, int height}) desktopBackgroundSize(
  int width,
  int height, {
  int maxWidth = 1920,
  int maxHeight = 1080,
}) {
  if (width <= 0 || height <= 0) return (width: 0, height: 0);
  if (width <= maxWidth && height <= maxHeight) {
    return (width: width, height: height);
  }
  final ratio = (maxWidth / width) < (maxHeight / height)
      ? maxWidth / width
      : maxHeight / height;
  return (
    width: (width * ratio).round(),
    height: (height * ratio).round(),
  );
}

/// The second pass: at most 0.75 of the first result and never below the minimum, so a picture that
/// is still too big shrinks enough to matter instead of by a few percent.
({int width, int height}) desktopBackgroundShrinkSize(int width, int height) {
  final ratio = [
    1280 / width,
    720 / height,
    0.75,
  ].reduce((a, b) => a < b ? a : b);
  final scaledWidth = (width * ratio).round();
  final scaledHeight = (height * ratio).round();
  return (
    width: scaledWidth < desktopBackgroundMinWidth
        ? desktopBackgroundMinWidth
        : scaledWidth,
    height: scaledHeight < desktopBackgroundMinHeight
        ? desktopBackgroundMinHeight
        : scaledHeight,
  );
}
