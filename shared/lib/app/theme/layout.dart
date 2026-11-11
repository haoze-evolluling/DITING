// Mirror of upstream `lib/common/layout.dart` and `constant.dart`. `maxMobileWidth` drives
// `ViewScope.isMobile`, so a mismatch lays the same page out differently on desktop and web.

/// Widths up to this value use the mobile layout.
const maxMobileWidth = 600.0;

/// Widths up to this value are laptop; above it is desktop. Unused on Android, kept to match
/// upstream.
const maxLaptopWidth = 840.0;

/// Upper bound for the `MediaQuery.textScaler` linear factor.
const maxTextScale = 1.4;

/// Lower bound for the text scale factor.
const minTextScale = 0.8;

/// Most items the floating dock holds; beyond this it falls back to `NavigationBar`. Matches
/// upstream `BottomBarDestination.MAX = 4`.
const maxDockDestinations = 4;

/// The [maxMobileWidth] test, shared by the host and the tests.
bool isMobileWidth(double width) => width <= maxMobileWidth;

/// Clamps any text scale into [minTextScale]..[maxTextScale].
double clampTextScale(double scale) => scale.clamp(minTextScale, maxTextScale);
