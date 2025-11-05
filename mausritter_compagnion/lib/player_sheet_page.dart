import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:collection/collection.dart';

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


// --- Grille PACK joueur: 2 lignes × 3 colonnes (indices 0..5)
// index -> (row, col) et inverse
int _packRows = 2, _packCols = 3;

({int r,int c}) _idxToRC(int idx) => (r: idx ~/ _packCols, c: idx % _packCols);
int _rcToIdx(int r, int c) => r * _packCols + c;

// Normalise une shape (liste d’indices 0..5) en coords relative (origine top-left)
List<({int r,int c})> _normalizeShape(List<int> shape) {
  final coords = shape.map(_idxToRC).toList();
  final minR = coords.map((e) => e.r).reduce((a,b) => a < b ? a : b);
  final minC = coords.map((e) => e.c).reduce((a,b) => a < b ? a : b);
  return coords.map((e) => (r: e.r - minR, c: e.c - minC)).toList();
}

// Rotation 0/90/180/270 autour de la bbox de la shape (pas du plateau)
List<({int r,int c})> _rotateShape(List<({int r,int c})> norm, int deg) {
  // bbox de la shape normalisée
  final H = norm.map((e) => e.r).reduce((a,b) => a>b?a:b) + 1;
  final W = norm.map((e) => e.c).reduce((a,b) => a>b?a:b) + 1;

  List<({int r,int c})> rot;
  switch (deg % 360) {
    case 0:
      rot = norm;
      break;
    case 90:
      // (r,c) -> (c, H-1-r) ; bbox devient (W,H)
      rot = norm.map((e) => (r: e.c, c: H - 1 - e.r)).toList();
      break;
    case 180:
      rot = norm.map((e) => (r: H - 1 - e.r, c: W - 1 - e.c)).toList();
      break;
    case 270:
      rot = norm.map((e) => (r: W - 1 - e.c, c: e.r)).toList();
      break;
    default:
      rot = norm;
  }
  // renormalise (origine top-left)
  final minR = rot.map((e) => e.r).reduce((a,b) => a < b ? a : b);
  final minC = rot.map((e) => e.c).reduce((a,b) => a < b ? a : b);
  return rot.map((e) => (r: e.r - minR, c: e.c - minC)).toList();
}

// Génère toutes les poses possibles (translations) de la shape (après rotation) dans la grille 2×3
List<List<int>> _translateAllFits(List<({int r,int c})> rot) {
  final H = rot.map((e) => e.r).reduce((a,b) => a>b?a:b) + 1;
  final W = rot.map((e) => e.c).reduce((a,b) => a>b?a:b) + 1;

  final maxDr = _packRows - H;
  final maxDc = _packCols - W;
  if (maxDr < 0 || maxDc < 0) return const [];

  final placements = <List<int>>[];
  for (var dr = 0; dr <= maxDr; dr++) {
    for (var dc = 0; dc <= maxDc; dc++) {
      final idxs = rot.map((e) => _rcToIdx(e.r + dr, e.c + dc)).toList()..sort();
      // évite doublons
      if (!placements.any((p) => p.length == idxs.length && ListEquality().equals(p, idxs))) {
        placements.add(idxs);
      }
    }
  }
  return placements;
}

// Toutes les poses (avec rotations si autorisées)
List<List<int>> allPackPlacements(List<int> shape, {required bool canRotate}) {
  if (shape.isEmpty) return const [];
  final norm = _normalizeShape(shape);
  final degs = canRotate ? const [0,90,180,270] : const [0];
  final out = <List<int>>[];
  for (final d in degs) {
    final rot = _rotateShape(norm, d);
    out.addAll(_translateAllFits(rot));
  }
  // unique
  final unique = <String, List<int>>{};
  for (final p in out) {
    unique[p.join(',')] = p;
  }
  return unique.values.toList();
}

/// Modèle simple d’item équipé côté UI
class EquippedItem {
  final String id;
  final String name;
  final String? description;
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
    this.description,
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

final Map<SlotType, GlobalKey> _slotKeys = {
  SlotType.pawMain: GlobalKey(),
  SlotType.pawOff:  GlobalKey(),
  SlotType.body1:   GlobalKey(),
  SlotType.body2:   GlobalKey(),
  SlotType.pack1:   GlobalKey(),
  SlotType.pack2:   GlobalKey(),
  SlotType.pack3:   GlobalKey(),
  SlotType.pack4:   GlobalKey(),
  SlotType.pack5:   GlobalKey(),
  SlotType.pack6:   GlobalKey(),
};

Size _slotSize(SlotType s) {
  final ctx = _slotKeys[s]?.currentContext;
  final box = ctx?.findRenderObject() as RenderBox?;
  return box?.size ?? const Size(120, 120); // fallback sûr
}

class _DragPayload {
  final SlotType from;           // slot d’origine
  final EquippedItem item;       // item déplacé
  final List<SlotType> occupied; // toutes les cases prises par cet item

