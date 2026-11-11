import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/ui/l10n.dart';
import 'package:material_ui/material_ui.dart';

/// The [UiLocalizations] the app runs with. `UiLocalizations.of` asserts the delegate is
/// registered, so every vendored widget in `lib/ui` depends on it. The strings come from the same
/// ARB resources as the pages (`lib/l10n/app_<locale>.arb`), so adding a language needs no change
/// here. The tests keep their own stub.
class AppUiLocalizations extends UiLocalizations {
  AppUiLocalizations(this.locale) : _l10n = lookupAppL10n(locale);

  final Locale locale;
  final AppL10n _l10n;

  static const delegate = _AppUiDelegate();

  @override
  String get back => _l10n.uiBack;
  @override
  String get cancel => _l10n.uiCancel;
  @override
  String get clearSearch => _l10n.uiClearSearch;
  @override
  String get close => _l10n.uiClose;
  @override
  String get hidePassword => _l10n.uiHidePassword;
  @override
  String get more => _l10n.uiMore;
  @override
  String get noSearchResults => _l10n.uiNoSearchResults;
  @override
  String get reset => _l10n.uiReset;
  @override
  String get search => _l10n.uiSearch;
  @override
  String get showLess => _l10n.uiShowLess;
  @override
  String get showMore => _l10n.uiShowMore;
  @override
  String get showPassword => _l10n.uiShowPassword;
  @override
  String get sort => _l10n.uiSort;
  @override
  String get submit => _l10n.uiSubmit;
}

class _AppUiDelegate extends LocalizationsDelegate<UiLocalizations> {
  const _AppUiDelegate();

  @override
  bool isSupported(Locale locale) => AppL10n.supportedLocales.any(
    (supported) => supported.languageCode == locale.languageCode,
  );

  @override
  Future<UiLocalizations> load(Locale locale) async =>
      AppUiLocalizations(locale);

  @override
  bool shouldReload(_AppUiDelegate old) => false;
}
