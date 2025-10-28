import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// Types de slots Mausritter
enum SlotType {
  pawMain,
  pawOff,
  body1,
  body2,
  pack1,
  pack2,
  pack3,
  pack4,
  pack5,
  pack6,
}

String slotLabel(SlotType s) {
  switch (s) {
    case SlotType.pawMain:
      return 'Patte directrice';
    case SlotType.pawOff:
      return 'Patte opposée';
    case SlotType.body1:
    case SlotType.body2:
      return 'Corps';
    case SlotType.pack1:
      return '1';
    case SlotType.pack2:
      return '2';
    case SlotType.pack3:
      return '3';
    case SlotType.pack4:
      return '4';
    case SlotType.pack5:
      return '5';
    case SlotType.pack6:
      return '6';
  }
}

/// Tag de compatibilité en BDD (items.compatible_slots TEXT[])
String slotTag(SlotType s) {
  switch (s) {
    case SlotType.pawMain:
      return 'PAW_MAIN';
    case SlotType.pawOff:
      return 'PAW_OFF';
    case SlotType.body1:
    case SlotType.body2:
      return 'BODY';
    default:
      return 'PACK';
  }
}

/// Modèle simple d’item équipé côté UI
class EquippedItem {
  final String id;
  final String name;
  final String? imageUrl;
  final int durabilityMax;
  int durabilityUsed;

  final String category; // 'WEAPON', 'ARMOR', etc.
  final String? damage; // pour WEAPON
  final int? defense;

  final bool two_handed;
  final bool two_body;
  final int packSize;

  EquippedItem({
    required this.id,
    required this.name,
    required this.durabilityMax,
    required this.durabilityUsed,
    this.imageUrl,
    required this.category,
    this.damage,
    this.defense,
    this.two_handed = false,
    this.two_body = false,
    this.packSize = 1,
  });
}

SlotType _otherPaw(SlotType s) =>
    s == SlotType.pawMain ? SlotType.pawOff : SlotType.pawMain;

bool _isPaw(SlotType s) => s == SlotType.pawMain || s == SlotType.pawOff;

SlotType _otherBody(SlotType s) =>
    s == SlotType.body1 ? SlotType.body2 : SlotType.body1;

bool _isBody(SlotType s) => s == SlotType.body1 || s == SlotType.body2;

// petit helper pour normaliser l'id en String
String? _asIdString(dynamic v) {
  if (v == null) return null;
  if (v is String) return v;
  if (v is int || v is num) return v.toString();
  return null;
}

class PlayerSheetPage extends StatefulWidget {
  final String? characterId; // ← nouveau (nullable pour compatibilité)
  const PlayerSheetPage({super.key, this.characterId});
  @override
  State<PlayerSheetPage> createState() => _PlayerSheetPageState();
}

class CharacterPickerPage extends StatefulWidget {
  const CharacterPickerPage({super.key});
  @override
  State<CharacterPickerPage> createState() => _CharacterPickerPageState();
}

class _CharacterPickerPageState extends State<CharacterPickerPage> {
  final supa = Supabase.instance.client;
  bool loading = true;
  List<Map<String, dynamic>> rows = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    final uid = supa.auth.currentUser!.id;

    // si tu veux aussi afficher des fiches partagées, ajoute un OR / view.
    final data = await supa
        .from('characters')
        .select('id,name,level,xp,updated_at,created_at')
        .eq('owner_id', uid)
        .order('updated_at', ascending: false);
    rows = (data as List).cast<Map<String, dynamic>>();
    setState(() => loading = false);
  }

  Future<void> _createNew() async {
    final uid = supa.auth.currentUser!.id;
    final ins = await supa
        .from('characters')
        .insert({
          'owner_id': uid,
          'name': 'Nouvelle fiche',
          'background': '',
          'level': 1,
          'xp': 0,
          'stats': {
            'str': {'max': 10, 'cur': 10},
            'dex': {'max': 10, 'cur': 10},
            'wil': {'max': 10, 'cur': 10},
            'hp': {'max': 4, 'cur': 4},
          },
          'slots': {},
        })
        .select('id')
        .single();

    if (!mounted) return;
    final id = ins['id'] as String;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PlayerSheetPage(characterId: id)),
    );
  }

  @override
  Widget build(BuildContext context) {
    

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        title: const Text('Choisir une fiche'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createNew,
        icon: const Icon(Icons.add),
        label: const Text('Nouvelle fiche'),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : rows.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Aucune fiche pour le moment.'),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: _createNew,
                        icon: const Icon(Icons.add),
                        label: const Text('Créer ma première fiche'),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final r = rows[i];
                    final name = (r['name'] ?? 'Sans nom') as String;
                    final level = r['level'] ?? 1;
                    final xp = r['xp'] ?? 0;
                    final up = r['updated_at'] ?? r['created_at'];
                    return ListTile(
                      leading: const Icon(Icons.pets),
                      title: Text(name),
                      subtitle: Text('Niv $level • XP $xp'),
                      trailing: up != null
                          ? Text(
                              DateTime.tryParse(up as String)
                                      ?.toLocal()
                                      .toString()
                                      .substring(0, 16) ??
                                  '',
                              style: const TextStyle(fontSize: 12),
                            )
                          : null,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                PlayerSheetPage(characterId: r['id'] as String),
                          ),
                        );
                      },
                    );
                  },
                ),
    );
  }
}