  _DragPayload({
    required this.from,
    required this.item,
    required this.occupied,
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

String? _stringOrNull(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
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
          'pepin_cur': 0,
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

Offset _centerAnchorStrategy(Draggable<Object> _, BuildContext ctx, Offset __) {
  final box = ctx.findRenderObject() as RenderBox?;
  final size = box?.size ?? const Size(60, 60);
  // Décale l’origine du feedback au CENTRE du widget
  return Offset(size.width / 2, size.height / 2);
}


class _PackPlacementDialog extends StatefulWidget {
  final List<int> shape;           // indices 0..5 (forme de l'item)
  final bool canRotate;            // si on autorise 90/180/270
  final Set<int> occupied;         // cases déjà occupées (0..5)
  final int preferredIndex;        // index privilégié (case cliquée)

  const _PackPlacementDialog({
    required this.shape,
    required this.canRotate,
    required this.occupied,
    required this.preferredIndex,
  });

  @override
  State<_PackPlacementDialog> createState() => _PackPlacementDialogState();
}

class _PackPlacementDialogState extends State<_PackPlacementDialog> {
  final List<int> _angles = const [0, 90, 180, 270];
  int _angleIdx = 0; // pointeur dans _angles

  // NEW: preview courant (set d’indices 0..5) et dernière case pressée
  Set<int>? _preview;
  int? _lastPressed;

  List<({int r,int c})> get _norm => _normalizeShape(widget.shape);
  List<({int r,int c})> get _rot =>
      _rotateShape(_norm, _angles[_angleIdx % _angles.length]);

  // renvoie toutes les traductions possibles (listes d’indices 0..5) pour l’angle courant,
  // EXCLUANT les placements qui chevauchent une case occupée
  List<List<int>> _validPlacements() {
    final fits = <List<int>>[];
    final H = _rot.map((e) => e.r).reduce((a,b) => a>b?a:b) + 1;
    final W = _rot.map((e) => e.c).reduce((a,b) => a>b?a:b) + 1;
    final maxDr = _packRows - H;   // ← utilise bien les globals 2×3
    final maxDc = _packCols - W;
    if (maxDr < 0 || maxDc < 0) return const [];

    for (var dr = 0; dr <= maxDr; dr++) {
      for (var dc = 0; dc <= maxDc; dc++) {
        final idxs = _rot.map((e) => _rcToIdx(e.r + dr, e.c + dc)).toList()..sort();
        final collides = idxs.any(widget.occupied.contains);
        if (!collides) fits.add(idxs);
      }
    }
    // unique
    final seen = <String>{};
    final uniq = <List<int>>[];
    for (final p in fits) {
      final k = p.join(',');
      if (seen.add(k)) uniq.add(p);
    }
    return uniq;
  }

  void _rotateLeft() {
    if (!widget.canRotate) return;
    final n = _angles.length;
    setState(() => _angleIdx = (_angleIdx - 1 + n) % n);
  }

  void _rotateRight() {
    if (!widget.canRotate) return;
    setState(() => _angleIdx = (_angleIdx + 1) % _angles.length);
  }

  void _setPreviewForIndex(int idx, Map<int, List<int>> validTargets) {
    final p = validTargets[idx];
    setState(() => _preview = p == null ? null : p.toSet());
  }

  @override
  Widget build(BuildContext context) {
    final placements = _validPlacements();

    // idx -> 1er placement qui inclut cette case
    final validTargets = <int, List<int>>{};
    for (final p in placements) {
      for (final idx in p) {
        validTargets.putIfAbsent(idx, () => p);
      }
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Text('Placer l’objet', style: TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(
                  onPressed: widget.canRotate ? _rotateLeft : null,
                  icon: const Icon(Icons.rotate_left),
                  tooltip: 'Pivoter -90°',
                ),
                IconButton(
                  onPressed: widget.canRotate ? _rotateRight : null,
                  icon: const Icon(Icons.rotate_right),
                  tooltip: 'Pivoter +90°',
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: 200,
              child: AspectRatio(
                aspectRatio: _packCols / _packRows, // 3/2
                child: GridView.builder(
                  padding: EdgeInsets.zero,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _packRows * _packCols, // 6
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3, mainAxisSpacing: 6, crossAxisSpacing: 6,
                  ),
                  itemBuilder: (_, i) {
                    final isOcc = widget.occupied.contains(i);
                    final canPlaceHere = validTargets.containsKey(i);
                    final isPreferred = (i == widget.preferredIndex);
                    final inPreview = _preview?.contains(i) ?? false;

                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (_) {
                        _lastPressed = i;
                        if (!isOcc && canPlaceHere) {
                          _setPreviewForIndex(i, validTargets);
                        } else {
                          setState(() => _preview = null);
                        }
                      },
                      onTapCancel: () => setState(() => _preview = null),
                      onTapUp: (_) => setState(() => _preview = null),
                      onTap: (!isOcc && canPlaceHere)
                          ? () => Navigator.pop(context, validTargets[i])
                          : null,
                      onDoubleTap: widget.canRotate ? _rotateRight : null,
                      onHorizontalDragEnd: widget.canRotate ? (details) {
                        final v = details.primaryVelocity ?? 0;
                        if (v.abs() < 50) return;
                        if (v > 0) { _rotateRight(); } else { _rotateLeft(); }
                        if (_lastPressed != null && !isOcc && canPlaceHere) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) _setPreviewForIndex(_lastPressed!, validTargets);
                          });
                        }
                      } : null,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 100),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: isPreferred ? Colors.blueAccent : Colors.black54,
                            width: isPreferred ? 2.2 : 1.2,
                          ),
                          borderRadius: BorderRadius.circular(6),
                          color: isOcc
                              ? Colors.red.withOpacity(0.25)
                              : inPreview
                                  ? Colors.blue.withOpacity(0.28)
                                  : canPlaceHere
                                      ? Colors.green.withOpacity(0.22)
                                      : Colors.grey.withOpacity(0.10),
                        ),
                        child: Center(
                          child: Text(
                            '${i+1}',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: isOcc ? Colors.red.shade800 : Colors.black87,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 10),
            if (placements.isEmpty)
              const Text('Aucun placement possible. Libère de la place ou pivote.'),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler'),
            ),
          ],
        ),
      ),
    );
  }
}


