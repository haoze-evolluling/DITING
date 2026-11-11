import 'package:diting_shared/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

/// The explainer that opens a page: one muted paragraph inside a card, indented 16 and pushed 12
/// below the app bar.
///
/// Ten pages spelled this out byte for byte. As a shared widget the 12/16 rhythm lives in one place,
/// so the intro no longer drifts page by page. [extra] holds rows that belong inside the same card
/// (a progress line, a live status), and both keep the card's 8 gap.
class PageIntroCard extends StatelessWidget {
  const PageIntroCard({super.key, required this.text, this.extra = const []});

  final String text;
  final List<Widget> extra;

  @override
  Widget build(BuildContext context) {
    final paragraph = Text(text, style: context.listSubtitleStyle);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: CommonCard(
        padding: const EdgeInsets.all(16),
        child: extra.isEmpty
            ? paragraph
            // `stretch`, as the original per-page copies used: a status row must span the card rather
            // than centre itself the way a lone child of the card's button does.
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 8,
                children: [paragraph, ...extra],
              ),
      ),
    );
  }
}

/// A page-level paragraph with no card around it: same 16/12 insets as [PageIntroCard], but the
/// text sits straight on the page background, in the smaller caption size.
class PageIntroText extends StatelessWidget {
  const PageIntroText({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Text(text, style: context.listCaptionStyle),
    );
  }
}
