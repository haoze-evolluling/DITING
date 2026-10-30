/// "Notification details" section of the notification page: which request counts the running
/// service shows, and in which order. Enabled items are dragged into order; the rest sit below.
library;

import 'package:diting/app/l10n/l10n.dart';
import 'package:diting/state/notification_stats_providers.dart';
import 'package:diting/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class NotificationStatsSection extends ConsumerWidget {
  const NotificationStatsSection({
    super.key,
    required this.enabled,
    required this.onChanged,
  });

  /// False while the notification is not persistent; the items then have nowhere to show.
  final bool enabled;

  /// Called after every change so the page can repaint the running notification.
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(notificationStatsProvider);
    final notifier = ref.read(notificationStatsProvider.notifier);
    final hidden = [
      for (final item in NotificationStatItem.values)
        if (!items.contains(item)) item,
    ];
    void toggle(NotificationStatItem item) {
      notifier.toggle(item);
      onChanged();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListHeader(title: context.l10n.notificationStatsSection),
        if (items.isEmpty)
          generateSection(
            items: [
              ListItem(
                leading: const GlyphIcon(AppGlyphs.info),
                title: Text(context.l10n.notificationStatsEmpty),
              ),
            ],
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ReorderableListView.builder(
              // The page already scrolls; a nested scrollable would steal drag gestures.
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              proxyDecorator: commonProxyDecorator,
              itemCount: items.length,
              onReorderItem: (oldIndex, newIndex) {
                notifier.move(oldIndex, newIndex);
                onChanged();
              },
              itemBuilder: (context, index) {
                final item = items[index];
                return ReorderableDelayedDragStartListener(
                  key: ValueKey(item),
                  index: index,
                  enabled: enabled,
                  child: ItemPositionProvider(
                    position: ItemPosition.get(index, items.length),
                    child: _EnabledRow(
                      item: item,
                      index: index,
                      enabled: enabled,
                      onToggle: () => toggle(item),
                    ),
                  ),
                );
              },
            ),
          ),
        ListFooter(text: context.l10n.notificationStatsFooter),
        if (hidden.isNotEmpty)
          generateSection(
            title: context.l10n.notificationStatsHidden,
            items: [
              for (final item in hidden)
                ListItem.toggle(
                  title: Text(item.label(context.l10n)),
                  subtitle: Text(item.description(context.l10n)),
                  leading: GlyphIcon(item.glyph),
                  value: false,
                  onChanged: enabled ? (_) => toggle(item) : null,
                ),
            ],
          ),
      ],
    );
  }
}

/// An enabled row: the switch removes it, the trailing handle drags it.
class _EnabledRow extends StatelessWidget {
  const _EnabledRow({
    required this.item,
    required this.index,
    required this.enabled,
    required this.onToggle,
  });

  final NotificationStatItem item;
  final int index;
  final bool enabled;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return ListItem(
      title: Text(item.label(context.l10n)),
      subtitle: Text(item.description(context.l10n)),
      leading: GlyphIcon(item.glyph),
      padding: const EdgeInsets.only(left: 16, right: 4),
      onTap: enabled ? onToggle : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CommonSwitch(
            value: true,
            onChanged: enabled ? (_) => onToggle() : null,
          ),
          ReorderableDragStartListener(
            index: index,
            enabled: enabled,
            child: const MouseRegion(
              cursor: SystemMouseCursors.grab,
              child: SizedBox.square(
                dimension: kMinInteractiveDimension,
                child: Center(child: GlyphIcon(AppGlyphs.dragHandle)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