class _PlayerSheetPageState extends State<PlayerSheetPage> {
  Timer? _saveTimer;
  DateTime _lastSave = DateTime.fromMillisecondsSinceEpoch(0);
  bool isDead = false;
  final pepinCtrl = TextEditingController(text: '0');
  final journalCtrl = TextEditingController();
  int pepinCur = 0;
  SlotType? _dragHover;

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
    pepinCtrl.dispose();
    super.dispose();
    journalCtrl.dispose();
  }

  bool _isPack(SlotType s) =>
    s == SlotType.pack1 || s == SlotType.pack2 || s == SlotType.pack3 ||
    s == SlotType.pack4 || s == SlotType.pack5 || s == SlotType.pack6;

  static const List<SlotType> _packs = [
    SlotType.pack1, SlotType.pack2, SlotType.pack3,
    SlotType.pack4, SlotType.pack5, SlotType.pack6,
  ];

int _packIndex(SlotType s) => _packs.indexOf(s); // 0..5

List<SlotType> _allSlotsHolding(String itemId) {
  final out = <SlotType>[];
  for (final kv in equipment.entries) {
    if (kv.value?.id == itemId) out.add(kv.key);
  }
  return out;
}

// Compat de base par type de slot
bool _accepts(SlotType target, EquippedItem it) {
  switch (target) {
    case SlotType.pawMain:
    case SlotType.pawOff:
      return it.category == 'WEAPON' || it.category == 'TOOL' || it.category == 'OTHER';
    case SlotType.body1:
    case SlotType.body2:
      return it.category == 'ARMOR' || it.category == 'AMMO' || it.category == 'OTHER';
    default:
      return true; // PACK accepte tout (on gère la shape/size après)
  }
}



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

bool _canDropHere(_DragPayload d, SlotType target) {
  final it = d.item;

  if (target == d.from) return true;                 // reposer au même endroit
  if (!_accepts(target, it)) return false;           // compat basique

  if (_isPack(target)) {
    if (it.packSize <= 1) {
      return equipment[target] == null || equipment[target]?.id == it.id;
    } else {
      // on laisse passer, la boîte de placement filtrera vraiment
      return true;
    }
  }

  // Pattes 2 mains : l’autre doit être libre ou déjà occupé par ce même item
  if ((target == SlotType.pawMain || target == SlotType.pawOff) && it.two_handed) {
    final other = _otherPaw(target);
    return equipment[other] == null || equipment[other]?.id == it.id;
  }

  // Corps 2 cases : idem
  if ((target == SlotType.body1 || target == SlotType.body2) && it.two_body) {
    final other = _otherBody(target);
    return equipment[other] == null || equipment[other]?.id == it.id;
  }

  // Sinon case libre ou déjà ce même item
  return equipment[target] == null || equipment[target]?.id == it.id;
}

