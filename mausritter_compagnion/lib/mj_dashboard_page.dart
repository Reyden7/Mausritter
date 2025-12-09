import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'items_admin_page.dart';
import 'package:flutter/services.dart';

class MjDashboardPage extends StatefulWidget {
  const MjDashboardPage({super.key});

  @override
  State<MjDashboardPage> createState() => _MjDashboardPageState();
}

class _MjDashboardPageState extends State<MjDashboardPage> {
  final supa = Supabase.instance.client;
  bool loading = true;
  String? mjCode;

  @override
  void initState() {
    super.initState();
    _loadMjCode();
  }

  Future<void> _loadMjCode() async {
    final uid = supa.auth.currentUser!.id;

    final data = await supa
        .from('profiles')
        .select('mj_code')
        .eq('id', uid)
        .maybeSingle();

    setState(() {
      mjCode = data?['mj_code'] as String?;
      loading = false;
    });
  }

  Future<void> _copyCode() async {
    if (mjCode == null) return;
    await Clipboard.setData(ClipboardData(text: mjCode!));

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Code MJ copié dans le presse-papier")),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Espace MJ"),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.black, width: 1.8),
                borderRadius: BorderRadius.circular(12),
                color: Colors.white,
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "Ton code MJ",
                      style: TextStyle(
                        fontFamily: 'crayon',
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 18),

                    Container(
                      padding:
                          const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.black, width: 1.4),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        mjCode ?? "Aucun code (bug ?)",
                        style: const TextStyle(
                          fontFamily: 'crayon',
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),

                    const SizedBox(height: 20),

                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.copy),
                        label: const Text(
                          "Copier le code",
                          style: TextStyle(
                            fontFamily: 'crayon',
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.black, width: 1.6),
                          foregroundColor: Colors.black,
                          backgroundColor: Colors.white,
                        ),
                        onPressed: _copyCode,
                      ),
                    ),

                    const SizedBox(height: 30),

                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: FilledButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ItemsAdminPage(),
                            ),
                          );
                        },
                        child: const Text(
                          "Gérer les items",
                          style: TextStyle(
                            fontFamily: 'crayon',
                            fontWeight: FontWeight.w700,
                            fontSize: 18,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    const Text(
                      "Partage ce code avec tes joueurs :\nils devront le saisir en créant leur compte.",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontFamily: 'crayon'),
                    )
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
