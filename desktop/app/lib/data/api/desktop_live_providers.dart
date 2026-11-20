library;

import 'dart:async';

import 'package:diting_desktop/data/api/desktop_api_providers.dart';
import 'package:diting_desktop/data/api/desktop_event_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const int desktopLiveBufferSize = 500;

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

  final List<DesktopLiveQuery> entries;

  final bool connected;

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

  void clear() {
    if (state.entries.isEmpty) return;
    state = state.copyWith(entries: const []);
  }
}

final desktopLiveProvider =
    NotifierProvider<DesktopLiveNotifier, DesktopLiveState>(
      DesktopLiveNotifier.new,
    );

final desktopLiveEnabledProvider = Provider<bool>((ref) => true);
