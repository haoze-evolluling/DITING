/// Font settings page (upstream `views/font_family.dart`).
///
/// The app bundles no fonts: the list is the system default plus whatever TTF/OTF files the user
/// imported. Android exposes no system-font enumeration API without a native channel, so there is
/// nothing to scan for — a fixed list of vendor family names would only ever render in the fallback
/// face on most devices.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/data/fonts/font_repository.dart';
import 'package:diting_android/pages/appearance/appearance_shared_pages.dart';
import 'package:diting_android/routes/system_routes.dart';
import 'package:diting_shared/state/appearance_extra_providers.dart';
import 'package:diting_shared/state/appearance_providers.dart';
import 'package:diting_android/state/font_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_android/widgets/nav_entry_row.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

class FontFamilyPage extends ConsumerStatefulWidget {
  const FontFamilyPage({super.key});

  @override
  ConsumerState<FontFamilyPage> createState() => _FontFamilyPageState();
}

class _FontFamilyPageState extends ConsumerState<FontFamilyPage> {
  /// Importing reads and parses a file, so the button shows a spinner while the picker is open.
  bool _importing = false;

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(selectedFontFamilyProvider);
    final scale = ref.watch(textScaleProvider);
    final fonts = ref.watch(importedFontsProvider);
    return CommonScaffold(
      title: context.l10n.fontFamilyTitle,
      body: PageBody(
        dockSpacer: false,
        children: [
          // Font size entry: the slider lives in `/font-size`, so the
          // subtitle shows the current scale here.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: CommonCard(
              padding: EdgeInsets.zero,
              child: NavEntryRow(
                glyph: AppGlyphs.textSize,
                title: context.l10n.appearanceFontSizeLabel,
                subtitle: context.l10n.appearanceFontSizeCurrent(
                  (scale * 100).round(),
                ),
                onPressed: () => context.push(SystemPaths.fontSize),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _PreviewHero(
              family: selected,
              label: fontLabelOf(fonts, selected),
            ),
          ),
          const SizedBox(height: 12),
          generateSection(
            title: context.l10n.appearanceFontSection,
            items: [
              _FontRow(
                label: context.l10n.fontSystemDefault,
                description: context.l10n.fontFamilySystemDefault,
                family: null,
                selected: selected == null,
                onTap: () => _select(null),
              ),
              for (final font in fonts)
                _FontRow(
                  label: font.label,
                  description: context.l10n.fontFamilyImported,
                  family: font.family,
                  selected: selected == font.family,
                  onTap: () => _select(font.family),
                  onDelete: () => _delete(font),
                ),
            ],
            footer: fonts.isEmpty
                ? context.l10n.fontFamilyEmpty
                : context.l10n.fontFamilyFooter,
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _ImportCard(
              isImporting: _importing,
              onPressed: _importing ? null : _import,
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(context.l10n.fontFamilyLocalOnly, style: context.listCaptionStyle),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  void _select(String? family) {
    ref.read(selectedFontFamilyProvider.notifier).select(family);
  }

  Future<void> _import() async {
    setState(() => _importing = true);
    final result = await ref.read(fontRepositoryProvider).import();
    if (!mounted) {
      return;
    }
    setState(() => _importing = false);
    if (result.cancelled) {
      return;
    }
    final font = result.font;
    if (font == null) {
      showSettingHint(context, result.error ?? context.l10n.fontFamilyImportFailed);
      return;
    }
    // Refresh the list, then switch to the new font so the user sees it applied.
    ref.invalidate(importedFontsProvider);
    _select(font.family);
    showSettingHint(
      context,
      context.l10n.appearanceFontImported(font.label),
    );
  }

  Future<void> _delete(ImportedFont font) async {
    final confirmed = await showFloatingDialog<bool>(
      context: context,
      child: CommonDialog(
        title: context.l10n.fontFamilyDeleteTitle,
        destructive: true,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.commonDelete),
          ),
        ],
        child: Text(context.l10n.fontFamilyDeleteConfirm(font.label)),
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    // Fall back first: the engine keeps the registered bytes for the process lifetime, so the
    // selection has to move before the entry disappears.
    if (ref.read(selectedFontFamilyProvider) == font.family) {
      _select(null);
    }
    await ref.read(fontRepositoryProvider).delete(font);
    if (!mounted) {
      return;
    }
    ref.invalidate(importedFontsProvider);
    showSettingHint(
      context,
      context.l10n.appearanceFontDeleted(font.label),
    );
  }
}

/// Sample text rendered in the candidate face, labelled with the name the user picked.
class _PreviewHero extends StatelessWidget {
  const _PreviewHero({required this.family, required this.label});

  final String? family;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return CommonCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.appearancePoem,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyle.title2
                .of(context, emphasized: true)
                .copyWith(fontFamily: family),
          ),
          const SizedBox(height: 6),
          Text(
            'The quick brown fox jumps over the lazy dog · 0123456789',
            style: AppTextStyle.footnote
                .of(context)
                .copyWith(
                  fontFamily: family,
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 10),
          MetaChip(label: label),
        ],
      ),
    );
  }
}

/// One selectable font. `Aa` is drawn in the candidate face so the list itself previews each entry;
/// imported entries get a delete button in the trailing slot.
class _FontRow extends StatelessWidget {
  const _FontRow({
    required this.label,
    required this.description,
    required this.family,
    required this.selected,
    required this.onTap,
    this.onDelete,
  });

  final String label;
  final String description;
  final String? family;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return DecorationListItem(
      isSelected: selected,
      onPressed: onTap,
      leading: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: ShapeDecoration(
          shape: AppShape.sm,
          color: context.raisedSurfaceLevel.colorOf(colorScheme),
        ),
        child: Text(
          'Aa',
          style: AppTextStyle.subheadline
              .of(context, emphasized: true)
              .copyWith(
                fontFamily: family,
                color: colorScheme.onSurfaceVariant,
              ),
        ),
      ),
      title: Text(
        label,
        style: context.listTitleStyle.copyWith(fontFamily: family),
      ),
      subtitle: Text(description),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onDelete case final onDelete?)
            IconButton(
              tooltip: context.l10n.commonDelete,
              onPressed: onDelete,
              icon: const GlyphIcon(AppGlyphs.delete, size: 20),
            ),
          if (selected) const SelectionCheck() else const SizedBox(width: 24),
        ],
      ),
    );
  }
}

/// Import entry point, styled as a card so it reads as an action rather than another list row.
class _ImportCard extends StatelessWidget {
  const _ImportCard({required this.isImporting, required this.onPressed});

  final bool isImporting;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return CommonCard(
      onPressed: onPressed,
      inert: onPressed == null,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          GlyphIcon(
            AppGlyphs.importFile,
            size: commonCardIconSize,
            color: colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.l10n.fontFamilyImport, style: context.listTitleStyle),
                const SizedBox(height: 2),
                Text(
                  isImporting ? context.l10n.fontFamilyReading : context.l10n.fontFamilyPickFile,
                  style: context.listSubtitleStyle,
                ),
              ],
            ),
          ),
          if (isImporting)
            const CommonCircleLoading(size: 20)
          else
            const GlyphIcon(AppGlyphs.chevronForward, size: 20),
        ],
      ),
    );
  }
}
