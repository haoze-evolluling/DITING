import 'package:diting/app/l10n/l10n.dart';
import 'package:diting/ui/ui.dart';
import 'package:diting/widgets/stat_strip.dart';
import 'package:material_ui/material_ui.dart';

/// Temporary bootstrap surface. The next step replaces this page with the Android six-branch
/// shell; no desktop-specific visual language or placeholder feature data belongs here.
class DesktopBootstrapPage extends StatelessWidget {
  const DesktopBootstrapPage({super.key});

  @override
  Widget build(BuildContext context) {
    return CommonScaffold(
      title: context.l10n.appTitle,
      body: PageBody(
        children: [
          NullStatus(
            label: context.l10n.bottomBarHome,
            illustration: NullStatusIllustration.data,
          ),
        ],
      ),
    );
  }
}