class _PlayerSheetPageState extends State<PlayerSheetPage> {
  Timer? _saveTimer;
  DateTime _lastSave = DateTime.fromMillisecondsSinceEpoch(0);
  bool isDead = false;

  void _scheduleAutoSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 450), () {
      if (!mounted) return;
      _saveCharacter();
    });
  }

  final supa = Supabase.instance.client;

  // Champs principaux
  final nameCtrl = TextEditingController();
  final backgroundCtrl = TextEditingController();
  final levelCtrl = TextEditingController(text: '1');
  final xpCtrl = TextEditingController(text: '0');

  int level = 1;
  int xp = 0;

  int strMax = 10, strCur = 10;
  int dexMax = 10, dexCur = 10;
  int wilMax = 10, wilCur = 10;
  int hpMax = 4, hpCur = 4;

  // Équipement par slot
  final Map<SlotType, EquippedItem?> equipment = {
    SlotType.pawMain: null,
    SlotType.body1: null,
    SlotType.body2: null,
    SlotType.pawOff: null,
    SlotType.pack1: null,
    SlotType.pack2: null,
    SlotType.pack3: null,
    SlotType.pack4: null,
    SlotType.pack5: null,
    SlotType.pack6: null,
  };

  String? _characterId;

  @override
  void initState() {
    super.initState();
    _loadCharacter();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    nameCtrl.dispose();
    backgroundCtrl.dispose();
    levelCtrl.dispose();
    xpCtrl.dispose();
    super.dispose();
  }

  bool _isPack(SlotType s) =>
    s == SlotType.pack1 || s == SlotType.pack2 || s == SlotType.pack3 ||
    s == SlotType.pack4 || s == SlotType.pack5 || s == SlotType.pack6;

  static const List<SlotType> _packs = [
    SlotType.pack1, SlotType.pack2, SlotType.pack3,
    SlotType.pack4, SlotType.pack5, SlotType.pack6,
  ];

int _packIndex(SlotType s) => _packs.indexOf(s); // 0..5

