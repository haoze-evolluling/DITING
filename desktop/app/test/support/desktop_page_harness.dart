/// Pumps the real `DesktopApp` against [FakeDesktopBackend], with the service reads a page makes
/// answered by the fake instead of the network.
library;

import 'package:diting_desktop/app/desktop_app.dart';
import 'package:diting_desktop/data/api/desktop_api_providers.dart';
import 'package:diting_desktop/data/api/desktop_event_client.dart';
import 'package:diting_desktop/data/api/desktop_live_providers.dart';
import 'package:diting_shared/data/prefs/legacy_prefs_store.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'desktop_api_fakes.dart';

/// Mounts the app at [path] (home when omitted). [store] keeps a handle on the preferences for
/// tests that assert what was persisted; [seed] is shorthand when only the initial values matter.
Future<FakeDesktopBackend> pumpDesktopPage(
  WidgetTester tester, {
  String? path,
  FakeDesktopBackend? backend,
  MemoryLegacyPrefsStore? store,
  Map<String, Map<String, Object?>>? seed,
  Size size = const Size(1280, 900),
  Stream<DesktopEvent>? live,
  bool polling = false,
  List<Override> overrides = const [],
}) async {
  final fake = backend ?? FakeDesktopBackend();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        legacyPrefsStoreProvider.overrideWithValue(
          store ?? MemoryLegacyPrefsStore(seed),
        ),
        desktopPollingEnabledProvider.overrideWithValue(polling),
        desktopLiveEnabledProvider.overrideWithValue(false),
        if (live != null) desktopEventStreamProvider.overrideWithValue(live),
        desktopApiClientProvider.overrideWithValue(fake.client()),
        ...overrides,
      ],
      child: DesktopApp(initialLocation: path),
    ),
  );
  await tester.pumpAndSettle();
  return fake;
}

/// Taps a control that may sit below the fold. The scaffold's bar floats over the page, so the
/// element is centered rather than parked at y=0 where the bar would eat the tap.
///
/// The settle before [Scrollable.ensureVisible] matters: a caller that just typed into a field has
/// a frame in flight, and measuring the old layout under-scrolls by exactly the height the field
/// grew.
Future<void> tapAt(WidgetTester tester, Finder finder) async {
  await tester.pumpAndSettle();
  await Scrollable.ensureVisible(
    tester.element(finder),
    alignment: 0.5,
    duration: Duration.zero,
  );
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Lets the current snackbar expire, so the next action's message is the one on screen.
Future<void> clearMessages(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

/// Restricts a finder to the modal on screen, which repeats labels used by the page behind it.
Finder inDialog(Finder matching) =>
    find.descendant(of: find.byType(CommonDialog), matching: matching);
