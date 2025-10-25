import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import 'package:flutter/services.dart';

/// Types de slots Mausritter
enum SlotType { pawMain, pawOff, body1, body2, pack1, pack2, pack3, pack4, pack5, pack6 }

String slotLabel(SlotType s) {
  switch (s) {
    case SlotType.pawMain: return 'Main paw';
    case SlotType.pawOff:  return 'Off paw';
    case SlotType.body1:
    case SlotType.body2:   return 'Body';
    case SlotType.pack1:   return '1';
    case SlotType.pack2:   return '2';
    case SlotType.pack3:   return '3';
    case SlotType.pack4:   return '4';
    case SlotType.pack5:   return '5';
    case SlotType.pack6:   return '6';
  }
}

/// Tag de compatibilité en BDD (items.compatible_slots TEXT[])
String slotTag(SlotType s) {
  switch (s) {
    case SlotType.pawMain: return 'PAW_MAIN';
    case SlotType.pawOff:  return 'PAW_OFF';
    case SlotType.body1:
    case SlotType.body2:   return 'BODY';
    default:               return 'PACK';
  }
}

/// Modèle simple d’item équipé côté UI
class EquippedItem {
  final int id;
  final String name;
  final String? imageUrl;
  final int durabilityMax;
  int durabilityUsed;
  EquippedItem({
    required this.id,
    required this.name,
    required this.durabilityMax,
    required this.durabilityUsed,
    this.imageUrl,
  });
}

class PlayerSheetPage extends StatefulWidget {
  const PlayerSheetPage({super.key});
  @override
  State<PlayerSheetPage> createState() => _PlayerSheetPageState();
}

class _PlayerSheetPageState extends State<PlayerSheetPage> {
  Timer? _saveTimer;
  DateTime _lastSave = DateTime.fromMillisecondsSinceEpoch(0);

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
  int hpMax = 4,  hpCur = 4;

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

  // ------- Sélecteur d’items filtrés par slot + déséquipement -------
  Future<void> _pickItemForSlot(SlotType slot) async {
    final tag = slotTag(slot);
    try {
      final rows = await supa
          .from('items')
          .select('id,name,image_url,durability_max,compatible_slots')
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
                  child: Text('Choisir un item – ${slotLabel(slot)}',
                      style: Theme.of(ctx).textTheme.titleMedium),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    controller: ctl,
                    itemCount: rows.length,
                    itemBuilder: (_, i) {
                      final r = rows[i] as Map<String, dynamic>;
                      return ListTile(
                        leading: (r['image_url'] != null)
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: Image.network(
                                  r['image_url'],
                                  width: 42, height: 42, fit: BoxFit.cover,
                                ),
                              )
                            : const Icon(Icons.inventory_2_outlined),
                        title: Text(r['name'] ?? ''),
                        subtitle: Text('Durabilité ${r['durability_max'] ?? 3}'),
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

      setState(() {
        equipment[slot] = EquippedItem(
          id: chosen['id'] as int,
          name: chosen['name'] ?? 'Item',
          imageUrl: chosen['image_url'] as String?,
          durabilityMax: (chosen['durability_max'] as int?) ?? 3,
          durabilityUsed: 0,
        );
      });
      await _saveCharacter();
      await _updateDurability(slot, 0);

    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur sélection item: $e')),
      );
    }
  }

  void _unequip(SlotType slot) {
    setState(() => equipment[slot] = null);
    _saveCharacter();
  }

  // ----------------- Chargement / Sauvegarde -----------------
  Future<void> _loadCharacter() async {
    final uid = supa.auth.currentUser!.id;

    final r = await supa.from('characters')
        .select()
        .eq('owner_id', uid)
        .maybeSingle();

    if (r == null) {
      final ins = await supa.from('characters').insert({
        'owner_id': uid,
        'name': '',
        'background': '',
        'level': level,
        'xp': xp,
        'str_cur': strCur, 'str_max': strMax,
        'dex_cur': dexCur,'dex_max': dexMax,
        'wil_cur': wilCur,'wil_max': wilMax,
        'hp_cur':  hpCur,'hp_max':  hpMax,
      }).select().single();
      _characterId = ins['id'] as String;

      await _prefillFromExample();
      await _saveCharacter();
      setState(() {});
      return;
    }

    _characterId = r['id'] as String;
    setState(() {
      nameCtrl.text       = (r['name'] ?? '') as String;
      backgroundCtrl.text = (r['background'] ?? '') as String;

      level = (r['level'] ?? 1) as int;
      xp    = (r['xp'] ?? 0) as int;
      levelCtrl.text = '$level';
      xpCtrl.text = '$xp';

      strMax = (r['str_max'] ?? 10) as int; strCur = (r['str_cur'] ?? 10) as int;
      dexMax = (r['dex_max'] ?? 10) as int; dexCur = (r['dex_cur'] ?? 10) as int;
      wilMax = (r['wil_max'] ?? 10) as int; wilCur = (r['wil_cur'] ?? 10) as int;
      hpMax  = (r['hp_max']  ??  4) as int; hpCur  = (r['hp_cur']  ??  4) as int;
    });

    final id = _characterId;
    if (id != null) {
      final eq = await supa.from('character_equipment')
          .select('slot,item_id,durability_used, items(name,image_url,durability_max)')
          .eq('character_id', id);

      for (final e in eq) {
        final item = e['items'] as Map<String, dynamic>;
        equipment[_fromSlotString(e['slot'] as String)] = EquippedItem(
          id: e['item_id'] as int,
          name: item['name'] as String,
          imageUrl: item['image_url'] as String?,
          durabilityMax: (item['durability_max'] as int?) ?? 3,
          durabilityUsed: (e['durability_used'] as int?) ?? 0,
        );
      }
      setState(() {});
    }
  }

