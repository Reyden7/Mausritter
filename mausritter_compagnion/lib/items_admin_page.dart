import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ItemsAdminPage extends StatefulWidget {
  const ItemsAdminPage({super.key});
  @override
  State<ItemsAdminPage> createState() => _ItemsAdminPageState();
}

class _ItemsAdminPageState extends State<ItemsAdminPage> {
  final supa = Supabase.instance.client;
  bool loading = true;
  List<dynamic> items = [];

  static const bucket = 'items'; // bucket Supabase Storage (public conseillé)

  // Catégories autorisées (alignées avec la BDD)
  static const categories = [
    'WEAPON',
    'ARMOR',
    'AMMO',
    'LIGHT',
    'RATION',
    'OTHER',
  ];
  // Slots compatibles
  static const slots = ['PAW_MAIN', 'PAW_OFF', 'BODY', 'PACK'];

  // Presets visuels
  static const weaponPresets = <String>[
    'd6',
    'd6/d8',
    'd10',
    'd8',
    'Personnalisé…',
  ];
  static const armorPresets = <String>[
    '1 DEF',
    '2 DEF',
    '3 DEF',
    '4 DEF',
    'Personnalisé…',
  ];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => loading = true);
    final data = await supa.from('items').select().order('name', ascending: true, nullsFirst: false);
    setState(() {
      items = data;
      loading = false;
    });
  }

  // ====== Choix Galerie / Appareil photo ======
  Future<ImageSource?> _chooseSource(BuildContext context) async {
    return showModalBottomSheet<ImageSource>(
      context: context,
      builder: (bCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Depuis la galerie'),
              onTap: () => Navigator.pop(bCtx, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Prendre une photo'),
              onTap: () => Navigator.pop(bCtx, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _pickAndUploadImage() async {
    try {
      final source = await _chooseSource(context);
      if (source == null) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Action annulée')));
        }
        return null;
      }

      final picker = ImagePicker();
      final x = await picker.pickImage(
        source: source,
        imageQuality: 85,
        preferredCameraDevice: CameraDevice.rear,
      );
      if (x == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                source == ImageSource.camera
                    ? 'Aucune photo prise'
                    : 'Aucune image sélectionnée',
              ),
            ),
          );
        }
        return null;
      }

      final bytes = await x.readAsBytes();

      // Nom unique + extension ; ranger sous le dossier de l’utilisateur
      String ext = 'jpg';
      final parts = x.name.split('.');
      if (parts.length > 1) ext = parts.last.toLowerCase();
      final uid = supa.auth.currentUser!.id;
      final path = '$uid/items_${DateTime.now().millisecondsSinceEpoch}.$ext';

      await supa.storage
          .from(bucket)
          .uploadBinary(
            path,
            Uint8List.fromList(bytes),
            fileOptions: FileOptions(upsert: true, contentType: 'image/$ext'),
          );

      // Bucket public → URL directe
      final url = supa.storage.from(bucket).getPublicUrl(path);
      return url;
    } on StorageException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Storage: ${e.message}')));
      }
      return null;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erreur upload: $e')));
      }
      return null;
    }
  }

  Future<void> _createOrEdit({Map<String, dynamic>? existing}) async {
    final nameCtrl = TextEditingController(text: existing?['name'] ?? '');
    final duraCtrl = TextEditingController(
      text: (existing?['durability_max'] ?? 3).toString(),
    );
    final descCtrl = TextEditingController(text: existing?['description'] ?? '');
    String category = existing?['category'] ?? 'OTHER';
    final selected = <String>{
      ...(existing?['compatible_slots']?.cast<String>() ?? <String>[]),
    };
    int packSize = (existing?['pack_size'] as int?)?.clamp(1,6) ?? 1;
    String? imageUrl = existing?['image_url'];
    bool twoHanded = (existing?['two_handed'] as bool?) ?? false;
    bool twoBody   = (existing?['two_body']   as bool?) ?? false;

    // Champs spécifiques
    String? damage = existing?['damage'] as String?;
    int? defense;
    final raw = existing?['defense'];

    if (raw is int) {
      defense = raw;
    } else if (raw != null) {
      defense = int.tryParse(raw.toString());
    } else {
      defense = null;
    }

    // Contrôleurs pour “Personnalisé…”
    final dmgCustomCtrl = TextEditingController(
      text: (damage != null && !weaponPresets.contains(damage)) ? damage : '',
    );
    final defCustomCtrl = TextEditingController(
      text: (defense != null && ![1, 2, 3, 4].contains(defense))
          ? '$defense'
          : '',
    );

    // Valeur de preset sélectionnée (ou “Personnalisé…”)
    String weaponPresetValue = damage == null
        ? weaponPresets.first
        : (weaponPresets.contains(damage) ? damage : 'Personnalisé…');

    String armorPresetValue = defense == null
        ? armorPresets.first
        : ([1, 2, 3, 4].contains(defense)
              ? '${defense!} DEF'
              : 'Personnalisé…');

    await showModalBottomSheet(
      isScrollControlled: true,
      context: context,
      builder: (sheetCtx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 16,
          ),
          child: StatefulBuilder(
            builder: (ctx, setS) {
              // Widgets conditionnels
              Widget _weaponSection() {
                if (category != 'WEAPON') return const SizedBox.shrink();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 12),
                    Text(
                      'Dégâts (arme)',
                      style: Theme.of(ctx).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 6),

                    // ✅ Dropdown des PRÉSETS DE DÉGÂTS (et plus le dropdown de "category")
                    DropdownButtonFormField<String>(
                      value: weaponPresetValue,
                      items: weaponPresets
                          .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                          .toList(),
                      onChanged: (v) => setS(() {
                        weaponPresetValue = v!;
                        if (v == 'Personnalisé…') {
                          final t = dmgCustomCtrl.text.trim();
                          damage = t.isEmpty ? null : t;
                        } else {
                          damage = v; // d6, d6/d8, d10, etc.
                        }
                      }),
                      decoration: const InputDecoration(labelText: 'Preset'),
                    ),

                    if (weaponPresetValue == 'Personnalisé…') ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: dmgCustomCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Dégâts personnalisés (ex: 2d6, d6+1, d6/d10...)',
                        ),
                        onChanged: (v) => setS(() {
                          final t = v.trim();
                          damage = t.isEmpty ? null : t;
                        }),
                      ),
                    ],

                    const SizedBox(height: 8),
                    CheckboxListTile(
                      value: twoHanded,
                      onChanged: (v) => setS(() => twoHanded = v ?? false),
                      title: const Text('Arme à deux mains'),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                  ],
                );
              }

              Widget _armorSection() {
                if (category != 'ARMOR') return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 12),
                    Text(
                      'Défense (armure)',
                      style: Theme.of(ctx).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      value: armorPresetValue,
                      items: armorPresets
                          .map(
                            (d) => DropdownMenuItem(value: d, child: Text(d)),
                          )
                          .toList(),
                      onChanged: (v) => setS(() {
                        armorPresetValue = v!;
                        if (v == 'Personnalisé…') {
                          defense = int.tryParse(defCustomCtrl.text.trim());
                        } else {
                          defense = int.parse(
                            v.split(' ').first,
                          ); // "1 DEF" -> 1
                        }
                        
                      }),
                      
                      decoration: const InputDecoration(labelText: 'Preset'),
                    ),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      value: twoBody,
                      onChanged: (v) => setS(() => twoBody = v ?? false),
                      title: const Text('Armure qui occupe les 2 cases du corps'),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                    if (armorPresetValue == 'Personnalisé…') ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: defCustomCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'DEF personnalisée (entier)',
                        ),
                        onChanged: (v) =>
                            setS(() => defense = int.tryParse(v.trim())),
                      ),
                    ],
                  ],
                );
              }

              Widget _packSizeSection() {
                if (!selected.contains('PACK')) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      const Text('Taille (PACK) : '),
                      const SizedBox(width: 8),
                      DropdownButton<int>(
                        value: packSize,
                        items: [1, 2, 3, 4, 5, 6]
                            .map((n) => DropdownMenuItem(value: n, child: Text('$n')))
                            .toList(),
                        onChanged: (v) => setS(() => packSize = v ?? 1),
                      ),
                    ],
                  ),
                );
              }

              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      existing == null ? 'Nouvel item' : 'Modifier l’item',
                      style: Theme.of(ctx).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: descCtrl,
                      maxLines: 10,
                      minLines: 1,
                      keyboardType: TextInputType.multiline,
                      decoration: const InputDecoration(
                        labelText: "Description de l'item",
                        alignLabelWithHint: true,
                      ),
                    ),

                    const SizedBox(height: 12),
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(labelText: 'Nom'),
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: duraCtrl,
                      enabled: true,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Durabilité max (ex: 3)',
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: category,
                      items: categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                      onChanged: (v) => setS(() {
                        category = v!;

                        // reset propres
                        if (category != 'WEAPON') {
                          weaponPresetValue = weaponPresets.first;
                          damage = null;
                          dmgCustomCtrl.clear();
                        }
                        if (category != 'ARMOR') {
                          armorPresetValue = armorPresets.first;
                          defense = null;
                          defCustomCtrl.clear();
                        } else {
                          // ← ICI : on initialise defense selon le preset affiché
                          if (armorPresetValue != 'Personnalisé…') {
                            defense = int.parse(armorPresetValue.split(' ').first); // "1 DEF" -> 1
                          } else {
                            defense = int.tryParse(defCustomCtrl.text.trim());
                          }
                        }
                    }),
                    decoration: const InputDecoration(labelText: 'Catégorie'),
                  ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: slots.map((s) {
                        final enabled = selected.contains(s);
                        return FilterChip(
                          label: Text(s),
                          selected: enabled,
                          onSelected: (v) => setS(() {
                            if (v) {
                              selected.add(s);
                            } else {
                              selected.remove(s);
                            }
                          }),
                        );
                      }).toList(),
                    ),

                    // Sections conditionnelles
                    _weaponSection(),
                    _armorSection(),
                    _packSizeSection(),

                    const SizedBox(height: 12),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          icon: const Icon(Icons.image),
                          label: const Text('Importer une image'),
                          onPressed: () async {
                            final url = await _pickAndUploadImage();
                            if (url != null) {
                              setS(() => imageUrl = url);
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Image importée ✔'),
                                  ),
                                );
                              }
                            }
                          },
                        ),
                        const SizedBox(width: 12),
                        if (imageUrl != null)
                          Expanded(
                            child: Text(
                              imageUrl!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () async {
                        final name = nameCtrl.text.trim();
                        final durability = int.tryParse(duraCtrl.text.trim()) ?? 3;

                        if (name.isEmpty) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(content: Text('Le nom est obligatoire')),
                          );
                          return;
                        }

                        // ← récupère la DEF effective si ARMOR
                        int? effDefense;
                        if (category == 'ARMOR') {
                          if (armorPresetValue != 'Personnalisé…') {
                            effDefense = int.parse(armorPresetValue.split(' ').first);
                          } else {
                            effDefense = int.tryParse(defCustomCtrl.text.trim());
                          }
                          if (effDefense == null) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(content: Text('Pour une armure, indique la DEF.')),
                            );
                            return;
                          }
                        }
                        if (!selected.contains('PACK') && packSize > 1) {
                          packSize = 1;
                        }

                        final payload = <String, dynamic>{
                          'name': name,
                          'description': descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
                          'durability_max': durability, // si tu veux ignorer la durabilité des armures
                          'compatible_slots': selected.toList(),
                          'category': category,
                          'created_by': supa.auth.currentUser!.id,

                          'damage': category == 'WEAPON'
                            ? (() {
                                if (damage != null && damage!.isNotEmpty) return damage;
                                final txt = dmgCustomCtrl.text.trim();
                                return txt.isNotEmpty ? txt : null;
                              }())
                            : null,

                          // ← utilise la DEF effective
                          'defense': category == 'ARMOR'? (defense ?? int.tryParse(defCustomCtrl.text.trim())): null,

                          // flags
                          'two_handed': category == 'WEAPON' ? (twoHanded ?? false) : false,
                          'two_body'  : category == 'ARMOR'  ? (twoBody   ?? false) : false,
                          'pack_size': selected.contains('PACK') ? packSize : 1,
                        };

                        if (imageUrl != null) payload['image_url'] = imageUrl;

                        try {
                          if (existing == null) {
                            await supa.from('items').insert(payload).select();
                          } else {
                            final oldImage = existing['image_url'] as String?;
                            final newImage = imageUrl;

                            await supa.from('items').update(payload).eq('id', existing['id']).select();

                            if (oldImage != null && newImage != null && oldImage != newImage) {
                              try {
                                if (oldImage.contains('/object/public/items/')) {
                                  final path = oldImage.split('/object/public/items/').last;
                                  await supa.storage.from(bucket).remove([path]);
                                }
                              } catch (_) {}
                            }
                          }
                          if (context.mounted) Navigator.pop(sheetCtx);
                          await _refresh();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(existing == null ? 'Item créé' : 'Item mis à jour')),
                            );
                          }
                        } on PostgrestException catch (e) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Postgres: ${e.message}')),
                          );
                        }
                      },
                      child: Text(existing == null ? 'Créer' : 'Enregistrer'),
                    ),
                    const SizedBox(height: 8),
                    if (existing != null &&
                        existing['created_by'] == supa.auth.currentUser!.id)
                      TextButton.icon(
                        icon: const Icon(Icons.delete_outline),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.red,
                        ),
                        onPressed: () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (dCtx) => AlertDialog(
                              title: const Text('Supprimer cet item ?'),
                              content: Text(existing['name'] ?? ''),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(dCtx, false),
                                  child: const Text('Annuler'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(dCtx, true),
                                  child: const Text('Supprimer'),
                                ),
                              ],
                            ),
                          );
                          if (ok != true) return;

                          await supa
                              .from('items')
                              .delete()
                              .eq('id', existing['id']);

                          try {
                            final url = existing['image_url'] as String?;
                            if (url != null &&
                                url.contains('/object/public/items/')) {
                              final path = url
                                  .split('/object/public/items/')
                                  .last;
                              await supa.storage.from(bucket).remove([path]);
                            }
                          } catch (_) {
                            /* non bloquant */
                          }

                          if (context.mounted) Navigator.pop(sheetCtx);
                          await _refresh();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Item supprimé')),
                            );
                          }
                        },
                        label: const Text('Supprimer'),
                      ),
                    if (existing != null &&
                        existing['created_by'] != supa.auth.currentUser!.id)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          'Tu ne peux modifier/supprimer que tes propres items.',
                          style: TextStyle(color: Colors.red),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = supa.auth.currentUser!.id;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestion des items (MJ)'),
        actions: [
          IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createOrEdit(),
        icon: const Icon(Icons.add),
        label: const Text('Ajouter'),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
          ? const Center(child: Text('Aucun item. Ajoute ton premier !'))
          : ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (ctx, i) {
                final it = items[i] as Map<String, dynamic>;
                final isOwner = (it['created_by'] == uid);
                final isWeapon = it['category'] == 'WEAPON';
                final isTwo = (it['two_handed'] as bool?) == true;
                final isTwoBody = it['two_body'] == true;

                final flags = [
                  if (isTwo) '2 mains',
                  if (isTwoBody) '2 corps',
                ].join(' • ');

                // Texte dégâts/défense pour l’aperçu
                String extra = '';
                if (isWeapon && (it['damage'] != null) && '${it['damage']}'.isNotEmpty) {
                  extra = ' • Dégâts: ${it['damage']}';
                } else if (it['category'] == 'ARMOR' && it['defense'] != null) {
                  extra = ' • DEF: ${it['defense']}';
                }
                // Taille PACK
                final comp = (it['compatible_slots'] as List?) ?? const [];
                final rawPackSize = it['pack_size'];
                final int packSize = rawPackSize is int
                    ? rawPackSize
                    : int.tryParse(rawPackSize?.toString() ?? '1') ?? 1;
                final showPackSize = comp.contains('PACK') && packSize > 1;
                final packTxt = showPackSize ? ' • Taille: $packSize cases' : '';

                final twoTxt = isWeapon && isTwo ? ' • (2 mains)' : '';
                

                return ListTile(
                  leading: (it['image_url'] != null)
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.network(
                            it['image_url'],
                            width: 44,
                            height: 44,
                            fit: BoxFit.cover,
                          ),
                        )
                      : const Icon(Icons.inventory_2_outlined),
                  title: Text(it['name'] ?? ''),
                  subtitle: Text(
                  'Cat: ${it['category']} • Durabilité: ${it['durability_max']}'
                  ' • Slots: ${comp.isEmpty ? "-" : comp.join(", ")}'
                  '$extra${flags.isNotEmpty ? ' • $flags' : ''}$packTxt'
                  '${(it['description'] ?? '').toString().isNotEmpty ? '\n${it['description']}' : ''}',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                  trailing: isOwner
                      ? const Icon(Icons.edit)
                      : const Icon(Icons.lock_outline),
                  onTap: () => isOwner
                      ? _createOrEdit(existing: it)
                      : ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Tu ne peux modifier que tes propres items.',
                            ),
                          ),
                        ),
                );
              },
            ),
    );
  }
}
