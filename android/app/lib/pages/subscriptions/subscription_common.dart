library;

import 'package:diting_android/app/l10n/l10n.dart';
import 'package:diting_android/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

/// 订阅正文超过上限时向用户确认，调用方可能已经从页面离开。
Future<bool> confirmLargeSubscription(
  BuildContext? context,
  int byteLength,
) async {
  final ctx = context ?? rootNavigatorKey.currentState?.overlay?.context;
  if (ctx == null || !ctx.mounted) {
    return false;
  }
  final l10n = ctx.l10n;
  const megabyte = 1024 * 1024;
  final confirmed = await showFloatingDialog<bool>(
    context: ctx,
    child: CommonDialog(
      title: l10n.subsLargeConfirmTitle,
      actions: [
        TextButton(
          onPressed: () => popFloatingDialog(ctx, false),
          child: Text(l10n.commonCancel),
        ),
        TextButton(
          onPressed: () => popFloatingDialog(ctx, true),
          child: Text(l10n.subsLargeConfirmAction),
        ),
      ],
      child: Text(
        l10n.subsLargeConfirmMessage(
          (byteLength / megabyte).toStringAsFixed(1),
        ),
      ),
    ),
  );
  return confirmed ?? false;
}

Future<String?> askSubscriptionGroupName(
  BuildContext context, {
  required String title,
  String value = '',
}) {
  return showFloatingDialog<String>(
    context: context,
    child: InputDialog(
      title: title,
      value: value,
      validator: (value) => (value ?? '').trim().isEmpty
          ? context.l10n.subsGroupNameRequired
          : null,
    ),
  );
}

/// 本地订阅保存的是 content:// 地址，展示时取最后一段作为文件名。
String subscriptionFileNameOf(String uri) {
  final segment = Uri.tryParse(uri)?.pathSegments.lastOrNull ?? uri;
  return segment.isEmpty ? uri : segment;
}
