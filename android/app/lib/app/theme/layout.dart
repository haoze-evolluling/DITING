const maxMobileWidth = 600.0;


const maxTextScale = 1.4;

const minTextScale = 0.8;

const maxDockDestinations = 4;

bool isMobileWidth(double width) => width <= maxMobileWidth;

double clampTextScale(double scale) => scale.clamp(minTextScale, maxTextScale);
