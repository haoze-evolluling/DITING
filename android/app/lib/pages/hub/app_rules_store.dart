library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/mock_data.dart';
import 'package:diting_android/data/native/apps_bridge.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_android/state/installed_apps_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_android/widgets/app_icon_avatar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class AppRulesDraft {
  AppRulesDraft({required this.master, required Map<String, Set<String>> rules})
    : _baseline = _copy(rules),
      _baselineMaster = master,
      _rules = _copy(rules);

  factory AppRulesDraft.load(LegacySettings settings) => AppRulesDraft(
    master: settings.appAllowlistEnabled,
    rules: settings.appAllowlistRules,
  );

  bool master;

  final Map<String, Set<String>> _baseline;
  final Map<String, Set<String>> _rules;
  bool _baselineMaster;

  Map<String, Set<String>> get rules => _rules;

  int get configuredApps => _rules.length;

  int get totalDomains =>
      _rules.values.fold<int>(0, (sum, domains) => sum + domains.length);

  Set<String> domainsOf(String packageName) => _rules[packageName] ?? const {};

  bool isConfigured(String packageName) => domainsOf(packageName).isNotEmpty;

  void addDomain(String packageName, String domain) {
    final trimmed = domain.trim();
    if (trimmed.isEmpty) {
      return;
    }
    (_rules[packageName] ??= <String>{}).add(trimmed);
  }

  void removeDomain(String packageName, String domain) {
    final domains = _rules[packageName];
    if (domains == null) {
      return;
    }
    domains.remove(domain);
    if (domains.isEmpty) {
      _rules.remove(packageName);
    }
  }

  void clearAll() => _rules.clear();

  bool get dirty {
    if (master != _baselineMaster || _rules.length != _baseline.length) {
      return true;
    }
    return _rules.entries.any((entry) {
      final baseline = _baseline[entry.key];
      return baseline == null ||
          baseline.length != entry.value.length ||
          !baseline.containsAll(entry.value);
    });
  }

  void commit() {
    _baseline
      ..clear()
      ..addAll(_copy(_rules));
    _baselineMaster = master;
  }

  String get baselineKey => appRulesKey(_baselineMaster, _baseline);

  static Map<String, Set<String>> _copy(Map<String, Set<String>> source) => {
    for (final entry in source.entries) entry.key: {...entry.value},
  };
}

String appRulesKey(bool master, Map<String, Set<String>> rules) {
  final parts = <String>[];
  for (final packageName in rules.keys.toList()..sort()) {
    final domains = rules[packageName]!.toList()..sort();
    parts.add('$packageName=${domains.join(',')}');
  }
  return '$master|${parts.join(';')}';
}

void saveAppRules(WidgetRef ref, AppRulesDraft draft) {
  ref.writeSettings((settings) {
    settings.setAppAllowlistEnabled(draft.master);
    settings.setAppAllowlistRules(draft.rules);
  });
}

List<InstalledApp> appRulesVisibleApps({
  required List<InstalledApp> apps,
  required String query,
  required AppListFilter filter,
  required AppListSort sort,
  required AppRulesDraft draft,
}) {
  final needle = query.trim().toLowerCase();
  final configured = {
    for (final app in apps)
      if (draft.isConfigured(app.packageName)) app.packageName,
  };
  final visible = [
    for (final app in apps)
      if (filter.accept(app, configured) && app.matches(needle)) app,
  ];
  visible.sort((a, b) {
    final aConfigured = draft.isConfigured(a.packageName);
    final bConfigured = draft.isConfigured(b.packageName);
    if (aConfigured != bConfigured) {
      return aConfigured ? -1 : 1;
    }
    return sort.compare(a, b);
  });
  return visible;
}

class AppRuleAppRow extends StatelessWidget {
  const AppRuleAppRow({
    super.key,
    required this.app,
    required this.domainCount,
    required this.onTap,
  });

  final InstalledApp app;
  final int domainCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final configured = domainCount > 0;
    return ListItem(
      leading: AppIconAvatar(packageName: app.packageName),
      title: Text(app.label, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        context.l10n.appRulesAllowCount(app.packageName, domainCount),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTextRole.supportingText.of(context),
      ),
      trailing: (configured || app.isSystem)
          ? Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 6,
              children: [
                if (configured)
                  MetaChip(label: context.l10n.appRulesConfigured),
                if (app.isSystem) MetaChip(label: context.l10n.appRulesSystem),
              ],
            )
          : null,
      onTap: onTap,
    );
  }
}

