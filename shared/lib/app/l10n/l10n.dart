/// Single entry point for localized text: `import 'package:diting_shared/app/l10n/l10n.dart';`
/// then `context.l10n.someKey`.
///
/// The strings themselves live in `lib/l10n/app_<locale>.arb` and are compiled into
/// [AppL10n] by `flutter gen-l10n` (see `l10n.yaml`). Adding a language is only a new ARB
/// file plus one entry in [AppLanguageMode].
library;

import 'package:diting_shared/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';

export 'package:diting_shared/l10n/app_localizations.dart';

extension AppL10nContext on BuildContext {
  /// Shorthand for `AppL10n.of(context)`; the delegate is registered by the app root.
  AppL10n get l10n => AppL10n.of(this);
}

AppL10n? _current;

/// The resources of the locale the app is showing right now.
///
/// Widgets must use `context.l10n`: only that rebuilds on a language change. This accessor exists
/// for the layers that have no [BuildContext] — providers, models and services that format a
/// user-facing message (error text, notification body) once, when they run.
AppL10n get currentL10n => _current ?? lookupAppL10n(const Locale('zh'));

/// Called by the app root on every build, below `Localizations`.
void setCurrentL10n(AppL10n l10n) => _current = l10n;