Future<void> _performDrop(_DragPayload d, SlotType target) async {
  final it = d.item;

  // 1) on libère les cases d’origine de cet item
  await _clearEverywhere(it);

  // 2) placement selon le type cible
  if (_isPack(target)) {
    if (it.packSize <= 1) {
      setState(() => equipment[target] = it);
      final id = _characterId;
      if (id != null) {
        await supa.from('character_items').upsert({
          'character_id': id,
          'slot': _slotToDb(target),
          'item_id': it.id,
          'durability_used': it.durabilityUsed,
        }, onConflict: 'character_id,slot');
      }
      return;
    } else {
      // Multi-cases → on récupère shape/canRotate puis on ouvre la boîte de placement
      final row = await supa
          .from('items')
          .select('pack_shape,pack_can_rotate,pack_size')
          .eq('id', it.id)
          .maybeSingle();

      List<int> shape = ((row?['pack_shape'] as List?) ?? const [])
          .map((e) => int.tryParse(e.toString()) ?? -1)
          .where((i) => i >= 0 && i <= 5)
          .toList();
      final canRotate = (row?['pack_can_rotate'] as bool?) ?? true;
      final size = (row?['pack_size'] as int?)?.clamp(1, 6) ?? it.packSize;

      if (shape.length != size) {
        shape = List<int>.generate(size, (i) => i);
      }

      const order = [
        SlotType.pack1, SlotType.pack2, SlotType.pack3,
        SlotType.pack4, SlotType.pack5, SlotType.pack6,
      ];
      final occupied = <int>{};
      for (int i = 0; i < order.length; i++) {
        if (equipment[order[i]] != null) occupied.add(i);
      }
      final preferredIndex = order.indexOf(target);

      final chosenIdxs = await showModalBottomSheet<List<int>>(
        context: context,
        isScrollControlled: true,
        builder: (_) => _PackPlacementDialog(
          shape: shape,
          canRotate: canRotate,
          occupied: occupied,
          preferredIndex: preferredIndex,
        ),
      );

      if (chosenIdxs == null || chosenIdxs.isEmpty) return;

      final chosenSlots = chosenIdxs.map((i) => order[i]).toList();

      setState(() {
        for (final s in chosenSlots) {
          equipment[s] = it;
        }
      });

      final id = _characterId;
      if (id != null) {
        for (final s in chosenSlots) {
          await supa.from('character_items').upsert({
            'character_id': id,
            'slot': _slotToDb(s),
            'item_id': it.id,
            'durability_used': it.durabilityUsed,
          }, onConflict: 'character_id,slot');
        }
      }
      await _updateDurability(chosenSlots.first, it.durabilityUsed);
      return;
    }
  }

  // PATTE
  if (target == SlotType.pawMain || target == SlotType.pawOff) {
    setState(() {
      equipment[target] = it;
      if (it.category == 'WEAPON' && it.two_handed) {
        equipment[_otherPaw(target)] = it;
      }
    });

    final id = _characterId;
    if (id != null) {
      await supa.from('character_items').upsert({
        'character_id': id,
        'slot': _slotToDb(target),
        'item_id': it.id,
        'durability_used': it.durabilityUsed,
      }, onConflict: 'character_id,slot');
      if (it.two_handed) {
        await supa.from('character_items').upsert({
          'character_id': id,
          'slot': _slotToDb(_otherPaw(target)),
          'item_id': it.id,
          'durability_used': it.durabilityUsed,
        }, onConflict: 'character_id,slot');
      }
    }
    await _updateDurability(target, it.durabilityUsed);
    if (it.two_handed) {
      await _updateDurability(_otherPaw(target), it.durabilityUsed);
    }
    return;
  }

  // CORPS
  if (target == SlotType.body1 || target == SlotType.body2) {
    setState(() {
      equipment[target] = it;
      if (it.category == 'ARMOR' && it.two_body) {
        equipment[_otherBody(target)] = it;
      }
    });

    final id = _characterId;
    if (id != null) {
      await supa.from('character_items').upsert({
        'character_id': id,
        'slot': _slotToDb(target),
        'item_id': it.id,
        'durability_used': it.durabilityUsed,
      }, onConflict: 'character_id,slot');
      if (it.category == 'ARMOR' && it.two_body) {
        await supa.from('character_items').upsert({
          'character_id': id,
          'slot': _slotToDb(_otherBody(target)),
          'item_id': it.id,
          'durability_used': it.durabilityUsed,
        }, onConflict: 'character_id,slot');
      }
    }
    // (pas de durabilité pour ARMOR)
    return;
  }
}


Future<void> _clearEverywhere(EquippedItem it) async {
  final id = _characterId;
  final slots = _allSlotsHolding(it.id);

  setState(() {
    for (final s in slots) {
      equipment[s] = null;
    }
  });

  if (id != null) {
    for (final s in slots) {
      await supa.from('character_items').delete().match({
        'character_id': id,
        'slot': _slotToDb(s),
      });
    }
  }
}


Future<void> _openJournalDialog() async {
  await showDialog(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      final isMobile = MediaQuery.of(ctx).size.width < 600;

      return Dialog(
        insetPadding: EdgeInsets.symmetric(
          horizontal: isMobile ? 0 : 80,
          vertical: isMobile ? 0 : 60,
        ),
        child: Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            title: const Text("Journal d'aventure"),
            automaticallyImplyLeading: false,
            actions: [
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(ctx),
              ),
            ],
          ),
          body: Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: journalCtrl,
              maxLines: null,
              expands: true, // <-- clé pour remplir tout l'espace
              textAlign: TextAlign.left,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              decoration: const InputDecoration(
                hintText: "Écris ici tes notes, rencontres, loot, indices…",
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.all(12),
              ),
              onChanged: (_) => _scheduleAutoSave(),
            ),
          ),
        ),
      );
    },
  );
}

  // ------- Sélecteur d’items filtrés par slot + recherche -------
