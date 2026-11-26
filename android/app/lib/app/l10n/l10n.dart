library;

import 'package:diting_android/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';

export 'package:diting_android/l10n/app_localizations.dart';

extension AppL10nContext on BuildContext {
  AppL10n get l10n => AppL10n.of(this);
}

AppL10n? _current;

AppL10n get currentL10n => _current ?? lookupAppL10n(const Locale('zh'));

void setCurrentL10n(AppL10n l10n) => _current = l10n;
