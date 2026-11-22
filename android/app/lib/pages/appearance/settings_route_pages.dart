import 'package:diting_android/data/vpn/cidr_text.dart';
import 'package:diting_android/pages/config/config_common.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/state/settings_providers.dart';
import 'package:diting_shared/ui/support/input_limits.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

enum RouteListKind { include, exclude }

class SettingsRouteListPage extends ConsumerWidget {
  const SettingsRouteListPage({super.key, required this.kind});

  final RouteListKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(foregroundBackgroundProvider);
    final notifier = ref.read(foregroundBackgroundProvider.notifier);
    final routes = kind == RouteListKind.include
        ? state.routeAddress
        : state.routeExcludeAddress;
    final l10n = context.l10n;
    final title = kind == RouteListKind.include
        ? l10n.routeIncludeTitle
        : l10n.routeExcludeTitle;
    final subtitle = kind == RouteListKind.include
        ? l10n.routeIncludeSubtitle
        : l10n.routeExcludeSubtitle;

    Future<void> add() async {
      final value = await showFloatingDialog<String>(
        context: context,
        child: _CidrDialog(existing: routes.toSet()),
      );
      if (value == null || !context.mounted) return;
      final next = [...routes, value];
      if (kind == RouteListKind.include) {
        notifier.setRouteAddress(next);
      } else {
        notifier.setRouteExclude(next);
      }
    }

    Future<void> remove(String route) async {
      final confirmed = await confirmConfigAction(
        context,
        title: l10n.commonDelete,
        message: route,
      );
      if (!confirmed) return;
      final next = routes.where((item) => item != route);
      if (kind == RouteListKind.include) {
        notifier.setRouteAddress(next);
      } else {
        notifier.setRouteExclude(next);
      }
    }

    return CommonScaffold(
      title: title,
      iconActions: [
        IconButtonData(
          glyph: TablerIcons.plus,
          tooltip: l10n.routeCidrAddTitle,
          onPressed: add,
        ),
      ],
      body: PageBody(
        children: [
          generateSection(
            title: title,
            items: [
              if (routes.isEmpty)
                ListItem(
                  leading: const Icon(TablerIcons.link),
                  title: Text(l10n.routeCidrEmpty),
                  subtitle: Text(l10n.routeCidrEmptySubtitle),
                  onTap: add,
                )
              else
                for (final route in routes)
                  ListItem(
                    leading: const Icon(TablerIcons.link),
                    title: Text(route),
                    trailing: ConfigRemoveButton(
                      tooltip: l10n.commonDelete,
                      onPressed: () => remove(route),
                    ),
                  ),
            ],
            footer: '$subtitle\n${l10n.routeCidrFooter}',
          ),
        ],
      ),
    );
  }
}

class _CidrDialog extends StatefulWidget {
  const _CidrDialog({required this.existing});

  final Set<String> existing;

  @override
  State<_CidrDialog> createState() => _CidrDialogState();
}

class _CidrDialogState extends State<_CidrDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (!isCidrText(value)) {
      setState(() => _error = context.l10n.routeCidrInvalid);
      return;
    }
    if (widget.existing.contains(value)) {
      setState(() => _error = context.l10n.routeCidrDuplicate);
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final errorStyle = AppTextRole.supportingText
        .of(context)
        .copyWith(color: context.colorScheme.error);
    return CommonDialog(
      title: context.l10n.routeCidrAddTitle,
      hasFields: true,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.configCancel),
        ),
        TextButton(onPressed: _submit, child: Text(context.l10n.commonSave)),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            autocorrect: false,
            inputFormatters: TextInputLimits.limit(TextInputLimits.cidr),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: context.l10n.routeCidrLabel,
              hintText: context.l10n.routeCidrHint,
            ),
          ),
          if (_error case final error?) Text(error, style: errorStyle),
        ],
      ),
    );
  }
}
