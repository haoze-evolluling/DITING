/// The automation rule editor (A1 / A13): trigger + match + actions over one `spec_json` document.
///
/// The editor is deliberately small — one trigger, a network condition when the trigger is
/// `network`, and up to three common actions (pause, block services, switch profile). The document
/// it writes is the same shape `AutomationEngine` evaluates, so the preview and the runtime read
/// one schema.
library;

import 'package:diting_android/data/db/automation_models.dart';
import 'package:diting_android/data/db/rust_services_core.dart';
import 'package:diting_android/state/automation_providers.dart';
import 'package:diting_android/widgets/page_intro.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

class AutomationEditPage extends ConsumerStatefulWidget {
  const AutomationEditPage({super.key, required this.ruleId});

  /// `new` for a fresh rule, otherwise the row id.
  final String ruleId;

  @override
  ConsumerState<AutomationEditPage> createState() => _AutomationEditPageState();
}

class _AutomationEditPageState extends ConsumerState<AutomationEditPage> {
  final _name = TextEditingController();
  final _priority = TextEditingController(text: '100');
  final _start = TextEditingController(text: '09:00');
  final _end = TextEditingController(text: '23:00');
  final _minutes = TextEditingController(text: '60');

  String _trigger = AutomationSpec.triggerManual;
  String _match = 'all';
  final Set<String> _networkTypes = {'wifi'};
  bool _pause = false;
  bool _blockServices = false;
  final Set<String> _services = {};
  String? _switchProfile;

  List<Map<String, Object?>> _catalog = const [];
  List<AutomationProfile> _profiles = const [];
  bool _loaded = false;
  bool _servicesUnavailable = false;

