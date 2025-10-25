// character_picker_page.dart (nouveau fichier)

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'player_sheet_page.dart';

class CharacterPickerPage extends StatefulWidget {
  const CharacterPickerPage({super.key});
  @override
  State<CharacterPickerPage> createState() => _CharacterPickerPageState();
}

class _CharacterPickerPageState extends State<CharacterPickerPage> {
  final supa = Supabase.instance.client;
  bool loading = true;
  List<Map<String, dynamic>> chars = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    final uid = supa.auth.currentUser!.id;

    final data = await supa
        .from('characters')
        .select('id,name,created_at')
        .eq('owner_id', uid)
        .order('created_at', ascending: true);

    setState(() {
      chars = (data as List).cast<Map<String, dynamic>>();
      loading = false;
    });
  }

  Future<void> _createCharacter() async {
    final uid = supa.auth.currentUser!.id;

    // ⚠️ Adapte ce payload à ton schéma réel (not null sur stats/slots, etc.)
    final payload = {
      'owner_id': uid,
      'name': 'Nouvelle souris',
      'background': '',
      'level': 1,
      'xp': 0,
      'str_max': 10, 'str_cur': 10,
      'dex_max': 10, 'dex_cur': 10,
      'wil_max': 10, 'wil_cur': 10,
      'hp_max':  4,  'hp_cur':  4,
      // Si tu es passé en colonnes JSONB (stats/slots), construis les objets par défaut ici.
      // 'stats': {'str':{'max':10,'cur':10}, ...},
      // 'slots': {...},
    };

    final ins = await supa.from('characters').insert(payload).select('id').single();
    final newId = ins['id'] as String;

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PlayerSheetPage(characterId: newId)),
    ).then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Choisir une fiche'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createCharacter,
        icon: const Icon(Icons.add),
        label: const Text('Nouvelle fiche'),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : chars.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Aucune fiche pour le moment.'),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: _createCharacter,
                        icon: const Icon(Icons.add),
                        label: const Text('Créer une fiche'),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: chars.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final c = chars[i];
                    return ListTile(
                      leading: const Icon(Icons.pets),
                      title: Text(c['name'] as String? ?? 'Sans nom'),
                      subtitle: Text((c['id'] as String).substring(0, 8)),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => PlayerSheetPage(characterId: c['id'] as String),
                          ),
                        );
                      },
                    );
                  },
                ),
    );
  }
}
