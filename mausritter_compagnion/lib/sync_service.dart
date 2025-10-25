class SyncService {
  final supa = Supabase.instance.client;
  final Isar isar;

  SyncService(this.isar);

  Future<void> pullAll() async {
    // 1) Pull items
    final items = await supa.from('items').select('*');
    await isar.writeTxn(() async {
      for (final it in items) {
        final obj = IsarItem()
          ..remoteId = it['id'] as int
          ..name = it['name'] as String
          ..imageUrl = it['image_url'] as String?
          ..durabilityMax = (it['durability_max'] as int?) ?? 3
          ..compatibleSlots = (it['compatible_slots'] as List?)?.cast<String>() ?? []
          ..category = it['category'] as String
          ..updatedAt = DateTime.now();
        await isar.isarItems.put(obj);
      }
    });

    // 2) Pull characters + equipment du user courant...
  }

  // push des modifications locales marquées “dirty” quand réseau dispo
}
