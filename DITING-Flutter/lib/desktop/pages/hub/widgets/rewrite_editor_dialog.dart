/// Add or edit one rewrite rule. The behaviour is `RewriteEditModal.vue`: shortcut targets for the
/// three common cases, an explicit record list for everything else, an optional response-code
/// override and an optional lifetime.
///
/// The dialog only builds a rule; the page sends it and re-reads what the service kept. A failure
/// code wins over the target checks, because a rule that answers NXDOMAIN needs no target at all.
library;

import 'package:diting/app/l10n/l10n.dart';
import 'package:diting/desktop/data/api/desktop_rewrite_models.dart';
import 'package:diting/desktop/widgets/desktop_picker.dart';
import 'package:diting/pages/home/dashboard/dashboard_card.dart';
import 'package:diting/pages/home/dashboard/dashboard_style.dart';
import 'package:diting/ui/ui.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// Opens the editor. Returns the rule to save, or null when cancelled.
Future<DesktopRewriteRule?> showRewriteEditor(
  BuildContext context, {
  DesktopRewriteRule? editing,
}) => showFloatingDialog<DesktopRewriteRule>(
  context: context,
  child: RewriteEditorDialog(editing: editing),
);

enum _TargetMode { shortcut, records }

enum _ShortcutType { address, cname, txt }

/// A record value example per type, taken from the service's own `$dnsrewrite` syntax. They are DNS
/// values, not prose, so they stay out of the ARB.
const Map<String, String> _recordHints = {
  'A': '10.0.0.5',
  'AAAA': 'fd00::5',
  'CNAME': 'target.lan',
  'TXT': 'v=spf1 ~all',
  'MX': '32 mail.lan',
  'SRV': '10 60 8080 sip.lan',
  'NS': 'ns1.lan',
  'PTR': 'host.lan',
  'HTTPS': '1 . alpn=h3 port=8443',
  'SVCB': '1 . alpn=h2,h3',
};

class _RecordDraft {
  _RecordDraft({required this.type, String value = ''})
    : value = TextEditingController(text: value);

  String type;
  final TextEditingController value;

  void dispose() => value.dispose();
}

class RewriteEditorDialog extends StatefulWidget {
  const RewriteEditorDialog({super.key, this.editing});

  final DesktopRewriteRule? editing;

  @override
  State<RewriteEditorDialog> createState() => _RewriteEditorDialogState();
}

class _RewriteEditorDialogState extends State<RewriteEditorDialog> {
  late final _domain = TextEditingController(
    text: widget.editing?.domain ?? '',
  );
  late final _ips = TextEditingController(
    text: widget.editing?.ips.join('\n') ?? '',
  );
  late final _cname = TextEditingController(text: widget.editing?.cname ?? '');
  late final _txt = TextEditingController(
    text: widget.editing?.txt.join('\n') ?? '',
  );
  late final _ttl = TextEditingController(
    text: (widget.editing?.ttl ?? 0) > 0 ? '${widget.editing!.ttl}' : '',
  );
  final _records = <_RecordDraft>[];