Future<void> _pickItemForSlot(SlotType slot) async {
  final tag = slotTag(slot);
  
  // Requête serveur avec filtre texte (nom + description)
  Future<List<dynamic>> fetch(String q) async {
    var req = supa
        .from('items')
        .select(
          'id,name,image_url,durability_max,compatible_slots,category,damage,defense,two_handed,two_body,pack_size,description,pack_shape,pack_can_rotate',
        )
        .contains('compatible_slots', [tag]);

    final s = q.trim();
    if (s.isNotEmpty) {
      req = req.or('name.ilike.%$s%,description.ilike.%$s%');
    }
    return await req.order('name', ascending: true);
  }

  // Charge initial (sans filtre)
  List<dynamic> rows = await fetch('');
  if (!mounted) return;

  // ----- BottomSheet avec barre de recherche -----
  final chosen = await showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      final searchCtrl = TextEditingController();
      Timer? deb;

      return SafeArea(
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.85,
          maxChildSize: 0.95,
          minChildSize: 0.6,
          builder: (_, ctl) => StatefulBuilder(
            builder: (ctx, setS) => Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                  child: TextField(
                    controller: searchCtrl,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Rechercher un item…',
                      isDense: true,
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: (searchCtrl.text.isEmpty)
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () async {
                                searchCtrl.clear();
                                rows = await fetch('');
                                if (ctx.mounted) setS(() {});
                              },
                            ),
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (v) {
                      deb?.cancel();
                      deb = Timer(const Duration(milliseconds: 250), () async {
                        rows = await fetch(v);
                        if (ctx.mounted) setS(() {});
                      });
                    },
                    onSubmitted: (v) async {
                      rows = await fetch(v);
                      if (ctx.mounted) setS(() {});
                    },
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
                          'Durabilité ${r['durability_max'] ?? 3}${twoH ? ' • 2 mains' : ''}',
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
    },
  );

  if (chosen == null) return;

  // --- GESTION PACK AVEC CHOIX MANUEL (rotation + position) ---
if (slotTag(slot) == 'PACK') {
  final int packSize = (chosen['pack_size'] as int?)?.clamp(1,6) ?? 1;

  if (packSize > 1) {
    // 1) récupérer la shape ; fallback linéaire [0..packSize-1] si absente
    List<int> packShape = ((chosen['pack_shape'] as List?) ?? const [])
        .map((e) => int.tryParse(e.toString()) ?? -1)
        .where((i) => i >= 0 && i <= 5)
        .toList();
    if (packShape.length != packSize) {
      packShape = List<int>.generate(packSize, (i) => i); // fallback simple
    }

    final bool canRotate = (chosen['pack_can_rotate'] as bool?) ?? true;

    // 2) construire l’occupation actuelle des 6 cases
    const order = [
      SlotType.pack1, SlotType.pack2, SlotType.pack3,
      SlotType.pack4, SlotType.pack5, SlotType.pack6,
    ];
    final occupied = <int>{};
    for (int i = 0; i < order.length; i++) {
      final s = order[i];
      if (equipment[s] != null) occupied.add(i);
    }

    // 3) case préférée = celle sur laquelle l’utilisateur a cliqué
    final preferredIndex = order.indexOf(slot);

    // 4) ouvrir le sélecteur
    final chosenIdxs = await showModalBottomSheet<List<int>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PackPlacementDialog(
        shape: packShape,
        canRotate: canRotate,
        occupied: occupied,
        preferredIndex: preferredIndex,
      ),
    );

    if (chosenIdxs == null || chosenIdxs.isEmpty) return; // annulé

    // 5) on a la liste d’indices 0..5 retenue → map vers SlotType
    final chosenSlots = chosenIdxs.map((i) => order[i]).toList();

    // 6) construire l'EquippedItem et poser sur ces slots
    final equipped = EquippedItem(
      id: chosen['id'].toString(),
      name: chosen['name'] ?? 'Item',
      description: chosen['description'] as String?,
      imageUrl: chosen['image_url'] as String?,
      durabilityMax: (chosen['durability_max'] as int?) ?? 3,
      durabilityUsed: 0,
      category: (chosen['category'] as String?) ?? 'OTHER',
      damage: _stringOrNull(chosen['damage']),
      defense: (chosen['defense'] is int)
          ? chosen['defense'] as int
          : int.tryParse('${chosen['defense'] ?? ''}'),
      two_handed: (chosen['two_handed'] as bool?) ?? false,
      two_body: (chosen['two_body'] as bool?) ?? false,
      packSize: packSize,
    );

    // si c’est une case PACK simple, refuse si déjà occupée
    if (slotTag(slot) == 'PACK' && equipment[slot] != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Case occupée. Retire l’objet d’abord.')),
      );
      return;
    }

    // libérer au cas où (rare) des cases qui contiendraient la même id
    setState(() {
      for (final s in order) {
        if (equipment[s]?.id == equipped.id) equipment[s] = null;
      }
      for (final s in chosenSlots) {
        equipment[s] = equipped;
      }
    });

    // persistance
    final id = _characterId;
    if (id != null) {
      for (final s in chosenSlots) {
        await supa.from('character_items').upsert({
          'character_id': id,
          'slot': _slotToDb(s),
          'item_id': equipped.id,
          'durability_used': equipped.durabilityUsed,
        }, onConflict: 'character_id,slot');
      }
    }
    await _updateDurability(chosenSlots.first, 0);
    return; // on ne passe pas à l’auto-placement plus bas
  }
}


  // ----- Suite inchangée : création de l’EquippedItem + placement -----
  final equipped = EquippedItem(
    id: chosen['id'].toString(),
    name: chosen['name'] ?? 'Item',
    description: chosen['description'] as String?,
    imageUrl: chosen['image_url'] as String?,
    durabilityMax: (chosen['durability_max'] as int?) ?? 3,
    durabilityUsed: 0,
    category: (chosen['category'] as String?) ?? 'OTHER',
    damage: _stringOrNull(chosen['damage']),
    defense: (chosen['defense'] is int)
        ? chosen['defense'] as int
        : int.tryParse('${chosen['defense'] ?? ''}'),
    two_handed: (chosen['two_handed'] as bool?) ?? false,
    two_body: (chosen['two_body'] as bool?) ?? false,
    packSize: (chosen['pack_size'] as int?)?.clamp(1, 6) ?? 1,
  );



  setState(() {
    equipment[slot] = equipped;
    if (_isPaw(slot) && equipped.category == 'WEAPON' && equipped.two_handed) {
      equipment[_otherPaw(slot)] = equipped;
    }
    if (_isBody(slot) && equipped.category == 'ARMOR' && equipped.two_body) {
      equipment[_otherBody(slot)] = equipped;
    }
  });

  await _saveCharacter();

  await _updateDurability(slot, 0);
  if (_isPaw(slot) && equipped.two_handed) {
    await _updateDurability(_otherPaw(slot), 0);
  }
  if (_isBody(slot) && equipped.two_body) {
    await _updateDurability(_otherBody(slot), 0);
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
      _hydrateFromRow(r); 
      await _loadEquipmentFor(_characterId!);
      return;
    }

    // 2) sinon : charger la dernière fiche de ce joueur (s’il y en a)
    final r = await supa
        .from('characters')
        .select()
        .eq('owner_id', uid)
        .order('updated_at', ascending: false) 
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
          'pepin_cur': pepinCur,               
          'stats': {
            'str': {'max': strMax, 'cur': strCur},
            'dex': {'max': dexMax, 'cur': dexCur},
            'wil': {'max': wilMax, 'cur': wilCur},
            'hp' : {'max': hpMax , 'cur': hpCur},
          },
          'slots': {},
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
  journalCtrl.text = (r['journal'] ?? '') as String;
  level = (r['level'] ?? 1) as int;
  levelCtrl.text = '$level';
  xp = (r['xp'] ?? 0) as int;
  xpCtrl.text = '$xp';
  // --- Pepins
  pepinCur = (r['pepin_cur'] ?? 0) as int? ?? 0;
  pepinCtrl.text = '$pepinCur';

  // --- Stats: JSON > colonnes à plat (fallback)
  final stats = (r['stats'] ?? {}) as Map<String, dynamic>;
  if (stats.isNotEmpty) {
    strMax = (stats['str']?['max'] ?? 10) as int;
    strCur = (stats['str']?['cur'] ?? 10) as int;
    dexMax = (stats['dex']?['max'] ?? 10) as int;
    dexCur = (stats['dex']?['cur'] ?? 10) as int;
    wilMax = (stats['wil']?['max'] ?? 10) as int;
    wilCur = (stats['wil']?['cur'] ?? 10) as int;
    hpMax  = (stats['hp']?['max']  ?? 4)  as int;
    hpCur  = (stats['hp']?['cur']  ?? 4)  as int;
  } else {
    // fallback si ta table a encore des colonnes à plat
    strMax = (r['str_max'] ?? 10) as int;
    strCur = (r['str_cur'] ?? 10) as int;
    dexMax = (r['dex_max'] ?? 10) as int;
    dexCur = (r['dex_cur'] ?? 10) as int;
    wilMax = (r['wil_max'] ?? 10) as int;
    wilCur = (r['wil_cur'] ?? 10) as int;
    hpMax  = (r['hp_max']  ?? 4)  as int;
    hpCur  = (r['hp_cur']  ?? 4)  as int;
  }

  isDead = (r['is_dead'] as bool?) ?? false;
  setState(() {});
}

  Future<void> _loadEquipmentFor(String characterId) async {
    final eq = await supa
        .from('character_items')
        .select(
          'slot,item_id,durability_used, items(name,image_url,durability_max,category,damage,defense,two_handed, two_body, pack_size,description,pack_shape,pack_can_rotate)',
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
        description: item['description'] as String?,
        imageUrl: item['image_url'] as String?,
        durabilityMax: (item['durability_max'] as int?) ?? 3,
        durabilityUsed: (e['durability_used'] as int?) ?? 0,
        category: (item['category'] as String?) ?? 'OTHER',
        damage: _stringOrNull(item['damage']),
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

      // ✅ Création initiale cohérente avec `stats` + `pepin_cur`
      final ins = await supa
          .from('characters')
          .insert({
            'owner_id': uid,
            'name': '',
            'background': '',
            'level': level,
            'xp': xp,
            'pepin_cur': pepinCur,
            'stats': {
              'str': {'max': strMax, 'cur': strCur},
              'dex': {'max': dexMax, 'cur': dexCur},
              'wil': {'max': wilMax, 'cur': wilCur},
              'hp' : {'max': hpMax , 'cur': hpCur },
            },
            'slots': {},
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
  if (!force && now.difference(_lastSave) < const Duration(milliseconds: 400)) {
    return;
  }
  _lastSave = now;

  final id = await _ensureCharacterId();
  if (id == null) {
    if (showFeedback) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible d’identifier l’utilisateur.')),
      );
    }
    return;
  }

  try {
    level = int.tryParse(levelCtrl.text.trim()) ?? level;
    xp    = int.tryParse(xpCtrl.text.trim()) ?? xp;

    // ✅ On sauve TOUT dans le JSON `stats` + `pepin_cur`
    final payload = {
      'name': nameCtrl.text.trim(),
      'background': backgroundCtrl.text.trim(),
      'level': level,
      'xp': xp,
      'pepin_cur': pepinCur,
      'stats': {
        'str': {'max': strMax, 'cur': strCur},
        'dex': {'max': dexMax, 'cur': dexCur},
        'wil': {'max': wilMax, 'cur': wilCur},
        'hp' : {'max': hpMax , 'cur': hpCur },
      },
      'journal': journalCtrl.text.trim(),
    };

    await supa.from('characters').update(payload).eq('id', id);

    // --- items équipés (inchangé)
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
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Fiche enregistrée ✅')));
    }
  } catch (e) {
    if (showFeedback) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Erreur à l’enregistrement : $e')));
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
      title: Row(
        children: [
          const Text('Fiche de personnage'),
          // Le bouton “Journal” centré horizontalement
          Expanded(
            child: Center(
              child: FilledButton.tonal(
                onPressed: _openJournalDialog,
                child: const Text('Journal'),
              ),
            ),
          ),
        ],
      ),
      centerTitle: false,
      actions: [
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
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // ta fiche
                      _sheetBody(),

                      // watermark "souris morte" si isDead
                      if (isDead)
                        Positioned.fill(
                          child: IgnorePointer( 
                            ignoring: true,
                            child: Center(
                              child: Opacity(
                                opacity: 0.85, 
                                child: Image.asset(
                                  'assets/icons/icon_souris_morte.png',
                                  width: designW * 0.80,   // ~80% de la largeur de la fiche
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
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
    const xpW = 45.0;

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
                      textAlign: TextAlign.left,
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
    const fieldH = 30.0;
    const fieldW = 37.0;

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
          const SizedBox(height: 3),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Pépins : ', style: labelStyle),
              SizedBox(
                width: 60,
                height: fieldH,
                child: TextField(
                  controller: pepinCtrl,                // ← NEW
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.left,
                  style: labelStyle,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) {
                    final only = v.replaceAll(RegExp(r'[^0-9]'), '');
                    final val = int.tryParse(only) ?? pepinCur;
                    pepinCur = val.clamp(0, 250);       
                    if (pepinCtrl.text != '$pepinCur') {
                      pepinCtrl.text = '$pepinCur';
                      pepinCtrl.selection = TextSelection.fromPosition(
                        TextPosition(offset: pepinCtrl.text.length),
                      );
                    }
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
            height: 100, // ← hauteur fixe ou tu peux mettre null pour auto
            child: TextField(
              controller: backgroundCtrl,
              style: labelStyle,
              maxLines: null,            // ← autorise multi-lignes auto
              minLines: 3,               // ← hauteur mini visible
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => _scheduleAutoSave(),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- Slots & Pack ----------------
  Widget _slotCard(SlotType slot, {double? height}) {
  final it = equipment[slot];
  final isHover = _dragHover == slot;

  Offset _centerAnchorFor(SlotType s, Draggable<Object> _, BuildContext __, Offset ___) {
  final sz = _slotSize(s);
  return Offset(sz.width / 2, sz.height / 2);
}

  // carte visuelle (utilisée par child / feedback)
  Widget _buildCard() {
    return Container(
      key: _slotKeys[slot],
      height: height ?? 120,
      decoration: BoxDecoration(
        border: Border.all(
          color: isHover ? Colors.blueAccent : Colors.black54,
          width: isHover ? 2.2 : 1.3,
        ),
        borderRadius: BorderRadius.circular(10),
        color: Colors.white.withOpacity(0.6),
      ),
      clipBehavior: Clip.antiAlias,
      child: it == null
          ? Center(child: Text(slotLabel(slot), style: const TextStyle(color: Colors.black87)))
          : Stack(
              fit: StackFit.expand,
              children: [
                if (it.imageUrl != null)
                  Image.network(it.imageUrl!, fit: BoxFit.cover)
                else
                  const Center(child: Icon(Icons.inventory_2_outlined, size: 42)),

                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter, end: Alignment.bottomCenter,
                        colors: [Colors.black.withOpacity(0.35), Colors.transparent, Colors.black.withOpacity(0.45)],
                        stops: const [0.0, 0.55, 1.0],
                      ),
                    ),
                  ),
                ),

                if ((it.description ?? '').isNotEmpty)
                  Positioned(
                    top: 6, left: 6,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () {
                          showDialog(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: Text(it.name),
                              content: SingleChildScrollView(child: Text(it.description!, textAlign: TextAlign.left)),
                              actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fermer'))],
                            ),
                          );
                        },
                        child: const Padding(
                          padding: EdgeInsets.all(4.0),
                          child: Icon(Icons.info_outline, size: 18, color: Colors.white),
                        ),
                      ),
                    ),
                  ),

                Positioned(
                  left: 6, right: 6, top: 30,
                  child: Text(
                    it.name,
                    maxLines: null, textAlign: TextAlign.center, softWrap: true, overflow: TextOverflow.visible,
                    style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white, height: 1.1,
                      shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
                    ),
                  ),
                ),

                Positioned(top: 6, right: 6, child: _itemBadgeFor(it)),

                // bouton supprimer
                Positioned(
                  left: 5, bottom: 5,
                  child: Material(
                    color: Colors.transparent,
                    child: Tooltip(
                      message: 'Supprimer',
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => _unequip(slot),
                        child: Container(
                          padding: const EdgeInsets.all(1),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withOpacity(0.95),
                            border: Border.all(color: Colors.black87, width: 1.1),
                          ),
                          child: Icon(Icons.close, size: 8, color: Colors.red.shade700),
                        ),
                      ),
                    ),
                  ),
                ),

                if (it.category != 'ARMOR' && it.durabilityMax > 0)
                  Positioned(
                    left: 0, right: 0, bottom: 6,
                    child: Center(
                      child: _durabilityDotsForSlot(
                        slot, max: it.durabilityMax, used: it.durabilityUsed,
                        color: Colors.white, size: 16, spacing: 6,
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
  final sz = _slotSize(slot);
  // Draggable si item présent
  final childCard = (it == null)
    ? _buildCard()
    : LongPressDraggable<_DragPayload>(
        data: _DragPayload(
          from: slot,
          item: it,
          occupied: _allSlotsHolding(it.id),
        ),

        // 👉 feedback à la TAILLE RÉELLE de la carte
       feedback: Opacity(
          opacity: 0.85,
          child: Material(
            type: MaterialType.transparency,
            child: SizedBox(width: sz.width, height: sz.height, child: _buildCard()),
          ),
        ),
        // Plus AUCUN offset manuel
        feedbackOffset: Offset.zero,
        // Centre du widget sous le doigt
        dragAnchorStrategy: (d, ctx, pos) => _centerAnchorFor(slot, d, ctx, pos),

        childWhenDragging: Opacity(opacity: 0.35, child: _buildCard()),
        child: _buildCard(),
      );

return DragTarget<_DragPayload>(
  onWillAccept: (d) {
    final ok = d != null && _canDropHere(d, slot);
    if (ok) setState(() => _dragHover = slot);
    return ok;
  },
  onLeave: (_) => setState(() => _dragHover = null),
  onAccept: (d) async {
    setState(() => _dragHover = null);
    await _performDrop(d, slot);
  },
  builder: (_, __, ___) => GestureDetector(
    onTap: () => _pickItemForSlot(slot),
    onLongPress: () => _unequip(slot),
    child: childCard,
  ),
);
}


  Widget _itemBadgeFor(EquippedItem it) {
    String? text;

    if (it.category == 'WEAPON') {
      final d = it.damage?.trim();
      if (d != null && d.isNotEmpty) {
        // "6" → "d6", garde "d6", "d6/d8", "2d6+1", etc.
        text = RegExp(r'^\d+$').hasMatch(d) ? 'd$d' : d;
      }
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
    if (max <= 0) return const SizedBox.shrink();  // ← rien à afficher

    final total = max.clamp(1, 6); // 1..6 seulement si max>0
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(total, (i) {
        final filled = i < used;
        return GestureDetector(
          onTap: () async {
            final newUsed = (i + 1 == used) ? i : i + 1;
            setState(() => equipment[slot]!.durabilityUsed = newUsed);
            await _updateDurability(slot, newUsed);
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