  Future<void> _saveCharacter() async {
    final now = DateTime.now();
    if (now.difference(_lastSave) < const Duration(milliseconds: 400)) return;
    _lastSave = now;

    final id = _characterId;
    if (id == null) return;

    level = int.tryParse(levelCtrl.text.trim()) ?? level;
    xp    = int.tryParse(xpCtrl.text.trim()) ?? xp;

    await supa.from('characters').update({
      'name': nameCtrl.text.trim(),
      'background': backgroundCtrl.text.trim(),
      'level': level,
      'xp': xp,
      'str_max': strMax, 'str_cur': strCur,
      'dex_max': dexMax, 'dex_cur': dexCur,
      'wil_max': wilMax, 'wil_cur': wilCur,
      'hp_max':  hpMax,  'hp_cur':  hpCur,
    }).eq('id', id);

    for (final entry in equipment.entries) {
      final slotDb = _slotToDb(entry.key);
      final it = entry.value;
      if (it == null) {
        await supa.from('character_equipment')
            .delete()
            .match({'character_id': id, 'slot': slotDb});
      } else {
        await supa.from('character_equipment').upsert({
          'character_id': id,
          'slot': slotDb,
          'item_id': it.id,
          'durability_used': it.durabilityUsed,
        }, onConflict: 'character_id,slot');
      }
    }
  }

  // ----------------- Pré-remplissage façon photo -----------------
  Future<void> _prefillFromExample() async {
    Future<Map<String, dynamic>?> _findFirst(List<String> patterns, SlotType slot) async {
      for (final p in patterns) {
        final rows = await supa.from('items')
            .select('id,name,image_url,durability_max,compatible_slots')
            .ilike('name', p)
            .contains('compatible_slots', [slotTag(slot)])
            .limit(1);
        if (rows.isNotEmpty) return rows.first as Map<String, dynamic>;
      }
      return null;
    }

    void _equip(SlotType slot, Map<String, dynamic> r) {
      equipment[slot] = EquippedItem(
        id: r['id'] as int,
        name: r['name'] as String,
        imageUrl: r['image_url'] as String?,
        durabilityMax: (r['durability_max'] as int?) ?? 3,
        durabilityUsed: 0,
      );
    }

    final sling = await _findFirst(const ['%fronde%', '%sling%'], SlotType.pawMain);
    if (sling != null) _equip(SlotType.pawMain, sling);

    final ammo = await _findFirst(const ['%munition%', '%stones%', '%arrows%'], SlotType.body1);
    if (ammo != null) _equip(SlotType.body1, ammo);

    final lantern = await _findFirst(const ['%lanterne%', '%lantern%'], SlotType.pack1);
    if (lantern != null) _equip(SlotType.pack1, lantern);

    final torch = await _findFirst(const ['%torche%', '%torch%'], SlotType.pack2);
    if (torch != null) _equip(SlotType.pack2, torch);

    final rations = await _findFirst(const ['%ration%','%rations%'], SlotType.pack3);
    if (rations != null) _equip(SlotType.pack3, rations);
  }

  Future<void> _updateDurability(SlotType slot, int newUsed) async {
    final id = _characterId;
    final it = equipment[slot];
    if (id == null || it == null) return;

    final slotDb = _slotToDb(slot);
    try {
      await supa.from('character_equipment').upsert({
        'character_id': id,
        'slot': slotDb,
        'item_id': it.id,
        'durability_used': newUsed,
      }, onConflict: 'character_id,slot');
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
      case 'PAW_MAIN': return SlotType.pawMain;
      case 'PAW_OFF' : return SlotType.pawOff;
      case 'BODY_1'  : return SlotType.body1;
      case 'BODY_2'  : return SlotType.body2;
      case 'PACK_1'  : return SlotType.pack1;
      case 'PACK_2'  : return SlotType.pack2;
      case 'PACK_3'  : return SlotType.pack3;
      case 'PACK_4'  : return SlotType.pack4;
      case 'PACK_5'  : return SlotType.pack5;
      case 'PACK_6'  : return SlotType.pack6;
      default:        return SlotType.pack1;
    }
  }

  String _slotToDb(SlotType s) {
    switch (s) {
      case SlotType.pawMain: return 'PAW_MAIN';
      case SlotType.pawOff:  return 'PAW_OFF';
      case SlotType.body1:   return 'BODY_1';
      case SlotType.body2:   return 'BODY_2';
      case SlotType.pack1:   return 'PACK_1';
      case SlotType.pack2:   return 'PACK_2';
      case SlotType.pack3:   return 'PACK_3';
      case SlotType.pack4:   return 'PACK_4';
      case SlotType.pack5:   return 'PACK_5';
      case SlotType.pack6:   return 'PACK_6';
    }
  }