/// Cherche un bloc contigu de 'need' cases PACK libres.
/// Essaie d’abord depuis 'preferredStart' si fourni.
List<SlotType> _findContiguousFreePacks(int need, {SlotType? preferredStart}) {
  if (need <= 1) return [];
  final occ = _packs.map((s) => equipment[s] != null).toList(); // true=occupé

  List<SlotType> tryFrom(int start) {
    if (start + need > _packs.length) return [];
    for (var i = start; i < start + need; i++) {
      if (occ[i]) return [];
    }
    return _packs.sublist(start, start + need);
  }

  if (preferredStart != null) {
    final idx = _packIndex(preferredStart);
    final b = tryFrom(idx);
    if (b.isNotEmpty) return b;
  }
  for (var i = 0; i <= _packs.length - need; i++) {
    final b = tryFrom(i);
    if (b.isNotEmpty) return b;
  }
  return [];
}

  // ------- Sélecteur d’items filtrés par slot + déséquipement -------
  Future<void> _pickItemForSlot(SlotType slot) async {
    final tag = slotTag(slot);

    try {
      final rows = await supa
          .from('items')
          .select(
            'id,name,image_url,durability_max,compatible_slots,category,damage,defense,two_handed,two_body,pack_size',
          )
          .contains('compatible_slots', [tag])
          .order('name');

      final chosen = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => SafeArea(
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.7,
            maxChildSize: 0.95,
            minChildSize: 0.4,
            builder: (_, ctl) => Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'Choisir un item – ${slotLabel(slot)}',
                    style: Theme.of(ctx).textTheme.titleMedium,
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    controller: ctl,
                    itemCount: rows.length,
                    itemBuilder: (_, i) {
                      final r = rows[i] as Map<String, dynamic>;
                      final twoH = (r['two_handed'] as bool?) ?? false;
                      return ListTile(
                        leading: (r['image_url'] != null)
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: Image.network(
                                  r['image_url'],
                                  width: 42,
                                  height: 42,
                                  fit: BoxFit.cover,
                                ),
                              )
                            : const Icon(Icons.inventory_2_outlined),
                        title: Text(r['name'] ?? ''),
                        subtitle: Text(
                          'Durabilité ${r['durability_max'] ?? 3}'
                          '${twoH ? ' • 2 mains' : ''}',
                        ),
                        onTap: () => Navigator.pop(ctx, r),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      if (chosen == null) return;

      final equipped = EquippedItem(
        id: chosen['id'].toString(),
        name: chosen['name'] ?? 'Item',
        imageUrl: chosen['image_url'] as String?,
        durabilityMax: (chosen['durability_max'] as int?) ?? 3,
        durabilityUsed: 0,
        category: (chosen['category'] as String?) ?? 'OTHER',
        damage: chosen['damage'] as String?,
        defense: (chosen['defense'] is int)
            ? chosen['defense'] as int
            : int.tryParse('${chosen['defense'] ?? ''}'),
        two_handed: (chosen['two_handed'] as bool?) ?? false,
        two_body: (chosen['two_body'] as bool?) ?? false,
        packSize: (chosen['pack_size'] as int?)?.clamp(1, 6) ?? 1,
      );

      setState(() {
        // place dans le slot cliqué
        equipment[slot] = equipped;

        // 2 mains si slot patte
        if (_isPaw(slot) &&
            equipped.category == 'WEAPON' &&
            equipped.two_handed) {
          equipment[_otherPaw(slot)] = equipped;
        }

        // 2 corps si slot body
        if (_isBody(slot) &&
            equipped.category == 'ARMOR' &&
            equipped.two_body) {
          equipment[_otherBody(slot)] = equipped;
        }
      });

      // --- GESTION DES OBJETS VOLUMINEUX (PACK) ---
      if (_isPack(slot) && equipped.packSize > 1) {
        final needed = equipped.packSize;

        final bloc = _findContiguousFreePacks(needed, preferredStart: slot);
        if (bloc.isEmpty) {
          // Pas assez de place contiguë → annuler
          setState(() => equipment[slot] = null);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Pas assez de place : cet objet nécessite $needed cases contiguës.")),
          );
          return;
        }

        // Poser l’item dans toutes les cases du bloc
        setState(() {
          for (final s in bloc) {
            equipment[s] = equipped;
          }
        });
      }

      await _saveCharacter();

      // init durabilité pour tous les slots impliqués
      await _updateDurability(slot, 0);
      if (_isPaw(slot) && equipped.two_handed) {
        await _updateDurability(_otherPaw(slot), 0);
      }
      if (_isBody(slot) && equipped.two_body) {
        await _updateDurability(_otherBody(slot), 0);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erreur sélection item: $e')));
    }
  }

  void _unequip(SlotType slot) {
    final it = equipment[slot];

    if (it != null) {
      // Armes 2 mains : libérer l’autre patte
      if (it.category == 'WEAPON' && it.two_handed && _isPaw(slot)) {
        equipment[_otherPaw(slot)] = null;
      }
      // Armures 2 corps : libérer l’autre case corps
      if (it.category == 'ARMOR' && it.two_body && _isBody(slot)) {
        equipment[_otherBody(slot)] = null;
      }

      // GROS OBJET PACK : libérer toutes les cases PACK contenant le même item.id
      if (_isPack(slot) && it.packSize > 1) {
        for (final s in _packs) {
          if (equipment[s]?.id == it.id) {
            equipment[s] = null;
          }
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Objet retiré de toutes les cases occupées.')),
        );
      }
    }

    setState(() => equipment[slot] = null);
    _saveCharacter();
  }

  // ----------------- Chargement / Sauvegarde -----------------
  Future<void> _loadCharacter() async {
    final uid = supa.auth.currentUser!.id;

    // 1) si un id est fourni, le charger
    if (widget.characterId != null) {
      final r = await supa
          .from('characters')
          .select()
          .eq('id', widget.characterId!)
          .maybeSingle();
      if (r == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Fiche introuvable.')));
        return;
      }
      _hydrateFromRow(r); // ← factorise ci-dessous
      await _loadEquipmentFor(_characterId!);
      return;
    }

    // 2) sinon : charger la dernière fiche de ce joueur (s’il y en a)
    final r = await supa
        .from('characters')
        .select()
        .eq('owner_id', uid)
        .order('updated_at', ascending: false) // si tu as ce champ
        .limit(1)
        .maybeSingle();

    if (r == null) {
      // 3) aucune fiche → en créer une vierge
      final ins = await supa
          .from('characters')
          .insert({
            'owner_id': uid,
            'name': '',
            'background': '',
            'level': level,
            'xp': xp,
            'stats': {
              // si tu utilises le JSON "stats"
              'str': {'max': strMax, 'cur': strCur},
              'dex': {'max': dexMax, 'cur': dexCur},
              'wil': {'max': wilMax, 'cur': wilCur},
              'hp': {'max': hpMax, 'cur': hpCur},
            },
            'slots': {}, // si ta colonne NOT NULL existe
          })
          .select()
          .single();

      _characterId = ins['id'] as String;
      await _prefillFromExample();
      await _saveCharacter();
      setState(() {});
      return;
    }

    _hydrateFromRow(r);
    await _loadEquipmentFor(_characterId!);
  }

  void _hydrateFromRow(Map<String, dynamic> r) {
    _characterId = r['id'] as String;
    nameCtrl.text = (r['name'] ?? '') as String;
    backgroundCtrl.text = (r['background'] ?? '') as String;
    level = (r['level'] ?? 1) as int;
    levelCtrl.text = '$level';
    xp = (r['xp'] ?? 0) as int;
    xpCtrl.text = '$xp';

    final stats = (r['stats'] ?? {}) as Map<String, dynamic>;
    strMax = (stats['str']?['max'] ?? 10) as int;
    strCur = (stats['str']?['cur'] ?? 10) as int;
    dexMax = (stats['dex']?['max'] ?? 10) as int;
    dexCur = (stats['dex']?['cur'] ?? 10) as int;
    wilMax = (stats['wil']?['max'] ?? 10) as int;
    wilCur = (stats['wil']?['cur'] ?? 10) as int;
    hpMax = (stats['hp']?['max'] ?? 4) as int;
    hpCur = (stats['hp']?['cur'] ?? 4) as int;

    isDead = (r['is_dead'] as bool?) ?? false; // NEW

    setState(() {});
  }

  Future<void> _loadEquipmentFor(String characterId) async {
    final eq = await supa
        .from('character_items')
        .select(
          'slot,item_id,durability_used, items(name,image_url,durability_max,category,damage,defense,two_handed, two_body, pack_size)',
        )
        .eq('character_id', characterId);

    // on vide d’abord (au cas où)
    for (final k in equipment.keys.toList()) {
      equipment[k] = null;
    }

    for (final e in eq) {
      final item = e['items'] as Map<String, dynamic>;
      final slot = _fromSlotString(e['slot'] as String);
      final itemId = e['item_id'].toString();

      final equipped = EquippedItem(
        id: itemId,
        name: (item['name'] ?? '') as String,
        imageUrl: item['image_url'] as String?,
        durabilityMax: (item['durability_max'] as int?) ?? 3,
        durabilityUsed: (e['durability_used'] as int?) ?? 0,
        category: (item['category'] as String?) ?? 'OTHER',
        damage: item['damage'] as String?,
        defense: (item['defense'] is int)
            ? item['defense'] as int
            : int.tryParse('${item['defense'] ?? ''}'),
        two_handed: (item['two_handed'] as bool?) ?? false,
        two_body: (item['two_body'] as bool?) ?? false,
        packSize: (item['pack_size'] as int?)?.clamp(1, 6) ?? 1,
      );

      equipment[slot] = equipped;

      if (_isPaw(slot) && equipped.two_handed) {
        equipment[_otherPaw(slot)] = equipped; // déjà présent
      }
      if (_isBody(slot) && equipped.two_body) {
        equipment[_otherBody(slot)] = equipped; // ← AJOUT
      }
    }

    setState(() {});
  }

  bool _isLoading = false;

  Future<String?> _ensureCharacterId() async {
    if (_characterId != null) return _characterId;
    final uid = supa.auth.currentUser?.id;
    if (uid == null) return null;

    _isLoading = true;
    setState(() {});

    try {
      final r = await supa
          .from('characters')
          .select()
          .eq('owner_id', uid)
          .maybeSingle();

      if (r != null) {
        _characterId = r['id'] as String;
        return _characterId;
      }

      final ins = await supa
          .from('characters')
          .insert({
            'owner_id': uid,
            'name': '',
            'background': '',
            'level': level,
            'xp': xp,
            'str_cur': strCur,
            'str_max': strMax,
            'dex_cur': dexCur,
            'dex_max': dexMax,
            'wil_cur': wilCur,
            'wil_max': wilMax,
            'hp_cur': hpCur,
            'hp_max': hpMax,
          })
          .select()
          .single();

      _characterId = ins['id'] as String;
      return _characterId;
    } finally {
      _isLoading = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _saveCharacter({
    bool force = false,
    bool showFeedback = false,
  }) async {
    if (!mounted) return;

    _saveTimer?.cancel();
    final now = DateTime.now();
    if (!force &&
        now.difference(_lastSave) < const Duration(milliseconds: 400)) {
      return;
    }
    _lastSave = now;

    // 🔒 assure l’existence du perso
    final id = await _ensureCharacterId();
    if (id == null) {
      if (showFeedback) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Impossible d’identifier l’utilisateur.'),
          ),
        );
      }
      return;
    }

    try {
      level = int.tryParse(levelCtrl.text.trim()) ?? level;
      xp = int.tryParse(xpCtrl.text.trim()) ?? xp;

      await supa
          .from('characters')
          .update({
            'name': nameCtrl.text.trim(),
            'background': backgroundCtrl.text.trim(),
            'level': level,
            'xp': xp,
            'str_max': strMax,
            'str_cur': strCur,
            'dex_max': dexMax,
            'dex_cur': dexCur,
            'wil_max': wilMax,
            'wil_cur': wilCur,
            'hp_max': hpMax,
            'hp_cur': hpCur,
          })
          .eq('id', id);

      for (final entry in equipment.entries) {
        final slotDb = _slotToDb(entry.key);
        final it = entry.value;
        if (it == null) {
          await supa.from('character_items').delete().match({
            'character_id': id,
            'slot': slotDb,
          });
        } else {
          await supa.from('character_items').upsert({
            'character_id': id,
            'slot': slotDb,
            'item_id': it.id,
            'durability_used': it.durabilityUsed,
          }, onConflict: 'character_id,slot');
        }
      }

      if (showFeedback) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Fiche enregistrée ✅')));
      }
    } catch (e) {
      if (showFeedback) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur à l’enregistrement : $e')),
        );
      }
    }
  }

  Future<void> _killMouse() async {
    if (_characterId == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tuer la souris ?'),
        content: const Text(
          'Cette action marquera définitivement cette souris comme morte.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Oui, la souris est morte'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await supa
          .from('characters')
          .update({
            'is_dead': true,
            'death_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', _characterId!);

      setState(() => isDead = true);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('La souris est maintenant marquée comme morte.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erreur: $e')));
      }
    }
  }

  // ----------------- Pré-remplissage façon photo -----------------
  Future<void> _prefillFromExample() async {
    Future<Map<String, dynamic>?> _findFirst(
      List<String> patterns,
      SlotType slot,
    ) async {
      for (final p in patterns) {
        final rows = await supa
            .from('items')
            .select(
              'id,name,image_url,durability_max,compatible_slots,category,damage,defense',
            )
            .ilike('name', p)
            .contains('compatible_slots', [slotTag(slot)])
            .limit(1);
        if (rows.isNotEmpty) return rows.first as Map<String, dynamic>;
      }
      return null;
    }

    void _equip(SlotType slot, Map<String, dynamic> r) {
      equipment[slot] = EquippedItem(
        id: r['id'].toString(),
        name: r['name'] as String,
        imageUrl: r['image_url'] as String?,
        durabilityMax: (r['durability_max'] as int?) ?? 3,
        durabilityUsed: 0,
        category: (r['category'] as String?) ?? 'OTHER',
        damage: r['damage'] as String?,
        defense: (r['defense'] is int)
            ? r['defense'] as int
            : int.tryParse('${r['defense'] ?? ''}'),
      );
    }

    final sling = await _findFirst(const [
      '%fronde%',
      '%sling%',
    ], SlotType.pawMain);
    if (sling != null) _equip(SlotType.pawMain, sling);

    final ammo = await _findFirst(const [
      '%munition%',
      '%stones%',
      '%arrows%',
    ], SlotType.body1);
    if (ammo != null) _equip(SlotType.body1, ammo);

    final lantern = await _findFirst(const [
      '%lanterne%',
      '%lantern%',
    ], SlotType.pack1);
    if (lantern != null) _equip(SlotType.pack1, lantern);

    final torch = await _findFirst(const [
      '%torche%',
      '%torch%',
    ], SlotType.pack2);
    if (torch != null) _equip(SlotType.pack2, torch);

    final rations = await _findFirst(const [
      '%ration%',
      '%rations%',
    ], SlotType.pack3);
    if (rations != null) _equip(SlotType.pack3, rations);
  }

  Future<void> _updateDurability(SlotType slot, int newUsed) async {
    final id = _characterId;
    final it = equipment[slot];
    if (id == null || it == null) return;

    // 🚫 On ignore totalement la durabilité pour les armures
    if (it.category == 'ARMOR') return;

    final slotDb = _slotToDb(slot);
    try {
      it.durabilityUsed = newUsed;

      await supa.from('character_items').upsert({
        'character_id': id,
        'slot': slotDb,
        'item_id': it.id,
        'durability_used': newUsed,
      }, onConflict: 'character_id,slot');

      // Miroir 2 mains (armes)
      if (_isPaw(slot) && it.two_handed) {
        final other = _otherPaw(slot);
        await supa.from('character_items').upsert({
          'character_id': id,
          'slot': _slotToDb(other),
          'item_id': it.id,
          'durability_used': newUsed,
        }, onConflict: 'character_id,slot');
      }
      // PACK multi-cases : refléter la même durabilité sur toutes les cases occupées
      if (_isPack(slot) && it.packSize > 1) {
        for (final s in _packs) {
          if (equipment[s]?.id == it.id) {
            await supa.from('character_items').upsert({
              'character_id': id,
              'slot': _slotToDb(s),
              'item_id': it.id,
              'durability_used': newUsed,
            }, onConflict: 'character_id,slot');
          }
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Échec sauvegarde durabilité: $e')),
      );
    }
  }

  // ----------------- Helpers mapping slots -----------------
  SlotType _fromSlotString(String s) {
    switch (s) {
      case 'PAW_MAIN':
        return SlotType.pawMain;
      case 'PAW_OFF':
        return SlotType.pawOff;
      case 'BODY_1':
        return SlotType.body1;
      case 'BODY_2':
        return SlotType.body2;
      case 'PACK_1':
        return SlotType.pack1;
      case 'PACK_2':
        return SlotType.pack2;
      case 'PACK_3':
        return SlotType.pack3;
      case 'PACK_4':
        return SlotType.pack4;
      case 'PACK_5':
        return SlotType.pack5;
      case 'PACK_6':
        return SlotType.pack6;
      default:
        return SlotType.pack1;
    }
  }

  String _slotToDb(SlotType s) {
    switch (s) {
      case SlotType.pawMain:
        return 'PAW_MAIN';
      case SlotType.pawOff:
        return 'PAW_OFF';
      case SlotType.body1:
        return 'BODY_1';
      case SlotType.body2:
        return 'BODY_2';
      case SlotType.pack1:
        return 'PACK_1';
      case SlotType.pack2:
        return 'PACK_2';
      case SlotType.pack3:
        return 'PACK_3';
      case SlotType.pack4:
        return 'PACK_4';
      case SlotType.pack5:
        return 'PACK_5';
      case SlotType.pack6:
        return 'PACK_6';
    }
  }

  // ------------------------- UI -------------------------
  @override
Widget build(BuildContext context) {
  final warmWhite = const Color(0xFFFAF8F3); // blanc légèrement chaleureux
  final ink = const Color(0xFF2C2A29);
  final base = Theme.of(context);

  // Police manuscrite sur tout le textTheme
  final handTextTheme = GoogleFonts.patrickHandTextTheme(base.textTheme)
      .apply(bodyColor: ink, displayColor: ink);

  const double designW = 390;
  const double designH = 650;

  return Theme(
    data: base.copyWith(
      scaffoldBackgroundColor: Colors.white,
      textTheme: handTextTheme,
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: Colors.white,
        foregroundColor: ink,
        titleTextStyle: handTextTheme.titleLarge, // police manuscrite pour le titre
      ),
    ),
    child: Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: const Text('Fiche de personnage'),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: 'Enregistrer',
            onPressed: (_isLoading)
                ? null
                : () => _saveCharacter(force: true, showFeedback: true),
            icon: const Icon(Icons.save),
          ),
          const SizedBox(width: 4),
          TextButton(
            onPressed: isDead ? null : _killMouse,
            style: TextButton.styleFrom(
              foregroundColor: isDead ? Colors.grey : Colors.red.shade800,
            ),
            child: const Text(
              "TUER !",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (ctx, c) {
            final s1 = c.maxWidth / designW;
            final s2 = c.maxHeight / designH;
            final scale = (s1 < s2 ? s1 : s2) * 0.98;

            return Center(
              child: Transform.scale(
                scale: scale,
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: designW,
                  height: designH,
                  child: _sheetBody(),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
}

  Widget _slotCell(SlotType s, double height) {
    return SizedBox(
      height: height,
      child: _slotCard(s, height: height),
    );
  }

  // Contenu compact : Name/XP -> Caractéristiques -> Inventaire
  Widget _sheetBody() {
    return LayoutBuilder(
      builder: (ctx, cons) {
        const gap = 6.0;
        final w = cons.maxWidth;
        final h = cons.maxHeight;

        final leftW = w * 0.30;
        final midW = w * 0.30;
        final rightW = w - leftW - midW - gap * 2;

        final topHeight = (h * 0.60).clamp(360.0, h - 120.0);
        final cell = (topHeight - gap) / 2;

        const rightTopMargin = 0.0;
        final double rightBoxW = rightW.clamp(0, 220.0);

        final packHeight = h - topHeight - gap;

        return Column(
          children: [
            SizedBox(
              height: topHeight,
              child: Row(
                children: [
                  // Colonne gauche : Pattes
                  SizedBox(
                    width: leftW,
                    child: Column(
                      children: [
                        _slotCell(SlotType.pawMain, cell),
                        const SizedBox(height: gap),
                        _slotCell(SlotType.pawOff, cell),
                      ],
                    ),
                  ),
                  const SizedBox(width: gap),

                  // Colonne milieu : Corps
                  SizedBox(
                    width: midW,
                    child: Column(
                      children: [
                        _slotCell(SlotType.body1, cell),
                        const SizedBox(height: gap),
                        _slotCell(SlotType.body2, cell),
                      ],
                    ),
                  ),
                  const SizedBox(width: gap),

                  // Colonne droite : Nom/XP + Caractéristiques
                  SizedBox(
                    width: rightW,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 2, bottom: 2),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: rightTopMargin),
                          Padding(
                            padding: const EdgeInsets.only(right: 4.0),
                            child: Align(
                              alignment: Alignment.topLeft,
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: rightBoxW,
                                ),
                                child: _nameRightBox(maxWidth: rightBoxW),
                              ),
                            ),
                          ),
                          const SizedBox(height: gap),
                          Expanded(
                            child: Align(
                              alignment: Alignment.topLeft,
                              child: SizedBox(
                                width: rightBoxW,
                                child: _statsRightBoxScrollable(
                                  maxWidth: rightBoxW,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: gap),

            // Pack (3 x 2)
            SizedBox(
              height: packHeight,
              child: GridView.builder(
                padding: EdgeInsets.zero,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: gap,
                  mainAxisSpacing: gap,
                  childAspectRatio:
                      (w - gap * 2) / 3 / ((packHeight - gap) / 2),
                ),
                itemCount: 6,
                itemBuilder: (_, i) {
                  const order = [
                    SlotType.pack1,
                    SlotType.pack2,
                    SlotType.pack3,
                    SlotType.pack4,
                    SlotType.pack5,
                    SlotType.pack6,
                  ];
                  return _slotCard(order[i], height: double.infinity);
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _statsRightBoxScrollable({required double maxWidth}) {
    return LayoutBuilder(
      builder: (ctx, cons) => SingleChildScrollView(
        padding: EdgeInsets.zero,
        physics: const BouncingScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: cons.maxHeight,
            maxWidth: maxWidth, // même largeur que le cadre NOM
          ),
          child: _statsRightBox(), // version sans param
        ),
      ),
    );
  }

  // --------- Widgets de base ---------
  Widget _frame({required String label, required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black54, width: 1.3),
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.fromLTRB(6, 2, 6, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w400, fontSize: 11),
          ),
          const SizedBox(height: 2),
          child,
        ],
      ),
    );
  }

  // Cadre Name + Level + XP (compact)
  Widget _nameRightBox({double maxWidth = 170}) {
    const labelStyle = TextStyle(fontSize: 11);
    const fieldH = 26.0;
    const lvlW = 25.0;
    const xpW = 40.0;

    InputDecoration _deco(String hint) => InputDecoration(
          isDense: true,
          hintText: hint,
          border: const OutlineInputBorder(),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        );

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Padding(
        padding: const EdgeInsets.only(right: 0),
        child: _frame(
          label: 'Nom :',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                style: TextStyle(
                  fontSize: 11,
                  decoration: isDead
                      ? TextDecoration.lineThrough
                      : TextDecoration.none,
                ),
                decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: 'Nom',
                  contentPadding: EdgeInsets.zero,
                ),
                onChanged: (_) => _scheduleAutoSave(),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Niv :', style: labelStyle),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: lvlW,
                    height: fieldH,
                    child: TextField(
                      controller: levelCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      textAlign: TextAlign.center,
                      style: labelStyle,
                      decoration: _deco('1'),
                      onChanged: (_) {
                        level = int.tryParse(levelCtrl.text) ?? level;
                        _scheduleAutoSave();
                      },
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Text('XP :', style: labelStyle),
                  const SizedBox(width: 4),
                  SizedBox(
                    width: xpW,
                    height: fieldH,
                    child: TextField(
                      controller: xpCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      textAlign: TextAlign.center,
                      style: labelStyle,
                      decoration: _deco('0'),
                      onChanged: (_) {
                        xp = int.tryParse(xpCtrl.text) ?? xp;
                        _scheduleAutoSave();
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Cadre Caractéristiques
  Widget _statsRightBox() {
    const labelStyle = TextStyle(fontSize: 11);
    const fieldH = 26.0;
    const fieldW = 34.0;

    String _digits(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

    InputDecoration _deco(String hint) => InputDecoration(
          isDense: true,
          hintText: hint,
          border: const OutlineInputBorder(),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        );

    Widget line(
      String label,
      int maxVal,
      int curVal,
      void Function(int, int) onChange,
    ) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 36, child: Text(label, style: labelStyle)),
            const SizedBox(width: 6),
            SizedBox(
              width: fieldW,
              height: fieldH,
              child: TextField(
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: labelStyle,
                decoration: _deco('$maxVal'),
                onChanged: (v) {
                  onChange(int.tryParse(_digits(v)) ?? maxVal, curVal);
                  _scheduleAutoSave();
                },
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text('/', style: labelStyle),
            ),
            SizedBox(
              width: fieldW,
              height: fieldH,
              child: TextField(
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: labelStyle,
                decoration: _deco('$curVal'),
                onChanged: (v) {
                  onChange(maxVal, int.tryParse(_digits(v)) ?? curVal);
                  _scheduleAutoSave();
                },
              ),
            ),
          ],
        ),
      );
    }

    return _frame(
      label: '',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          line('FOR :', strMax, strCur, (m, c) {
            setState(() {
              strMax = m;
              strCur = c;
            });
          }),
          line('DEX :', dexMax, dexCur, (m, c) {
            setState(() {
              dexMax = m;
              dexCur = c;
            });
          }),
          line('VOL :', wilMax, wilCur, (m, c) {
            setState(() {
              wilMax = m;
              wilCur = c;
            });
          }),
          line('PV  :', hpMax, hpCur, (m, c) {
            setState(() {
              hpMax = m;
              hpCur = c;
            });
          }),
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Pépins : ', style: labelStyle),
              SizedBox(
                width: 48,
                height: fieldH,
                child: TextField(
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: labelStyle,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) {
                    _scheduleAutoSave();
                  },
                ),
              ),
              const Text(' / 250', style: labelStyle),
            ],
          ),
          const SizedBox(height: 3),
          const Text('Passé :', style: labelStyle),
          SizedBox(
            height: fieldH,
            child: TextField(
              controller: backgroundCtrl,
              style: labelStyle,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (_) {
                _scheduleAutoSave();
              },
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- Slots & Pack ----------------
  Widget _slotCard(SlotType slot, {double? height}) {
    final it = equipment[slot];

    return GestureDetector(
      onTap: () => _pickItemForSlot(slot),
      onLongPress: () => _unequip(slot),
      child: Container(
        height: height ?? 120,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.black54, width: 1.3),
          borderRadius: BorderRadius.circular(10),
          color: Colors.white.withOpacity(0.6),
        ),
        clipBehavior: Clip.antiAlias, // évite tout overflow
        child: it == null
            ? Center(
                child: Text(
                  slotLabel(slot),
                  style: const TextStyle(color: Colors.black87),
                ),
              )
            : Stack(
                fit: StackFit.expand,
                children: [
                  // --- image de fond ---
                  if (it.imageUrl != null)
                    Image.network(it.imageUrl!, fit: BoxFit.cover)
                  else
                    const Center(
                      child: Icon(Icons.inventory_2_outlined, size: 42),
                    ),

                  // --- voile pour lisibilité (haut et bas)
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withOpacity(0.35),
                            Colors.transparent,
                            Colors.black.withOpacity(0.45),
                          ],
                          stops: const [0.0, 0.55, 1.0],
                        ),
                      ),
                    ),
                  ),

                  // --- titre centré en haut ---
                  Positioned(
                    left: 6,
                    right: 6,
                    top: 6,
                    child: Text(
                      it.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
                      ),
                    ),
                  ),

                  // --- badge dégâts/défense en haut-droite ---
                  Positioned(top: 6, right: 6, child: _itemBadgeFor(it)),

                  // --- points de durabilité centrés en bas ---
                  if (it.category != 'ARMOR') // ← ne pas afficher pour ARMOR
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 6,
                      child: Center(
                        child: _durabilityDotsForSlot(
                          slot,
                          max: it.durabilityMax,
                          used: it.durabilityUsed,
                          color: Colors.white,
                          size: 16,
                          spacing: 6,
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  Widget _itemBadgeFor(EquippedItem it) {
    String? text;
    if (it.category == 'WEAPON' && (it.damage?.isNotEmpty ?? false)) {
      text = it.damage; // ex: d6, d6/d8, d10…
    } else if (it.category == 'ARMOR' && it.defense != null) {
      text = '${it.defense} DEF';
    }
    if (text == null && !it.two_handed) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (text != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.92),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.black87, width: 1.2),
            ),
            child: Text(
              text,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ),
        if (it.two_handed) ...[
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.92),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.black87, width: 1.2),
            ),
            child: const Text(
              '2 mains',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ],
    );
  }

  Widget _durabilityDotsForSlot(
    SlotType slot, {
    required int max,
    required int used,
    Color color = Colors.black87,
    double size = 14,
    double spacing = 4,
  }) {
    final total = max.clamp(1, 6);
    return Row(
      mainAxisSize: MainAxisSize.min, // ← centrage serré
      children: List.generate(total, (i) {
        final filled = i < used;
        return GestureDetector(
          onTap: () async {
            final newUsed = (i + 1 == used) ? i : i + 1;
            setState(
              () => equipment[slot]!.durabilityUsed = newUsed,
            ); // UI optimiste
            await _updateDurability(slot, newUsed); // save DB
          },
          child: Padding(
            padding: EdgeInsets.only(right: i == total - 1 ? 0 : spacing),
            child: Icon(
              filled ? Icons.circle : Icons.circle_outlined,
              size: size,
              color: color,
            ),
          ),
        );
      }),
    );
  }
}
