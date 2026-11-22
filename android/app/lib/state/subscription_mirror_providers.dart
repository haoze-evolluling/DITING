part of 'subscription_providers.dart';


final mirrorTemplateRepositoryProvider =
    FutureProvider<MirrorTemplateRepository?>((ref) async {
      final db = await ref.watch(subscriptionDatabaseProvider.future);
      if (db == null) return null;
      return MirrorTemplateRepository(
        db,
        onChanged: () => ref.read(subscriptionRevisionProvider.notifier).bump(),
      );
    });

final mirrorTemplatesProvider = FutureProvider<List<MirrorTemplateRecord>>((
  ref,
) async {
  ref.watch(subscriptionRevisionProvider);
  final repository = await ref.watch(mirrorTemplateRepositoryProvider.future);
  return repository == null ? const <MirrorTemplateRecord>[] : repository.all();
});

class MirrorTemplateActions {
  MirrorTemplateActions(this._ref);

  final Ref _ref;

  Future<MirrorTemplateRepository?> _repository() =>
      _ref.read(mirrorTemplateRepositoryProvider.future);

  Future<int?> create({required String name, required String template}) async =>
      (await _repository())?.insert(name: name, template: template);

  Future<bool> update({
    required int id,
    required String name,
    required String template,
  }) async =>
      await (await _repository())?.update(
        id: id,
        name: name,
        template: template,
      ) ??
      false;

  Future<void> remove(int id) async => (await _repository())?.delete(id);
}

final mirrorTemplateActionsProvider = Provider<MirrorTemplateActions>(
  MirrorTemplateActions.new,
);
