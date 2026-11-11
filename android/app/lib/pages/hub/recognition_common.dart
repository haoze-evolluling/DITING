/// Shared avatar, row and list skeleton for the recognition lists, so they cannot drift apart.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/recognition/recognition_members.dart';
import 'package:diting_android/state/recognition_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_android/widgets/empty_state.dart';
import 'package:diting_android/widgets/page_intro.dart';
import 'package:diting_android/widgets/status_pill.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Circular avatar from the cloud, cached on disk, with a person glyph when unavailable.
class RecognitionAvatar extends ConsumerWidget {
  const RecognitionAvatar({super.key, required this.member, this.size = 48});

  final RecognitionMember member;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fileName = member.avatarFileName;
    if (fileName == null) {
      return _frame(context, _placeholder(context));
    }
    final bytes = ref.watch(recognitionAvatarProvider(fileName)).value;
    if (bytes == null) {
      return _frame(context, _placeholder(context));
    }
    return _frame(
      context,
      Image.memory(
        bytes,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => _placeholder(context),
      ),
    );
  }

  Widget _placeholder(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final dimension = constraints.biggest.shortestSide;
      return Center(
        child: GlyphIcon(
          AppGlyphs.account,
          size: dimension * 0.55,
          color: context.colorScheme.onSurfaceVariant.withValues(alpha: 0.55),
        ),
      );
    },
  );

  Widget _frame(BuildContext context, Widget child) {
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: context.colorScheme.surfaceContainerHigh,
      ),
      child: child,
    );
  }
}

class RecognitionMemberRow extends StatelessWidget {
  const RecognitionMemberRow({super.key, required this.member});

  final RecognitionMember member;

  @override
  Widget build(BuildContext context) {
    return ListItem(
      leading: RecognitionAvatar(member: member),
      title: Row(
        children: [
          Flexible(
            child: Text(
              member.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (member.count > 1) ...[
            const SizedBox(width: 8),
            _SponsorCountBadge(count: member.count),
          ],
        ],
      ),
    );
  }
}

/// A small `×N` pill after a sponsor's name, marking how many times they supported the project.
/// Reuses [StatusPill] so the tint, radius and caption size stay the same as every other status tag
/// in the app.
class _SponsorCountBadge extends StatelessWidget {
  const _SponsorCountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return StatusPill(
      label: '× $count',
      color: context.colorScheme.primary,
      alpha: 0.12,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      style: AppTextStyle.caption2,
      tabular: true,
    );
  }
}

/// List page skeleton; the two pages differ only in `title`, `intro`, `sectionTitle` and
/// `sortable`.
class RecognitionListPage extends ConsumerStatefulWidget {
  const RecognitionListPage({
    super.key,
    required this.title,
    required this.intro,
    required this.sectionTitle,
    required this.select,
    this.sortable = false,
  });

  final String title;
  final String intro;
  final String sectionTitle;

  final List<RecognitionMember> Function(RecognitionMembers) select;

  final bool sortable;

  @override
  ConsumerState<RecognitionListPage> createState() =>
      _RecognitionListPageState();
}

class _RecognitionListPageState extends ConsumerState<RecognitionListPage> {
  bool _newestFirst = false;
  bool _requestedFirstLoad = false;

  @override
  void initState() {
    super.initState();
    // Fetch once even with an empty cache, otherwise a fresh install stays on "no list".
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureFresh());
  }

  void _ensureFresh() {
    if (!mounted) return;
    if (ref.read(recognitionMembersProvider).value == null) return;
    _requestedFirstLoad = true;
    ref.read(recognitionMembersProvider.notifier).ensureFresh();
  }

  Future<void> _refresh() async {
    await ref.read(recognitionMembersProvider.notifier).refresh();
    if (!mounted) return;
    final state = ref.read(recognitionMembersProvider).value;
    _toast(context, state?.error ?? context.l10n.recognitionUpdated);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(recognitionMembersProvider);
    final data = async.value;
    final state = data ?? const RecognitionState();
    // A silent refresh runs once after the first data arrives; it only hits the network
    // when the cache is older than `freshWindow`.
    if (!_requestedFirstLoad && data != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _ensureFresh());
    }
    final members = state.members;
    final visible = members == null
        ? const <RecognitionMember>[]
        : () {
            final list = widget.select(members);
            return widget.sortable && _newestFirst
                ? list.reversed.toList(growable: false)
                : list;
          }();

    return CommonScaffold(
      title: widget.title,
      iconActions: [
        IconButtonData(
          glyph: AppGlyphs.refresh,
          tooltip: context.l10n.recognitionRefresh,
          isLoading: state.isRefreshing,
          onPressed: _refresh,
        ),
        if (widget.sortable)
          IconButtonData(
            glyph: AppGlyphs.sort,
            tooltip: _newestFirst ? context.l10n.recognitionSortAsc : context.l10n.recognitionSortDesc,
            isSelected: _newestFirst,
            onPressed: () => setState(() => _newestFirst = !_newestFirst),
          ),
      ],
      body: PageBody(
        children: [
          PageIntroCard(text: widget.intro),
          if (!state.hasMembers && (state.isRefreshing || data == null))
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 64),
              child: Center(child: CommonCircleLoading()),
            )
          else if (!state.hasMembers)
            EmptyStateBox(
              minHeight: 320,
              child: NullStatus(
                label: state.error == null ? context.l10n.recognitionEmpty : context.l10n.recognitionLoadFailed,
                description: state.error ?? context.l10n.recognitionEmptyBody,
                illustration: state.error == null
                    ? NullStatusIllustration.data
                    : NullStatusIllustration.error,
                action: TextButton(
                  onPressed: _refresh,
                  child: Text(state.error == null ? context.l10n.recognitionLoad : context.l10n.recognitionRetry),
                ),
              ),
            )
          else if (visible.isEmpty)
            EmptyStateBox(
              minHeight: 280,
              child: NullStatus(
                label: context.l10n.recognitionNoMembers,
                description: context.l10n.recognitionNoMembersBody,
                illustration: NullStatusIllustration.data,
                action: TextButton(
                  onPressed: _refresh,
                  child: Text(context.l10n.recognitionRefreshShort),
                ),
              ),
            )
          else
            generateSection(
              title: '${widget.sectionTitle}（${visible.length}）',
              items: [
                for (final member in visible)
                  RecognitionMemberRow(member: member),
              ],
            ),
          if (state.hasMembers) _StatusFooter(state: state),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// Footer stating where the data came from and when it updated. A failed refresh says
/// "showing the local cache" instead of pretending to succeed.
class _StatusFooter extends StatelessWidget {
  const _StatusFooter({required this.state});

  final RecognitionState state;

  @override
  Widget build(BuildContext context) {
    final parts = <String>[];
    if (state.error != null) {
      parts.add(state.error!);
    } else if (state.fromCache) {
      parts.add(context.l10n.recognitionCached);
    }
    final updatedAt = state.updatedAt;
    if (updatedAt != null) {
      parts.add(context.l10n.recognitionLastUpdate(_formatTime(updatedAt)));
    }
    if (parts.isEmpty) {
      parts.add(context.l10n.recognitionCloudNote);
    }
    return ListFooter(text: parts.join(' · '));
  }

  static String _formatTime(DateTime time) {
    final local = time.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}

void _toast(BuildContext context, String text) {
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(
      content: Text(text),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(milliseconds: 2000),
    ),
  );
}
