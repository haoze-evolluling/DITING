import 'package:diting_shared/ui/l10n.dart';
import 'package:material_ui/material_ui.dart';

/// Minimal [UiLocalizations] for tests and the demo app; `lib/ui` asserts it is present
class StubUiLocalizations extends UiLocalizations {
  StubUiLocalizations();

  static const delegate = _StubDelegate();

  @override
  String get back => '返回';
  @override
  String get cancel => '取消';
  @override
  String get clearSearch => '清除搜索';
  @override
  String get close => '关闭';
  @override
  String get hidePassword => '隐藏密码';
  @override
  String get more => '更多';
  @override
  String get noSearchResults => '无搜索结果';
  @override
  String get reset => '重置';
  @override
  String get search => '搜索';
  @override
  String get showLess => '收起';
  @override
  String get showMore => '展开';
  @override
  String get showPassword => '显示密码';
  @override
  String get sort => '排序';
  @override
  String get submit => '提交';
}

class _StubDelegate extends LocalizationsDelegate<UiLocalizations> {
  const _StubDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<UiLocalizations> load(Locale locale) async => StubUiLocalizations();

  @override
  bool shouldReload(_StubDelegate old) => false;
}