class AppAllowDomainRow extends StatelessWidget {
  const AppAllowDomainRow({
    super.key,
    required this.domain,
    required this.onDelete,
  });

  final String domain;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return ListItem(
      leading: const Icon(TablerIcons.rosette_discount_check, size: 20),
      title: Text(domain, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(context.l10n.appRulesIncludeSub),
      trailing: IconButton(
        tooltip: context.l10n.appRulesDelete,
        onPressed: onDelete,
        icon: const Icon(TablerIcons.trash, size: 20),
      ),
    );
  }
}

Future<String?> showAppAllowDomainDialog(BuildContext context) async {
  return showFloatingDialog<String>(
    context: context,
    child: const _AllowDomainDialog(),
  );
}

class _AllowDomainDialog extends StatefulWidget {
  const _AllowDomainDialog();

  @override
  State<_AllowDomainDialog> createState() => _AllowDomainDialogState();
}

class _AllowDomainDialogState extends State<_AllowDomainDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      return;
    }
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    return CommonDialog(
      title: context.l10n.appRulesAddDomainTitle,
      hasFields: true,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.appRulesCancel),
        ),
        TextButton(onPressed: _submit, child: Text(context.l10n.appRulesAdd)),
      ],
      child: TextField(
        controller: _controller,
        autocorrect: false,
        autofocus: true,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          labelText: context.l10n.appRulesDomain,
          hintText: 'api.example.com',
          helperText: context.l10n.appRulesDomainHint,
        ),
      ),
    );
  }
}

class AppScopedRuleRow extends StatelessWidget {
  const AppScopedRuleRow({
    super.key,
    required this.rule,
    required this.onToggle,
    required this.onDelete,
  });

  final MockRule rule;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final isAllow = rule.kind == RuleKind.allow;
    return ListItem(
      leading: Icon(
        isAllow ? TablerIcons.rosette_discount_check : TablerIcons.shield,
        size: 20,
        color: isAllow
            ? context.colorScheme.primary
            : context.colorScheme.error,
      ),
      title: Text(rule.pattern, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        isAllow
            ? context.l10n.appRulesAllowlistRow
            : context.l10n.appRulesBlocklistRow,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (rule.important) MetaChip(label: context.l10n.appRulesImportant),
          IconButton(
            tooltip: rule.enabled
                ? context.l10n.appRulesDisable
                : context.l10n.appRulesEnable,
            onPressed: () => onToggle(!rule.enabled),
            icon: Icon(
              rule.enabled ? TablerIcons.check : TablerIcons.x,
              size: 20,
            ),
          ),
          IconButton(
            tooltip: context.l10n.appRulesDelete,
            onPressed: onDelete,
            icon: const Icon(TablerIcons.trash, size: 20),
          ),
        ],
      ),
    );
  }
}

typedef AppScopedRuleInput = ({RuleKind kind, String pattern});

Future<AppScopedRuleInput?> showAppScopedRuleDialog(
  BuildContext context,
) async {
  return showFloatingDialog<AppScopedRuleInput>(
    context: context,
    child: const _ScopedRuleDialog(),
  );
}

class _ScopedRuleDialog extends StatefulWidget {
  const _ScopedRuleDialog();

  @override
  State<_ScopedRuleDialog> createState() => _ScopedRuleDialogState();
}

class _ScopedRuleDialogState extends State<_ScopedRuleDialog> {
  final _controller = TextEditingController();
  var _kind = RuleKind.block;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final pattern = _controller.text.trim();
    if (pattern.isEmpty) {
      return;
    }
    Navigator.of(context).pop((kind: _kind, pattern: pattern));
  }

  @override
  Widget build(BuildContext context) {
    return CommonDialog(
      title: context.l10n.appRulesAddRuleTitle,
      hasFields: true,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.appRulesCancel),
        ),
        TextButton(onPressed: _submit, child: Text(context.l10n.appRulesAdd)),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedControl<RuleKind>(
            segments: [
              (RuleKind.block, context.l10n.appRulesBlocklist),
              (RuleKind.allow, context.l10n.appRulesAllowlist),
            ],
            value: _kind,
            onChanged: (value) => setState(() => _kind = value),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autocorrect: false,
            autofocus: true,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: context.l10n.appRulesDomain,
              hintText: 'ads.example.com',
              helperText: context.l10n.appRulesRuleDomainHint,
            ),
          ),
        ],
      ),
    );
  }
}
