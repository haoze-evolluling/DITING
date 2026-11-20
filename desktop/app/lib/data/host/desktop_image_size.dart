library;

const desktopBackgroundMinWidth = 320;
const desktopBackgroundMinHeight = 180;

const desktopBackgroundPayloadLimit = 1.5 * 1024 * 1024;

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
