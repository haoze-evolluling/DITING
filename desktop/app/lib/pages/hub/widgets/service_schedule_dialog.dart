/// One service's weekly plan, edited in a dialog and returned to the page.
///
/// The old desktop console's `ServiceScheduleModal.vue` is the blueprint: the same editor the global
/// time plan uses, with the meaning "block this service only inside these windows".
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_schedule_models.dart';
import 'package:diting_desktop/data/api/desktop_services_models.dart';
import 'package:diting_desktop/pages/hub/widgets/schedule_editor.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

/// Opens the editor. Returns the plan to save (possibly empty), or null when cancelled.
Future<List<DesktopSchedule>?> showServiceScheduleDialog(
  BuildContext context, {
  required DesktopBlockedService service,
  required List<DesktopSchedule> schedules,
}) => showFloatingDialog<List<DesktopSchedule>>(
  context: context,
  child: _ServiceScheduleDialog(service: service, schedules: schedules),
);

class _ServiceScheduleDialog extends StatefulWidget {
  const _ServiceScheduleDialog({
    required this.service,
    required this.schedules,
  });

  final DesktopBlockedService service;
  final List<DesktopSchedule> schedules;

  @override
  State<_ServiceScheduleDialog> createState() => _ServiceScheduleDialogState();
}

class _ServiceScheduleDialogState extends State<_ServiceScheduleDialog> {
  late List<DesktopSchedule> _rows = widget.schedules;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return CommonDialog(
      title: l10n.desktopServicesScheduleTitle(widget.service.name),
      hasFields: true,
      width: 640,
      actions: [
        TextButton(
          onPressed: () => popFloatingDialog(context),
          child: Text(l10n.commonCancel),
        ),
        TextButton(
          onPressed: () => popFloatingDialog(context, _rows),
          child: Text(l10n.desktopServicesScheduleSave),
        ),
      ],
      child: SizedBox(
        width: 580,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: [
              Text(
                l10n.desktopServicesScheduleBody,
                style: DashboardText.label(context),
              ),
              ScheduleEditor(
                rows: _rows,
                onChanged: (rows) => _rows = rows,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
