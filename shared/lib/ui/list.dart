// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:diting_shared/ui/support/input_limits.dart';
import 'package:diting_shared/ui/context.dart';
import 'package:diting_shared/ui/dialog.dart';
import 'package:diting_shared/ui/focus.dart';
import 'package:diting_shared/ui/icons/icons.dart';
import 'package:diting_shared/ui/inherited.dart';
import 'package:diting_shared/ui/input.dart';
import 'package:diting_shared/ui/item_position.dart';
import 'package:diting_shared/ui/measure.dart';
import 'package:diting_shared/ui/metrics.dart';
import 'package:diting_shared/ui/models.dart';
import 'package:diting_shared/ui/shape.dart';
import 'package:diting_shared/ui/typography.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import 'button.dart';
import 'card.dart';
import 'navigation_dock.dart';
import 'popup.dart';
import 'scaffold.dart';
import 'sheet.dart';
import 'sortable.dart';
import 'switch.dart';

part 'list_row_separator.dart';
part 'list_selected.dart';
part 'list_a.dart';
part 'list_b.dart';

sealed class _ListItemAction {
  const _ListItemAction();
}

final class _DefaultAction extends _ListItemAction {
  const _DefaultAction();
}

final class _ToggleAction extends _ListItemAction {
  final bool value;
  final ValueChanged<bool>? onChanged;

  const _ToggleAction({required this.value, this.onChanged});
}

final class _CheckboxAction extends _ListItemAction {
  final bool value;
  final ValueChanged<bool?>? onChanged;

  const _CheckboxAction({required this.value, this.onChanged});
}

final class _NextAction extends _ListItemAction {
  final Widget widget;

  const _NextAction({required this.widget});
}

final class _OptionsAction<T> extends _ListItemAction {
  final List<T> options;
  final T value;
  final String Function(T value) textBuilder;
  final ValueChanged<T> onChanged;

  const _OptionsAction({
    required this.options,
    required this.textBuilder,
    required this.value,
    required this.onChanged,
  });
}

final class _InputAction extends _ListItemAction {
  final String title;
  final String value;
  final String? suffixText;
  final ValueChanged<String?> onChanged;
  final FormFieldValidator<String>? validator;
  final int? maxLength;
  final TextInputType? keyboardType;
  final String? resetValue;

  const _InputAction({
    required this.title,
    required this.value,
    this.suffixText,
    required this.onChanged,
    this.resetValue,
    this.validator,
    this.maxLength,
    this.keyboardType,
  });
}
