// Detail-panel sections of [AppRulesPage]: allowlisted domains and DNS-scoped rules.
//
// Split out only to keep the page file under 600 lines; an extension still sees the state's
// private helpers. Both sections build their rows through lazy slivers so a package with
// thousands of entries stays a flat first frame.
part of 'app_rules_page.dart';

extension _AppRulesDetail on _AppRulesPageState {
  /// Same rationale as [_allowDomainSlivers]: a package can carry hundreds of scoped rules, and
  /// they must not all be inflated before the first frame.
  List<Widget> _scopedRuleSlivers(InstalledApp app) {
    final actions = [
      IconButtonData(
        glyph: AppGlyphs.add,
        tooltip: context.l10n.appRulesAddDnsRule,
        onPressed: () => _addScopedRule(app),
      ),
    ];
    final footer = context.l10n.appRulesDnsScopeIntro;
    final rules = ref.watch(appScopedRulesProvider(app.packageName));
    if (rules.isLoading) {
      return [
        SliverToBoxAdapter(
          child: generateSection(
            title: context.l10n.appRulesDnsScopeSection,
            actions: actions,
            items: [
              ListItem(
                leading: GlyphIcon(AppGlyphs.info),
                title: Text(context.l10n.appRulesReadingRules),
                subtitle: Text(context.l10n.appRulesWait),
              ),
            ],
          ),
        ),
      ];
    }
    final value = rules.value;
    if (value == null || !value.available) {
      return [
        SliverToBoxAdapter(
          child: generateSection(
            title: context.l10n.appRulesDnsScopeSection,
            actions: actions,
            items: [
              ListItem(
                leading: const GlyphIcon(AppGlyphs.info),
                title: Text(context.l10n.appRulesRuleDbUnreadable),
                subtitle: Text(value?.error ?? context.l10n.appRulesRuleDbUnavailable),
              ),
            ],
          ),
        ),
      ];
    }
    final scoped = [...value.block, ...value.allow];
    if (scoped.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: generateSection(
            title: context.l10n.appRulesDnsScopeSection,
            actions: actions,
            items: [
              ListItem(
                leading: GlyphIcon(AppGlyphs.info),
                title: Text(context.l10n.appRulesNoScopedRules),
                subtitle: Text(context.l10n.appRulesNoScopedRulesSubtitle),
              ),
            ],
          ),
        ),
      ];
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

  /// Header-only when there is nothing to list; the rows themselves are built by a lazy sliver, so
  /// an app with thousands of allowlisted domains no longer inflates them all in one frame.
  List<Widget> _allowDomainSlivers(
    AppRulesDraft draft,
    InstalledApp app,
    Set<String> domains,
  ) {
    final actions = [
      IconButtonData(
        glyph: AppGlyphs.add,
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
                leading: GlyphIcon(AppGlyphs.info),
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

  /// Trailing section of the detail panel: the outer-network switch for this package.
  Widget _detailFooter(InstalledApp app, AsyncValue<AppScopedRules> rules) {
    final fullBlock = rules.value?.fullBlock ?? false;
    return Column(
      children: [
        generateSection(
          title: context.l10n.appRulesIsolationSection,
          items: [
            ListItem.toggle(
              leading: const GlyphIcon(AppGlyphs.wifiOff),
              title: Text(context.l10n.appRulesFullBlockToggle),
              subtitle: Text(context.l10n.appRulesFullBlockToggleSubtitle),
              value: fullBlock,
              onChanged: (value) => _toggleFullBlock(app, value),
            ),
            if (fullBlock)
              ListItem(
                leading: GlyphIcon(AppGlyphs.info),
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
