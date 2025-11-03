import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_config.dart';
import 'items_admin_page.dart';
// utile si tu l’ouvres directement quelque part
import 'package:mausritter_compagnion/character_picker_page.dart' as picker;

// ---------------- Déconnexion quand l’app part en arrière-plan (optionnel) ----------------
class SignOutOnBackground extends StatefulWidget {
  final Widget child;
  const SignOutOnBackground({super.key, required this.child});

  @override
  State<SignOutOnBackground> createState() => _SignOutOnBackgroundState();
}

class _SignOutOnBackgroundState extends State<SignOutOnBackground>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    // Déconnecte quand l’app n’est plus active (optionnel)
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      try {
        await Supabase.instance.client.auth.signOut();
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

// ---------------- AuthGate : force la déconnexion au démarrage ----------------
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _forceSignOutThenShowLogin();
  }

  Future<void> _forceSignOutThenShowLogin() async {
    final supa = Supabase.instance.client;
    try {
      await supa.auth.signOut();
    } catch (_) {
      // non bloquant
    } finally {
      if (mounted) setState(() => _ready = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return const AuthPage(); // toujours l’écran de login après signOut()
  }
}

// ---------------- Gates rôle / navigation post-auth ----------------
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
        return role == 'MJ' ? const ItemsAdminPage() : const picker.CharacterPickerPage();
      },
    );
  }
}

// ---------------- main ----------------
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
    // Thème 100% noir & blanc, police globale 'crayon'
    final base = ThemeData(
      useMaterial3: true,
      fontFamily: 'crayon',
      brightness: Brightness.light,
      scaffoldBackgroundColor: Colors.white,
      colorScheme: const ColorScheme.light(
        primary: Colors.black,
        onPrimary: Colors.white,
        secondary: Colors.black,
        onSecondary: Colors.white,
        surface: Colors.white,
        onSurface: Colors.black,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'crayon',
          fontWeight: FontWeight.w700,
          fontSize: 24,
          color: Colors.black,
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        isDense: true,
        border: OutlineInputBorder(
          borderSide: BorderSide(width: 1.4, color: Colors.black),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(width: 1.4, color: Colors.black),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(width: 1.8, color: Colors.black),
        ),
        labelStyle: TextStyle(
          color: Colors.black,
          fontFamily: 'crayon',
          fontSize: 16,
        ),
        hintStyle: TextStyle(color: Colors.black54, fontFamily: 'crayon'),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: Colors.black,
        selectionColor: Colors.black12,
        selectionHandleColor: Colors.black,
      ),
      iconTheme: const IconThemeData(color: Colors.black),
      dropdownMenuTheme: const DropdownMenuThemeData(
        textStyle: TextStyle(color: Colors.black, fontFamily: 'crayon'),
      ),
    );

    return MaterialApp(
      title: 'Mausritter Companion',
      theme: base,
      // Déconnexion auto en arrière-plan (si tu veux)
      home: const SignOutOnBackground(child: AuthGate()),
      // Sinon : home: const AuthGate(),
    );
  }
}