  // ------------------------- UI : tout tient sur l’écran -------------------------
  @override
  Widget build(BuildContext context) {
    final parchment = const Color(0xFFF6F1E7);
    final ink = const Color(0xFF2C2A29);

    const double designW = 390;
    const double designH = 600;

    return Theme(
      data: Theme.of(context).copyWith(
        scaffoldBackgroundColor: parchment,
        textTheme: Theme.of(context).textTheme.apply(bodyColor: ink, displayColor: ink),
        cardTheme: const CardThemeData(),
      ),
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
          backgroundColor: parchment,
          foregroundColor: ink,
          title: const Text('Fiche de personnage'),
          centerTitle: false,
          actions: [
            IconButton(
              tooltip: 'Enregistrer',
              onPressed: _saveCharacter,
              icon: const Icon(Icons.save),
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
    return SizedBox(height: height, child: _slotCard(s, height: height));
  }

  // Contenu compact : Name/XP -> Caractéristiques -> Inventaire
  Widget _sheetBody() {
    return LayoutBuilder(
      builder: (ctx, cons) {
        const gap = 6.0;
        final w = cons.maxWidth;
        final h = cons.maxHeight;

        final leftW   = w * 0.30;
        final midW    = w * 0.30;
        final rightW  = w - leftW - midW - gap * 2;

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
                                constraints: BoxConstraints(maxWidth: rightBoxW),
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
                                child: _statsRightBoxScrollable(maxWidth: rightBoxW),
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
                  childAspectRatio: (w - gap * 2) / 3 / ((packHeight - gap) / 2),
                ),
                itemCount: 6,
                itemBuilder: (_, i) {
                  const order = [
                    SlotType.pack1, SlotType.pack2, SlotType.pack3,
                    SlotType.pack4, SlotType.pack5, SlotType.pack6,
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
          Text(label, style: const TextStyle(fontWeight: FontWeight.w400, fontSize: 11)),
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
    const lvlW   = 25.0;
    const xpW    = 40.0;

    InputDecoration _deco(String hint) => InputDecoration(
      isDense: true,
      hintText: hint,
      border: const OutlineInputBorder(),
      contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
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
                style: labelStyle,
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
                    width: lvlW, height: fieldH,
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
                    width: xpW, height: fieldH,
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
    );

    Widget line(String label, int maxVal, int curVal, void Function(int,int) onChange) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 36, child: Text(label, style: labelStyle)),
            const SizedBox(width: 6),
            SizedBox(
              width: fieldW, height: fieldH,
              child: TextField(
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: labelStyle,
                decoration: _deco('$maxVal'),
                onChanged: (v){
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
              width: fieldW, height: fieldH,
              child: TextField(
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: labelStyle,
                decoration: _deco('$curVal'),
                onChanged: (v){
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
          line('FOR :', strMax, strCur, (m,c){ setState((){ strMax=m; strCur=c; }); }),
          line('DEX :', dexMax, dexCur, (m,c){ setState((){ dexMax=m; dexCur=c; }); }),
          line('VOL :', wilMax, wilCur, (m,c){ setState((){ wilMax=m; wilCur=c; }); }),
          line('PV  :',  hpMax,  hpCur,  (m,c){ setState((){  hpMax=m;  hpCur=c; }); }),
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Pépins : ', style: labelStyle),
              SizedBox(
                width: 48, height: fieldH,
                child: TextField(
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: labelStyle,
                  decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                  onChanged: (_){ _scheduleAutoSave(); },
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
              decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
              onChanged: (_){ _scheduleAutoSave(); },
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
        height: height ?? 43,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.75),
          border: Border.all(color: Colors.black54, width: 1.3),
          borderRadius: BorderRadius.circular(6),
        ),
        padding: const EdgeInsets.all(8),
        child: it == null
            ? Center(child: Text(slotLabel(slot), style: const TextStyle(color: Colors.black87)))
            : Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (it.imageUrl != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Image.network(it.imageUrl!, width: 44, height: 44, fit: BoxFit.cover),
                    )
                  else
                    const Icon(Icons.inventory_2_outlined, size: 36),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(it.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 6),
                        _durabilityDotsForSlot(
                          slot,
                          max: it.durabilityMax,
                          used: it.durabilityUsed,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _durabilityDotsForSlot(
    SlotType slot, {
    required int max,
    required int used,
  }) {
    final total = max.clamp(1, 6);
    return Row(
      children: List.generate(total, (i) {
        final filled = i < used;
        return GestureDetector(
          onTap: () async {
            final newUsed = (i + 1 == used) ? i : i + 1;
            setState(() => equipment[slot]!.durabilityUsed = newUsed); // UI optimiste
            await _updateDurability(slot, newUsed);                     // save immédiat
          },
          child: Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Icon(filled ? Icons.circle : Icons.circle_outlined, size: 14),
          ),
        );
      }),
    );
  }
}
