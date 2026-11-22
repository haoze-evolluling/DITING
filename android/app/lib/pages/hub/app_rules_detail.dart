part of 'app_rules_page.dart';

extension _AppRulesDetail on _AppRulesPageState {
  List<Widget> _scopedRuleSlivers(InstalledApp app) {
    final actions = [
      IconButtonData(
        glyph: TablerIcons.plus,
        tooltip: context.l10n.appRulesAddDnsRule,
        onPressed: () => _addScopedRule(app),
      ),
    ];
    final footer = context.l10n.appRulesDnsScopeIntro;
    final rules = ref.watch(appScopedRulesProvider(app.packageName));
    if (rules.isLoading) {
      return _scopedNotice(
        actions,
        context.l10n.appRulesReadingRules,
        context.l10n.appRulesWait,
      );
    }
    final value = rules.value;
    if (value == null || !value.available) {
      return _scopedNotice(
        actions,
        context.l10n.appRulesRuleDbUnreadable,
        value?.error ?? context.l10n.appRulesRuleDbUnavailable,
      );
    }
    final scoped = [...value.block, ...value.allow];
    if (scoped.isEmpty) {
      return _scopedNotice(
        actions,
        context.l10n.appRulesNoScopedRules,
        context.l10n.appRulesNoScopedRulesSubtitle,
      );
    }
    return lazySectionSlivers(
      title: context.l10n.appRulesScopedCount(scoped.length),
      actions: actions,
      itemCount: scoped.length,
      footer: footer,
      itemBuilder: (context, index) {
        final rule = scoped[index];
        return AppScopedRuleRow(
          rule: rule,
          onToggle: (enabled) => _toggleScopedRule(app, rule, enabled),
          onDelete: () => _deleteScopedRule(app, rule),
        );
      },
    );
  }

  List<Widget> _scopedNotice(
    List<IconButtonData> actions,
    String title,
    String subtitle,
  ) {
    return [
      SliverToBoxAdapter(
        child: generateSection(
          title: context.l10n.appRulesDnsScopeSection,
          actions: actions,
          items: [
            ListItem(
              leading: const Icon(TablerIcons.info_circle),
              title: Text(title),
              subtitle: Text(subtitle),
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _allowDomainSlivers(
    AppRulesDraft draft,
    InstalledApp app,
    Set<String> domains,
  ) {
    final actions = [
      IconButtonData(
        glyph: TablerIcons.plus,
        tooltip: context.l10n.appRulesAddAllowDomain,
        onPressed: () => _addDomain(draft, app.packageName),
      ),
    ];
    if (domains.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: generateSection(
            title: context.l10n.appRulesAllowDomainTitle(0),
            actions: actions,
            items: [
              ListItem(
                title: Text(context.l10n.appRulesNoAllowDomains),
                subtitle: Text(context.l10n.appRulesNoAllowDomainsSubtitle),
                leading: Icon(TablerIcons.info_circle),
              ),
            ],
          ),
        ),
      ];
    }
    final sorted = domains.toList()..sort();
    return lazySectionSlivers(
      title: context.l10n.appRulesAllowDomainTitle(sorted.length),
      actions: actions,
      itemCount: sorted.length,
      itemBuilder: (context, index) {
        final domain = sorted[index];
        return AppAllowDomainRow(
          domain: domain,
          onDelete: () => _removeDomain(draft, app.packageName, domain),
        );
      },
      footer: context.l10n.appRulesAllowDomainFooter,
    );
  }

  Widget _detailFooter(InstalledApp app, AsyncValue<AppScopedRules> rules) {
    final fullBlock = rules.value?.fullBlock ?? false;
    return Column(
      children: [
        generateSection(
          title: context.l10n.appRulesIsolationSection,
          items: [
            ListItem.toggle(
              leading: const Icon(TablerIcons.wifi_off),
              title: Text(context.l10n.appRulesFullBlockToggle),
              subtitle: Text(context.l10n.appRulesFullBlockToggleSubtitle),
              value: fullBlock,
              onChanged: (value) => _toggleFullBlock(app, value),
            ),
            if (fullBlock)
              ListItem(
                leading: Icon(TablerIcons.info_circle),
                title: Text(context.l10n.appRulesFullBlockOnTitle),
                subtitle: Text(context.l10n.appRulesFullBlockOnBody),
              ),
          ],
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
