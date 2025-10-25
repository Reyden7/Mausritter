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

  // Catégories autorisées (alignées avec le check DB)
  static const categories = ['WEAPON', 'ARMOR', 'AMMO', 'LIGHT', 'RATION', 'OTHER'];
  // Slots compatibles
  static const slots = ['PAW_MAIN', 'PAW_OFF', 'BODY', 'PACK'];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => loading = true);
    final data = await supa.from('items').select().order('created_at');
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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Action annulée')),
          );
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
            SnackBar(content: Text(source == ImageSource.camera
                ? 'Aucune photo prise'
                : 'Aucune image sélectionnée')),
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

      await supa.storage.from(bucket).uploadBinary(
        path,
        Uint8List.fromList(bytes),
        fileOptions: FileOptions(
          upsert: true,
          contentType: 'image/$ext',
        ),
      );

      // Bucket public → URL directe
      final url = supa.storage.from(bucket).getPublicUrl(path);
      return url;
    } on StorageException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Storage: ${e.message}')),
        );
      }
      return null;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur upload: $e')),
        );
      }
      return null;
    }
  }

  Future<void> _createOrEdit({Map<String, dynamic>? existing}) async {
    final nameCtrl = TextEditingController(text: existing?['name'] ?? '');
    final duraCtrl = TextEditingController(text: (existing?['durability_max'] ?? 3).toString());
    String category = existing?['category'] ?? 'OTHER';
    final selected = <String>{...(existing?['compatible_slots']?.cast<String>() ?? <String>[])};
    String? imageUrl = existing?['image_url'];

    await showModalBottomSheet(
      isScrollControlled: true,
      context: context,
      builder: (sheetCtx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16, right: 16, top: 16,
            bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 16,
          ),
          child: StatefulBuilder(
            builder: (ctx, setS) {
              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(existing == null ? 'Nouvel item' : 'Modifier l’item',
                        style: Theme.of(ctx).textTheme.titleLarge),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(labelText: 'Nom'),
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: duraCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Durabilité max (ex: 3)'),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: category,
                      items: categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                      onChanged: (v) => setS(() => category = v!),
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
                                const SnackBar(content: Text('Image importée ✔')),
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
                        final payload = <String, dynamic>{
                          'name': name,
                          'durability_max': durability,
                          'compatible_slots': selected.toList(),
                          'category': category,
                          'created_by': supa.auth.currentUser!.id,
                        };
                        // Très important : ne pas envoyer image_url si on n'a pas choisi d'image
                        if (imageUrl != null) {
                          payload['image_url'] = imageUrl;
                        }
                        try {
                          if (existing == null) {
                            // CREATION
                            await supa.from('items').insert(payload).select();
                          } else {
                            // MODIFICATION
                            final oldImage = existing['image_url'] as String?; // ancienne URL en BDD
                            final newImage = imageUrl; // peut être null si l'utilisateur n'a pas re-sélectionné une image

                            await supa.from('items').update(payload).eq('id', existing['id']).select();

                            // Si l'image a réellement changé : supprime l'ancienne du Storage
                            if (oldImage != null && newImage != null && oldImage != newImage) {
                              try {
                                if (oldImage.contains('/object/public/items/')) {
                                  final path = oldImage.split('/object/public/items/').last;
                                  await supa.storage.from(bucket).remove([path]);
                                }
                              } catch (_) {
                                // non bloquant
                              }
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
                    if (existing != null && existing['created_by'] == supa.auth.currentUser!.id)
                      TextButton.icon(
                        icon: const Icon(Icons.delete_outline),
                        style: TextButton.styleFrom(foregroundColor: Colors.red),
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

                          // Supprime d'abord l'item
                          await supa.from('items').delete().eq('id', existing['id']);

                          // (Optionnel) supprime le fichier Storage associé
                          try {
                            final url = existing['image_url'] as String?;
                            if (url != null && url.contains('/object/public/items/')) {
                              final path = url.split('/object/public/items/').last;
                              await supa.storage.from(bucket).remove([path]);
                            }
                          } catch (_) {
                            // non bloquant si l'image reste
                          }

                          if (context.mounted) Navigator.pop(sheetCtx); // ferme le bottom sheet
                          await _refresh();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Item supprimé')),
                            );
                          }
                        },
                        label: const Text('Supprimer'),
                      ),
                    if (existing != null && existing['created_by'] != supa.auth.currentUser!.id)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text('Tu ne peux modifier/supprimer que tes propres items.',
                            style: TextStyle(color: Colors.red)),
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
                        'Cat: ${it['category']} • Durabilité: ${it['durability_max']} • Slots: ${(it['compatible_slots'] as List?)?.join(", ") ?? "-"}',
                      ),
                      trailing: isOwner ? const Icon(Icons.edit) : const Icon(Icons.lock_outline),
                      onTap: () => isOwner
                          ? _createOrEdit(existing: it)
                          : ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Tu ne peux modifier que tes propres items.')),
                            ),
                    );
                  },
                ),
    );
  }
}