// ---------------- Auth ----------------
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

  // --- Remember ID (email) ---
  bool rememberId = false;

  @override
  void initState() {
    super.initState();
    _loadRememberedEmail();
  }

  Future<void> _loadRememberedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('remembered_email');
    if (!mounted) return;
    if (saved != null && saved.isNotEmpty) {
      setState(() {
        email.text = saved;
        rememberId = true;
      });
    }
  }

  Future<void> _persistRememberedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    if (rememberId) {
      await prefs.setString('remembered_email', email.text.trim());
    } else {
      await prefs.remove('remembered_email');
    }
  }

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
          await _persistRememberedEmail();
          if (!mounted) return;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const RoleGate()),
          );
          return;
        }

        _toast('✅ Compte créé ! Vérifie ta boîte mail puis connecte-toi.');
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
        await _persistRememberedEmail();

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
    final existing = await supa.from('profiles').select('id').eq('id', uid).maybeSingle();
    if (existing == null) {
      await _upsertProfile(uid, role);
    }
  }

  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 4)));

  @override
  Widget build(BuildContext context) {
    // PAGE CENTRÉE : carte “papier” noir & blanc
    return Scaffold(
      appBar: AppBar(title: const Text('MauseRitter companion')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.black, width: 1.6),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
                  child: SingleChildScrollView(
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // --- IMAGE BANDEAU ICI ---
                        Center(
                          child: Image.asset(
                            'assets/icons/torch-mouse.png',
                            width: MediaQuery.of(context).size.width * 0.7, // auto-responsive (~70%)
                            fit: BoxFit.contain,
                          ),
                        ),
                        const SizedBox(height: 24),
                        // Titre style “écrit à la main”
                        const Text(
                          'Connexion',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'crayon',
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Petite ligne horizontale “crayon”
                        Container(height: 1.6, color: Colors.black),
                        const SizedBox(height: 18),

                        // Email + checkbox "Se souvenir" alignée à droite
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            // Champ email élargi
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: const [
                                  Text('Email'),
                                  SizedBox(height: 6),
                                ],
                              ),
                            ),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Text('Se souvenir', style: TextStyle(fontSize: 11)),
                                SizedBox(height: 6),
                              ],
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              height: 24,
                              width: 24,
                              child: Checkbox(
                                value: null, // placeholder, sera surchargé en StatefulBuilder
                                onChanged: null,
                              ),
                            ),
                          ],
                        ),
                        // On remplace la Checkbox ci-dessus par une version avec état via Builder pour accéder à rememberId
                        Builder(
                          builder: (_) => Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: email,
                                  keyboardType: TextInputType.emailAddress,
                                  textInputAction: TextInputAction.next,
                                  style: const TextStyle(fontSize: 16),
                                  decoration: const InputDecoration(
                                    hintText: 'souris@fromage.fr',
                                  ),
                                  onChanged: (_) {
                                    // si déjà coché, on met à jour la valeur stockée en live
                                    if (rememberId) {
                                      _persistRememberedEmail();
                                    }
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(height: 0), // pour aligner la case
                                  SizedBox(
                                    height: 24,
                                    width: 24,
                                    child: Checkbox(
                                      value: rememberId,
                                      onChanged: (v) async {
                                        setState(() => rememberId = v ?? false);
                                        await _persistRememberedEmail();
                                      },
                                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      side: const BorderSide(color: Colors.black, width: 1.4),
                                      activeColor: Colors.black,
                                      checkColor: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Mot de passe
                        const Text('Mot de passe'),
                        const SizedBox(height: 6),
                        TextField(
                          controller: pass,
                          obscureText: true,
                          textInputAction: TextInputAction.done,
                          style: const TextStyle(fontSize: 16),
                          decoration: const InputDecoration(
                            hintText: '••••••••',
                          ),
                        ),

                        const SizedBox(height: 14),
                        // Mode + Rôle (rôle seulement en signup)
                        Row(
                          children: [
                            const Text('Mode:'),
                            const SizedBox(width: 8),
                            _MonoDropdown<String>(
                              value: mode,
                              items: const [
                                DropdownMenuItem(value: 'login', child: Text('Se connecter')),
                                DropdownMenuItem(value: 'signup', child: Text('Créer un compte')),
                              ],
                              onChanged: (v) => setState(() => mode = v!),
                            ),
                            const Spacer(),
                            if (mode == 'signup') ...[
                              const Text('Rôle:'),
                              const SizedBox(width: 8),
                              _MonoDropdown<String>(
                                value: role,
                                items: const [
                                  DropdownMenuItem(value: 'JOUEUR', child: Text('JOUEUR')),
                                  DropdownMenuItem(value: 'MJ', child: Text('MJ')),
                                ],
                                onChanged: (v) => setState(() => role = v!),
                              ),
                            ],
                          ],
                        ),

                        const SizedBox(height: 18),

                        // Bouton submit : blanc, bord noir (style papier)
                        SizedBox(
                          height: 46,
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.black,
                              backgroundColor: Colors.white,
                              side: const BorderSide(color: Colors.black, width: 1.6),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            onPressed: loading ? null : _submit,
                            child: Text(
                              loading
                                  ? '...'
                                  : (mode == 'signup' ? 'Créer le compte' : 'Connexion'),
                              style: const TextStyle(
                                fontFamily: 'crayon',
                                fontWeight: FontWeight.w800,
                                fontSize: 18,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 12),
                        // Lien de bascule
                        TextButton(
                          onPressed: () => setState(() {
                            mode = (mode == 'login') ? 'signup' : 'login';
                          }),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.black,
                            overlayColor: Colors.black12,
                          ),
                          child: Text(
                            mode == 'login'
                                ? 'Créer un compte'
                                : 'J’ai déjà un compte',
                            style: const TextStyle(
                              fontFamily: 'crayon',
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Dropdown monochrome (fond blanc, texte noir, bordure noire)
class _MonoDropdown<T> extends StatelessWidget {
  final T value;
  final List<DropdownMenuItem<T>> items;
  final void Function(T?) onChanged;
  const _MonoDropdown({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black, width: 1.4),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: DropdownButton<T>(
          value: value,
          items: items,
          onChanged: onChanged,
          underline: const SizedBox.shrink(),
          isDense: true,
          icon: const Icon(Icons.arrow_drop_down, color: Colors.black),
          dropdownColor: Colors.white,
          style: const TextStyle(
            color: Colors.black,
            fontFamily: 'crayon',
            fontSize: 16,
          ),
        ),
      ),
    );
  }
}
