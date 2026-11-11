/// The log branch's live view: a bounded buffer of the queries the service pushes over
/// `/api/v1/events`, plus whether that channel is up.
///
/// A separate file from the log's reads, because this is a push source with its own lifetime: the
/// socket opens when the live card is on screen and closes with it, and a dead socket must not
/// affect the history table or the summary.
library;

import 'dart:async';

import 'package:diting_desktop/data/api/desktop_api_providers.dart';
import 'package:diting_desktop/data/api/desktop_event_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How many queries the live list keeps, newest first. The old desktop console caps its scrolling
/// buffer at 500; beyond that the oldest entries are the least interesting.
const int desktopLiveBufferSize = 500;

/// The push channel. Overridden in tests with a controller, so no test opens a socket.
final desktopEventStreamProvider = Provider<Stream<DesktopEvent>>((ref) {
  if (!ref.watch(desktopLiveEnabledProvider)) return const Stream.empty();
  final client = DesktopEventClient(
    config: ref.watch(desktopApiConfigProvider),
  );
  ref.onDispose(client.close);
  return client.events;
});

class DesktopLiveState {
  const DesktopLiveState({
    this.entries = const [],
    this.connected = false,
    this.paused = false,
  });

  /// Newest first, capped at [desktopLiveBufferSize].
  final List<DesktopLiveQuery> entries;

  /// Whether the socket is up. False before the first connection and after a drop.
  final bool connected;

  /// Frozen on purpose: while paused, arriving queries are dropped rather than queued, which is
  /// what the console's pause button does.
  final bool paused;

  DesktopLiveState copyWith({
    List<DesktopLiveQuery>? entries,
    bool? connected,
    bool? paused,
  }) => DesktopLiveState(
    entries: entries ?? this.entries,
    connected: connected ?? this.connected,
    paused: paused ?? this.paused,
  );
}

class DesktopLiveNotifier extends Notifier<DesktopLiveState> {
  @override
  DesktopLiveState build() {
    final events = ref.watch(desktopEventStreamProvider);
    final subscription = events.listen(
      _onEvent,
      // The channel already reports drops as [DesktopChannelEvent]; an error here is the same
      // news, so it only has to stop the list from claiming it is live.
      onError: (_) {
        if (ref.mounted) {
          state = state.copyWith(connected: false);
        }
      },
    );
    ref.onDispose(subscription.cancel);
    return const DesktopLiveState();
  }

  void _onEvent(DesktopEvent event) {
    if (!ref.mounted) return;
    switch (event) {
      case DesktopChannelEvent(:final connected):
        state = state.copyWith(connected: connected);
      case DesktopQueryEvent(:final query):
        if (state.paused) return;
        state = state.copyWith(
          entries: [
            query,
            ...state.entries.take(desktopLiveBufferSize - 1),
          ],
        );
    }
  }

  void togglePaused() => state = state.copyWith(paused: !state.paused);

  /// Drops what has been captured; the socket keeps running unless it is paused.
  void clear() {
    if (state.entries.isEmpty) return;
    state = state.copyWith(entries: const []);
  }
}

final desktopLiveProvider =
    NotifierProvider<DesktopLiveNotifier, DesktopLiveState>(
      DesktopLiveNotifier.new,
    );

/// Whether the live list is asked to connect at all. Widget tests turn it off so a page they only
/// render for layout opens no socket.
final desktopLiveEnabledProvider = Provider<bool>((ref) => true);