  _TargetMode _mode = _TargetMode.shortcut;
  _ShortcutType _shortcut = _ShortcutType.address;
  String _rcode = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    final editing = widget.editing;
    if (editing == null) return;
    _rcode = editing.rcode;
    for (final record in editing.records) {
      _records.add(_RecordDraft(type: record.type, value: record.value));
    }
    final hasShortcut =
        editing.cname.isNotEmpty ||
        editing.ips.isNotEmpty ||
        editing.txt.isNotEmpty;
    // A rule that only carries explicit records opens in record mode; anything the shortcut fields
    // can express stays in shortcut mode, as the console does.
    _mode = !hasShortcut && _records.isNotEmpty
        ? _TargetMode.records
        : _TargetMode.shortcut;
    if (editing.cname.isNotEmpty) {
      _shortcut = _ShortcutType.cname;
    } else if (editing.txt.isNotEmpty) {
      _shortcut = _ShortcutType.txt;
    }
  }

  @override
  void dispose() {
    _domain.dispose();
    _ips.dispose();
    _cname.dispose();
    _txt.dispose();
    _ttl.dispose();
    for (final record in _records) {
      record.dispose();
    }
    super.dispose();
  }

  static List<String> _lines(String text) => [
    for (final line in text.split('\n'))
      if (line.trim().isNotEmpty) line.trim(),
  ];

  List<DesktopRewriteRecord> get _validRecords => [
    for (final draft in _records)
      if (draft.value.text.trim().isNotEmpty)
        DesktopRewriteRecord(type: draft.type, value: draft.value.text.trim()),
  ];

  void _addRecord() {
    setState(() => _records.add(_RecordDraft(type: 'MX')));
  }

  void _removeRecord(int index) {
    setState(() => _records.removeAt(index).dispose());
  }

  void _save() {
    final l10n = context.l10n;
    final domain = _domain.text.trim().toLowerCase();
    if (domain.isEmpty) {
      setState(() => _error = l10n.desktopRewriteDomainRequired);
      return;
    }
    final ttl = int.tryParse(_ttl.text.trim()) ?? 0;
    final records = _validRecords;

    // A failure code replaces every record, so the target checks would only force the user to fill
    // in something that is never returned.
    if (_rcode.isNotEmpty && _rcode != 'NOERROR') {
      popFloatingDialog(
        context,
        DesktopRewriteRule(
          domain: domain,
          records: records,
          rcode: _rcode,
          ttl: ttl,
        ),
      );
      return;
    }

    var ips = const <String>[];
    var cname = '';
    var txt = const <String>[];
    if (_mode == _TargetMode.records) {
      if (records.isEmpty) {
        setState(() => _error = l10n.desktopRewriteNeedRecord);
        return;
      }
    } else {
      switch (_shortcut) {
        case _ShortcutType.address:
          ips = _lines(_ips.text);
          if (ips.isEmpty) {
            setState(() => _error = l10n.desktopRewriteNeedIp);
            return;
          }
        case _ShortcutType.cname:
          cname = _cname.text.trim().toLowerCase();
          if (cname.isEmpty) {
            setState(() => _error = l10n.desktopRewriteNeedCname);
            return;
          }
        case _ShortcutType.txt:
          txt = _lines(_txt.text);
          if (txt.isEmpty) {
            setState(() => _error = l10n.desktopRewriteNeedTxt);
            return;
          }
      }
    }
    popFloatingDialog(
      context,
      DesktopRewriteRule(
        domain: domain,
        ips: ips,
        cname: cname,
        txt: txt,
        records: records,
        rcode: _rcode,
        ttl: ttl,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colorScheme = context.colorScheme;
    return CommonDialog(
      title: widget.editing == null
          ? l10n.desktopRewriteAddTitle
          : l10n.desktopRewriteEditTitle,
      hasFields: true,
      width: 520,
      actions: [
        TextButton(
          onPressed: () => popFloatingDialog(context),
          child: Text(l10n.commonCancel),
        ),
        TextButton(onPressed: _save, child: Text(l10n.commonSave)),
      ],
      child: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: [
              TextFormField(
                controller: _domain,
                decoration: InputDecoration(
                  labelText: l10n.desktopRewriteDomainLabel,
                  hintText: l10n.desktopRewriteDomainHint,
                  helperText: l10n.desktopRewriteDomainHelp,
                  helperMaxLines: 2,
                ),
                style: AppTextStyle.callout.of(context),
              ),
              Text(
                l10n.desktopRewriteTargetMode,
                style: DashboardText.rowTitle(context),
              ),
              SegmentedControl<_TargetMode>(
                value: _mode,
                segments: [
                  (_TargetMode.shortcut, l10n.desktopRewriteModeShortcut),
                  (_TargetMode.records, l10n.desktopRewriteModeRecords),
                ],
                onChanged: (mode) => setState(() {
                  _mode = mode;
                  _error = null;
                }),
              ),
              if (_mode == _TargetMode.shortcut)
                ..._shortcutFields(context)
              else
                ..._recordFields(context),
              Text(
                l10n.desktopRewriteRcodeLabel,
                style: DashboardText.rowTitle(context),
              ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: DesktopPicker(
                  glyph: AppGlyphs.warning,
                  semanticLabel: l10n.desktopRewriteRcodeLabel,
                  label: _rcode.isEmpty ? l10n.desktopRewriteRcodeNone : _rcode,
                  active: _rcode.isNotEmpty,
                  items: [
                    CommonPopupMenuItem(
                      label: l10n.desktopRewriteRcodeNone,
                      checked: _rcode.isEmpty,
                      onPressed: () => setState(() => _rcode = ''),
                    ),
                    for (final code in desktopRewriteRcodes)
                      CommonPopupMenuItem(
                        label: code,
                        checked: code == _rcode,
                        onPressed: () => setState(() => _rcode = code),
                      ),
                  ],
                ),
              ),
              if (_rcode.isNotEmpty && _rcode != 'NOERROR')
                Text(
                  l10n.desktopRewriteRcodeWarning,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.caption1
                      .of(context)
                      .copyWith(color: colorScheme.warning),
                ),
              TextFormField(
                controller: _ttl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: l10n.desktopRewriteTtlLabel,
                  hintText: l10n.desktopRewriteTtlHint,
                ),
                style: AppTextStyle.callout.of(context),
              ),
              if (_error case final error?)
                Text(
                  error,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.caption1
                      .of(context)
                      .copyWith(color: colorScheme.error),
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _shortcutFields(BuildContext context) {
    final l10n = context.l10n;
    return [
      Text(
        l10n.desktopRewriteTargetType,
        style: DashboardText.rowTitle(context),
      ),
      SegmentedControl<_ShortcutType>(
        value: _shortcut,
        segments: [
          (_ShortcutType.address, l10n.desktopRewriteTypeIp),
          (_ShortcutType.cname, l10n.desktopRewriteTypeCname),
          (_ShortcutType.txt, l10n.desktopRewriteTypeTxt),
        ],
        onChanged: (type) => setState(() => _shortcut = type),
      ),
      switch (_shortcut) {
        _ShortcutType.address => TextFormField(
          controller: _ips,
          minLines: 3,
          maxLines: 5,
          decoration: InputDecoration(
            labelText: l10n.desktopRewriteIpsLabel,
            helperText: l10n.desktopRewriteIpsHelp,
            helperMaxLines: 2,
          ),
          style: AppTextStyle.callout.of(context),
        ),
        _ShortcutType.cname => TextFormField(
          controller: _cname,
          decoration: InputDecoration(
            labelText: l10n.desktopRewriteCnameLabel,
            helperText: l10n.desktopRewriteCnameHelp,
            helperMaxLines: 2,
          ),
          style: AppTextStyle.callout.of(context),
        ),
        _ShortcutType.txt => TextFormField(
          controller: _txt,
          minLines: 3,
          maxLines: 5,
          decoration: InputDecoration(labelText: l10n.desktopRewriteTxtLabel),
          style: AppTextStyle.callout.of(context),
        ),
      },
    ];
  }

  List<Widget> _recordFields(BuildContext context) {
    final l10n = context.l10n;
    final colorScheme = context.colorScheme;
    return [
      Row(
        children: [
          Expanded(
            child: Text(
              l10n.desktopRewriteRecordsLabel,
              style: DashboardText.rowTitle(context),
            ),
          ),
          TonalButton(
            size: TonalButtonSize.compact,
            glyph: AppGlyphs.add,
            label: l10n.desktopRewriteRecordAdd,
            onPressed: _addRecord,
          ),
        ],
      ),
      if (_records.isEmpty)
        Text(
          l10n.desktopRewriteRecordEmpty,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyle.caption1
              .of(context)
              .copyWith(color: colorScheme.onSurfaceVariant),
        )
      else
        for (final (index, record) in _records.indexed)
          Row(
            spacing: 8,
            children: [
              DesktopPicker(
                glyph: AppGlyphs.layers,
                semanticLabel: l10n.desktopRewriteRecordsLabel,
                label: record.type,
                items: [
                  for (final type in desktopRewriteRecordTypes)
                    CommonPopupMenuItem(
                      label: type,
                      checked: type == record.type,
                      onPressed: () => setState(() => record.type = type),
                    ),
                ],
              ),
              Expanded(
                child: TextFormField(
                  controller: record.value,
                  decoration: InputDecoration(
                    hintText:
                        _recordHints[record.type] ??
                        l10n.desktopRewriteRecordValueHint,
                  ),
                  style: AppTextStyle.callout.of(context),
                ),
              ),
              SizedBox.square(
                dimension: 32,
                child: DashboardIconButton(
                  glyph: AppGlyphs.delete,
                  tooltip: l10n.desktopRewriteDelete,
                  onPressed: () => _removeRecord(index),
                ),
              ),
            ],
          ),
      Text(
        l10n.desktopRewriteRecordsHelp,
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
        style: AppTextStyle.caption1
            .of(context)
            .copyWith(color: colorScheme.onSurfaceVariant),
      ),
    ];
  }
}
