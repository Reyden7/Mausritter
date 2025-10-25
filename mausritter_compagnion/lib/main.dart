import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_config.dart';
import 'items_admin_page.dart';
import 'player_sheet_page.dart';

// -------------- Gates --------------

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});
  @override
  Widget build(BuildContext context) {
    final supa = Supabase.instance.client;
    return StreamBuilder<AuthState>(
      stream: supa.auth.onAuthStateChange,
      builder: (ctx, snap) {
        final session = supa.auth.currentSession;
        if (session == null) return const AuthPage();
        return const RoleGate();
      },
    );
  }
}

class RoleGate extends StatefulWidget {
  const RoleGate({super.key});
  @override
  State<RoleGate> createState() => _RoleGateState();
}

class _RoleGateState extends State<RoleGate> {
  final supa = Supabase.instance.client;

  Future<String?> _fetchRole() async {
    final uid = supa.auth.currentUser!.id;
    final r = await supa.from('profiles').select('role').eq('id', uid).maybeSingle();
    return (r?['role'] as String?);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _fetchRole(),
      builder: (ctx, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final role = snap.data ?? 'JOUEUR';
        if (role == 'MJ') {
          return const ItemsAdminPage();
        } else {
          return const PlayerSheetPage();
        }
      },
    );
  }
}

// -------------- Main --------------

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
  );
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mausritter Companion',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xFF445C4F)),
      home: const AuthGate(), // ⬅️ gate d’auth
    );
  }
}

// -------------- Auth --------------

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final email = TextEditingController();
  final pass = TextEditingController();
  String role = 'JOUEUR';   // ou 'MJ'
  String mode = 'login';    // 'login' | 'signup'
  bool loading = false;
  final supa = Supabase.instance.client;

  Future<void> _submit() async {
    setState(() => loading = true);
    try {
      if (mode == 'signup') {
        final res = await supa.auth.signUp(
          email: email.text.trim(),
          password: pass.text.trim(),
        );

        final uid = res.user?.id;
        if (uid != null) {
          await _upsertProfile(uid, role);
          if (!mounted) return;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const RoleGate()),
          );
          return;
        }

        _toast('✅ Compte créé ! Vérifie ta boîte mail et confirme ton compte, puis connecte-toi.');
        await Future.delayed(const Duration(milliseconds: 800));
        if (mounted) setState(() => mode = 'login');
        return;
      } else {
        await supa.auth.signInWithPassword(
          email: email.text.trim(),
          password: pass.text.trim(),
        );

        final uid = supa.auth.currentUser!.id;
        await _ensureProfile(uid, role);

        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const RoleGate()),
        );
      }
    } on AuthException catch (e) {
      _toast('Auth: ${e.message}');
    } on PostgrestException catch (e) {
      _toast('Postgres: ${e.message}');
    } catch (e) {
      _toast('Erreur: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _upsertProfile(String uid, String role) async {
    await supa.from('profiles').upsert({
      'id': uid,
      'display_name': email.text.split('@').first,
      'role': role,
    }, onConflict: 'id').select();
  }

  Future<void> _ensureProfile(String uid, String role) async {
    final existing = await supa
        .from('profiles')
        .select('id')
        .eq('id', uid)
        .maybeSingle();
    if (existing == null) {
      await _upsertProfile(uid, role);
    }
  }

  void _toast(String msg) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 4)),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(title: const Text('Connexion')),
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
            16, 16, 16,
            MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: email,
                decoration: const InputDecoration(labelText: 'Email'),
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: pass,
                decoration: const InputDecoration(labelText: 'Mot de passe'),
                obscureText: true,
                textInputAction: TextInputAction.done,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Mode:'), const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: mode,
                    items: const [
                      DropdownMenuItem(value: 'login',  child: Text('Se connecter')),
                      DropdownMenuItem(value: 'signup', child: Text('Créer un compte')),
                    ],
                    onChanged: (v) => setState(()=> mode = v!),
                  ),
                  const SizedBox(width: 16),
                  if (mode == 'signup') ...[
                    const Text('Rôle:'), const SizedBox(width: 8),
                    DropdownButton<String>(
                      value: role,
                      items: const [
                        DropdownMenuItem(value: 'JOUEUR', child: Text('JOUEUR')),
                        DropdownMenuItem(value: 'MJ',     child: Text('MJ')),
                      ],
                      onChanged: (v) => setState(()=> role = v!),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: loading ? null : _submit,
                child: Text(loading ? '...' : (mode=='signup' ? 'Créer le compte' : 'Connexion')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
