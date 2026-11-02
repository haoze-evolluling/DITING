/// Add one subscription list. The console's `RuleListsPanel.vue` add modal is the blueprint: a name
/// (optional, the page names it by position) and a URL or local file path (required).
///
/// The dialog only builds the draft; the page sends it and re-reads the rows the service answers
/// with, because adding starts a download the page cannot predict.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

/// The draft the page submits; [name] may be empty.
typedef FilterListDraft = ({String name, String url});

Future<FilterListDraft?> showAddFilterListDialog(BuildContext context) =>
    showFloatingDialog<FilterListDraft>(
      context: context,
      child: const _AddFilterListDialog(),
    );

class _AddFilterListDialog extends StatefulWidget {
  const _AddFilterListDialog();

  @override
  State<_AddFilterListDialog> createState() => _AddFilterListDialogState();
}

class _AddFilterListDialogState extends State<_AddFilterListDialog> {
  final _name = TextEditingController();
  final _url = TextEditingController();
  bool _invalid = false;

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  void _submit() {
    final url = _url.text.trim();
    if (url.isEmpty) {
      setState(() => _invalid = true);
      return;
    }
    popFloatingDialog<FilterListDraft>(
      context,
      (name: _name.text.trim(), url: url),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colorScheme = context.colorScheme;
    return CommonDialog(
      title: l10n.desktopFilterListAddTitle,
      hasFields: true,
      width: 520,
      actions: [
        TextButton(
          onPressed: () => popFloatingDialog(context),
          child: Text(l10n.commonCancel),
        ),
        TextButton(
          onPressed: _submit,
          child: Text(l10n.desktopFilterListAddConfirm),
        ),
      ],
      child: SizedBox(
        width: 460,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            Text(
              l10n.desktopFilterListAddBody,
              style: DashboardText.label(context),
            ),
            TextFormField(
              controller: _name,
              decoration: InputDecoration(
                labelText: l10n.desktopFilterListNameLabel,
                hintText: l10n.desktopFilterListNameHint,
              ),
              style: AppTextStyle.callout.of(context),
            ),
            TextFormField(
              controller: _url,
              autofocus: true,
              decoration: InputDecoration(
                labelText: l10n.desktopFilterListUrlLabel,
                hintText: l10n.desktopFilterListUrlHint,
              ),
              style: AppTextStyle.callout.of(context).toMonospace,
              onChanged: (_) {
                if (_invalid) setState(() => _invalid = false);
              },
              onFieldSubmitted: (_) => _submit(),
            ),
            if (_invalid)
              Text(
                l10n.desktopFilterListNeedUrl,
                style: AppTextStyle.caption1
                    .of(context)
                    .copyWith(color: colorScheme.error),
              ),
          ],
        ),
      ),
    );
  }
}