  bool get _isNew => widget.ruleId == 'new';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _priority.dispose();
    _start.dispose();
    _end.dispose();
    _minutes.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    // Catalog is Rust-owned; a missing core degrades to "no presets", never a crash.
    try {
      final answer = RustServicesCore.instance.catalog();
      final raw = answer['services'];
      if (raw is List) {
        _catalog = [
          for (final item in raw)
            if (item is Map) Map<String, Object?>.from(item),
        ];
      }
    } catch (_) {
      _servicesUnavailable = true;
    }
    try {
      _profiles = await ref.read(automationProfilesProvider.future);
    } catch (_) {
      _profiles = const [];
    }
    if (!_isNew) {
      final rule = await ref.read(automationRuleProvider(widget.ruleId).future);
      if (rule != null) _apply(rule);
    }
    if (mounted) setState(() => _loaded = true);
  }

  void _apply(AutomationRule rule) {
    _name.text = rule.name;
    _priority.text = '${rule.priority}';
    _match = rule.match;
    _trigger = rule.triggerType;
    final trigger = rule.spec['trigger'];
    if (trigger is Map && trigger['window'] is Map) {
      final window = Map<String, Object?>.from(trigger['window'] as Map);
      _start.text = _minutesToClock((window['startMin'] as num?)?.toInt() ?? 540);
      _end.text = _minutesToClock((window['endMin'] as num?)?.toInt() ?? 1380);
    }
    for (final condition in rule.conditions) {
      if (condition['type'] == 'network' && condition['types'] is List) {
        _networkTypes
          ..clear()
          ..addAll([
            for (final item in condition['types'] as List)
              if (item is String) item,
          ]);
      }
    }
    for (final action in rule.actions) {
      switch (action['type']) {
        case AutomationSpec.actionPause:
          _pause = true;
          _minutes.text = '${(action['minutes'] as num?)?.toInt() ?? 60}';
        case AutomationSpec.actionBlockServices:
          _blockServices = true;
          if (action['services'] is List) {
            _services.addAll([
              for (final item in action['services'] as List)
                if (item is String) item,
            ]);
          }
        case AutomationSpec.actionSwitchProfile:
          _switchProfile = action['profileId'] as String?;
      }
    }
  }

  Future<void> _save() async {
    final actions = <Map<String, Object?>>[
      if (_pause)
        {'type': AutomationSpec.actionPause, 'minutes': _parseMinutes(_minutes.text)},
      if (_blockServices && _services.isNotEmpty)
        {'type': AutomationSpec.actionBlockServices, 'services': _services.toList()},
      if (_switchProfile != null)
        {'type': AutomationSpec.actionSwitchProfile, 'profileId': _switchProfile},
    ];
    final trigger = <String, Object?>{'type': _trigger};
    if (_trigger == AutomationSpec.triggerSchedule) {
      trigger['window'] = {
        'days': [1, 2, 3, 4, 5, 6, 7],
        'startMin': _parseClock(_start.text),
        'endMin': _parseClock(_end.text),
      };
    }
    final conditions = <Map<String, Object?>>[
      if (_trigger == AutomationSpec.triggerNetwork && _networkTypes.isNotEmpty)
        {'type': 'network', 'types': _networkTypes.toList()},
    ];
    final now = DateTime.now().millisecondsSinceEpoch;
    final existing = _isNew
        ? null
        : await ref.read(automationRuleProvider(widget.ruleId).future);
    final rule = AutomationRule(
      id: _isNew ? newAutomationId('rule') : widget.ruleId,
      name: _name.text.trim(),
      enabled: existing?.enabled ?? true,
      priority: int.tryParse(_priority.text.trim()) ?? 100,
      match: _match,
      spec: {'trigger': trigger, 'conditions': conditions, 'actions': actions},
      lastRunAt: existing?.lastRunAt ?? 0,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
    await ref.read(automationControllerProvider).saveRule(rule);
    if (mounted) context.pop();
  }

  Future<void> _delete() async {
    await ref.read(automationControllerProvider).deleteRule(widget.ruleId);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return CommonScaffold(
      title: _isNew ? context.l10n.automationNewTitle : context.l10n.automationEditTitle,
      actions: [
        if (!_isNew)
          IconButton(
            tooltip: context.l10n.automationDelete,
            onPressed: _delete,
            icon: const GlyphIcon(AppGlyphs.remove),
          ),
        TextButton(
          onPressed: _loaded ? _save : null,
          child: Text(context.l10n.automationSave),
        ),
      ],
      body: PageBody(
        children: [
          PageIntroCard(text: context.l10n.automationEditIntro),
          _paddedCard(
            context,
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 16,
              children: [
                LabeledInputField(
                  label: context.l10n.automationRuleName,
                  controller: _name,
                ),
                LabeledInputField(
                  label: context.l10n.automationPriority,
                  controller: _priority,
                  keyboardType: TextInputType.number,
                ),
              ],
            ),
          ),
          _Section(title: context.l10n.automationTrigger, child: _triggerSection(context)),
          _Section(title: context.l10n.automationMatch, child: _matchSection(context)),
          _Section(title: context.l10n.automationActions, child: _actionsSection(context)),
        ],
      ),
    );
  }

  Widget _triggerSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LabeledSelectField<String>(
          value: _trigger,
          items: [
            for (final entry in _triggerOptions(context)) (entry.$1, entry.$2),
          ],
          onChanged: (value) => setState(() => _trigger = value),
        ),
        if (_trigger == AutomationSpec.triggerSchedule) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _clockField(_start, context.l10n.automationScheduleStart)),
              const SizedBox(width: 12),
              Expanded(child: _clockField(_end, context.l10n.automationScheduleEnd)),
            ],
          ),
        ],
        if (_trigger == AutomationSpec.triggerNetwork) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final type in const ['wifi', 'cellular', 'ethernet'])
                FilterChip(
                  label: Text(type),
                  selected: _networkTypes.contains(type),
                  onSelected: (selected) => setState(() {
                    if (selected) {
                      _networkTypes.add(type);
                    } else {
                      _networkTypes.remove(type);
                    }
                  }),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _matchSection(BuildContext context) => SegmentedButton<String>(
    segments: [
      ButtonSegment(value: 'all', label: Text(context.l10n.automationMatchAll)),
      ButtonSegment(value: 'any', label: Text(context.l10n.automationMatchAny)),
    ],
    selected: {_match},
    onSelectionChanged: (value) => setState(() => _match = value.first),
  );

  Widget _actionsSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(context.l10n.automationActionPause),
          value: _pause,
          onChanged: (value) => setState(() => _pause = value),
        ),
        if (_pause)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: LabeledInputField(
              label: context.l10n.automationMinutes,
              controller: _minutes,
              keyboardType: TextInputType.number,
            ),
          ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(context.l10n.automationActionBlockServices),
          subtitle: _servicesUnavailable
              ? Text(context.l10n.automationServicesUnavailable)
              : null,
          value: _blockServices,
          onChanged: _servicesUnavailable
              ? null
              : (value) => setState(() => _blockServices = value),
        ),
        if (_blockServices)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final service in _catalog)
                  FilterChip(
                    label: Text('${service['name']}'),
                    selected: _services.contains(service['id']),
                    onSelected: (selected) => setState(() {
                      final id = '${service['id']}';
                      if (selected) {
                        _services.add(id);
                      } else {
                        _services.remove(id);
                      }
                    }),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        LabeledSelectField<String?>(
          value: _switchProfile,
          items: [
            (null, context.l10n.automationSwitchProfileNone),
            for (final profile in _profiles) (profile.id, profile.name),
          ],
          onChanged: (value) => setState(() => _switchProfile = value),
        ),
      ],
    );
  }

  Widget _clockField(TextEditingController controller, String label) => LabeledInputField(
    label: label,
    controller: controller,
    hintText: 'HH:mm',
  );

  static List<(String, String)> _triggerOptions(BuildContext context) => [
    (AutomationSpec.triggerManual, context.l10n.automationTriggerManual),
    (AutomationSpec.triggerSchedule, context.l10n.automationTriggerSchedule),
    (AutomationSpec.triggerNetwork, context.l10n.automationTriggerNetwork),
    (AutomationSpec.triggerState, context.l10n.automationTriggerState),
  ];

  static int _parseClock(String text) {
    final parts = text.trim().split(':');
    final hour = int.tryParse(parts.first) ?? 0;
    final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    return (hour.clamp(0, 23) * 60 + minute.clamp(0, 59));
  }

  static String _minutesToClock(int minutes) {
    final hour = (minutes ~/ 60).toString().padLeft(2, '0');
    final minute = (minutes % 60).toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  static int _parseMinutes(String text) {
    final value = int.tryParse(text.trim()) ?? 60;
    return value.clamp(1, 24 * 60);
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return _paddedCard(
      context,
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

Widget _paddedCard(BuildContext context, Widget child) => Padding(
  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
  child: CommonCard(padding: const EdgeInsets.all(16), child: child),
);
