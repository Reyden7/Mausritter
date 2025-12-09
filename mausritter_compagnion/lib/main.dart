import 'dart:async'; // 👈 POUR StreamSubscription
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:app_links/app_links.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_config.dart';
import 'mj_dashboard_page.dart';
import 'items_admin_page.dart';

import 'package:mausritter_compagnion/character_picker_page.dart' as picker;

final navigatorKey = GlobalKey<NavigatorState>();

// ---------------- Déconnexion quand l’app part en arrière-plan (optionnel) ----------------
class SignOutOnBackground extends StatefulWidget {
  final Widget child;
  const SignOutOnBackground({super.key, required this.child});

  

  @override
  State<SignOutOnBackground> createState() => _SignOutOnBackgroundState();

  
}

class _SignOutOnBackgroundState extends State<SignOutOnBackground>
    with WidgetsBindingObserver {

  Uri? lastDeepLink; // 👈 on stocke le lien reçu (si reset password)

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    // 🔥 Si on voit "type=recovery" dans l’URL → ne PAS déconnecter
    final isPasswordRecovery =
        lastDeepLink?.toString().contains("recovery") ?? false;

    if (isPasswordRecovery) {
      return; // ✔ on ne casse pas le reset password
    }

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      try {
        await Supabase.instance.client.auth.signOut();
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
// ---------------- AuthGate : ne force plus le signOut au démarrage ----------------
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  Widget build(BuildContext context) {
    final supa = Supabase.instance.client;
    // Si une session existe déjà → on envoie vers RoleGate, sinon vers login
    if (supa.auth.currentUser != null) {
      return const RoleGate();
    }
    return const AuthPage();
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
    final r = await supa
        .from('profiles')
        .select('role')
        .eq('id', uid)
        .maybeSingle();
    return (r?['role'] as String?);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _fetchRole(),
      builder: (ctx, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        final role = snap.data ?? 'JOUEUR';
        return role == 'MJ'
            ? const MjDashboardPage()
            : const picker.CharacterPickerPage();
      },
    );
  }
}

// ---------------- main ----------------
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.implicit, // 👈 IMPORTANT
      // detectSessionInUri reste à true par défaut : Supabase gère les deep links
    ),
  );

  runApp(const App());
}


// ---------------- App avec listener passwordRecovery ----------------
class App extends StatefulWidget {
  const App({super.key});
  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  late final StreamSubscription<AuthState> _authSub;
  

  @override
  void initState() {
    super.initState();

    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final event = data.event;

      if (event == AuthChangeEvent.passwordRecovery) {
        // 👉 On est bien dans le flow de reset
        final ctx = navigatorKey.currentContext;
        if (ctx != null) {
          Navigator.of(ctx).push(
            MaterialPageRoute(builder: (_) => const ResetPasswordPage()),
          );
        }
      }
    });
  }

  
  @override
  void dispose() {
    _authSub.cancel();
    super.dispose();
  }

  
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
      navigatorKey: navigatorKey,
      home: const SignOutOnBackground(child: AuthGate()),
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
  final mjCodeCtrl = TextEditingController(); // ← Code MJ pour les JOUEURS

  String role = 'JOUEUR'; // ou 'MJ'
  String mode = 'login'; // 'login' | 'signup'
  bool loading = false;
  final supa = Supabase.instance.client;

  // --- Remember ID (email) ---
  bool rememberId = false;
  late final StreamSubscription<AuthState> _authSub;
  @override
  void initState() {
    super.initState();
    _loadRememberedEmail();

    _authSub = supa.auth.onAuthStateChange.listen((data) {
      final event = data.event;

      if (event == AuthChangeEvent.passwordRecovery) {
        // Lien de reset cliqué → on affiche la page de nouveau mot de passe
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const ResetPasswordPage(),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    email.dispose();
    pass.dispose();
    mjCodeCtrl.dispose();
    _authSub.cancel(); 
    super.dispose();
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

  Future<void> _resetPassword() async {
    final mail = email.text.trim();
    if (mail.isEmpty) {
      _toast('Tape ton email d’abord.');
      return;
    }

    try {
      await supa.auth.resetPasswordForEmail(
        mail,
        redirectTo: 'mausritter://auth/callback', // 🔗 deep link vers l’app
      );

      _toast(
        'Si un compte existe pour cet email, un lien de réinitialisation vient de t’être envoyé.',
      );
    } on AuthException catch (e) {
      _toast('Auth: ${e.message}');
    } catch (e) {
      _toast('Erreur: $e');
    }
  }

  Future<void> _submit() async {
    // 🔐 En signup + JOUEUR : on impose le code MJ
    if (mode == 'signup' &&
        role == 'JOUEUR' &&
        mjCodeCtrl.text.trim().isEmpty) {
      _toast('Merci de renseigner le code de ton MJ.');
      return;
    }

    setState(() => loading = true);
    try {
      if (mode == 'signup') {
        // --- INSCRIPTION ---
        await supa.auth.signUp(
          email: email.text.trim(),
          password: pass.text.trim(),
        );

        _toast(
            '✅ Compte créé ! Va confirmer ton email puis reviens te connecter.');
        await Future.delayed(const Duration(milliseconds: 800));
        if (!mounted) return;

        // On force le retour en mode "login"
        setState(() => mode = 'login');

        // Par sécurité : aucune session active côté app
        await supa.auth.signOut();

        return;
      }

      // --- LOGIN ---
      final authRes = await supa.auth.signInWithPassword(
        email: email.text.trim(),
        password: pass.text.trim(),
      );

      final user = authRes.user;

      // 🔒 BLOCAGE SI EMAIL NON CONFIRMÉ
      if (user == null || user.emailConfirmedAt == null) {
        await supa.auth.signOut();
        _toast('Tu dois d’abord confirmer ton email avant de te connecter.');
        return;
      }

      final uid = user.id;

      // Profil + rôle
      await _ensureProfile(uid, role);

      // Rattachement MJ / JOUEUR au premier login
      if (role == 'MJ') {
        await supa.rpc('become_mj');
      } else if (role == 'JOUEUR' && mjCodeCtrl.text.trim().isNotEmpty) {
        await supa.rpc('attach_joueur_to_mj', params: {
          'mj_code_in': mjCodeCtrl.text.trim(),
        });
      }

      await _persistRememberedEmail();

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const RoleGate()),
      );
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
    final existing =
        await supa.from('profiles').select('id').eq('id', uid).maybeSingle();
    if (existing == null) {
      await _upsertProfile(uid, role);
    }
  }

  void _toast(String msg) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 4)));

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
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.black, width: 1.6),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
                  child: SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Image.asset(
                            'assets/icons/torch-mouse.png',
                            width: MediaQuery.of(context).size.width * 0.7,
                            fit: BoxFit.contain,
                          ),
                        ),
                        const SizedBox(height: 24),
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
                        Container(height: 1.6, color: Colors.black),
                        const SizedBox(height: 18),

                        // Email + checkbox "Se souvenir"
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
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
                                Text('Se souvenir',
                                    style: TextStyle(fontSize: 11)),
                                SizedBox(height: 6),
                              ],
                            ),
                            const SizedBox(width: 8),
                            
                          ],
                        ),
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
                                  const SizedBox(height: 0),
                                  SizedBox(
                                    height: 24,
                                    width: 24,
                                    child: Checkbox(
                                      value: rememberId,
                                      onChanged: (v) async {
                                        setState(
                                            () => rememberId = v ?? false);
                                        await _persistRememberedEmail();
                                      },
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      side: const BorderSide(
                                          color: Colors.black, width: 1.4),
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

                        // bouton "mot de passe oublié ?"
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: loading ? null : _resetPassword,
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.black,
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(0, 0),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text(
                              'Mot de passe oublié ?',
                              style: TextStyle(
                                fontFamily: 'crayon',
                                fontSize: 12,
                                decoration: TextDecoration.underline,
                              ),
                            ),
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
                                DropdownMenuItem(
                                    value: 'login',
                                    child: Text('Se connecter')),
                                DropdownMenuItem(
                                    value: 'signup',
                                    child: Text('Créer un compte')),
                              ],
                              onChanged: (v) =>
                                  setState(() => mode = v!),
                            ),
                            const Spacer(),
                            if (mode == 'signup') ...[
                              const Text('Rôle:'),
                              const SizedBox(width: 8),
                              _MonoDropdown<String>(
                                value: role,
                                items: const [
                                  DropdownMenuItem(
                                      value: 'JOUEUR',
                                      child: Text('JOUEUR')),
                                  DropdownMenuItem(
                                      value: 'MJ',
                                      child: Text('MJ')),
                                ],
                                onChanged: (v) {
                                  setState(() {
                                    role = v!;
                                    if (role == 'MJ') {
                                      mjCodeCtrl.clear();
                                    }
                                  });
                                },
                              ),
                            ],
                          ],
                        ),

                        if (mode == 'signup' && role == 'JOUEUR') ...[
                          const SizedBox(height: 14),
                          const Text('Code MJ'),
                          const SizedBox(height: 6),
                          TextField(
                            controller: mjCodeCtrl,
                            textInputAction: TextInputAction.next,
                            style: const TextStyle(fontSize: 16),
                            decoration: const InputDecoration(
                              hintText: 'Ex : 8B7Q',
                            ),
                          ),
                        ],

                        const SizedBox(height: 18),

                        SizedBox(
                          height: 46,
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.black,
                              backgroundColor: Colors.white,
                              side: const BorderSide(
                                  color: Colors.black, width: 1.6),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                            ),
                            onPressed: loading ? null : _submit,
                            child: Text(
                              loading
                                  ? '...'
                                  : (mode == 'signup'
                                      ? 'Créer le compte'
                                      : 'Connexion'),
                              style: const TextStyle(
                                fontFamily: 'crayon',
                                fontWeight: FontWeight.w800,
                                fontSize: 18,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 12),
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

// ---------------- Page de reset de mot de passe ----------------
class ResetPasswordPage extends StatefulWidget {
  const ResetPasswordPage({super.key});

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final _pass1 = TextEditingController();
  final _pass2 = TextEditingController();
  bool _loading = false;
  final supa = Supabase.instance.client;

  @override
  void dispose() {
    _pass1.dispose();
    _pass2.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _changePassword() async {
    final p1 = _pass1.text.trim();
    final p2 = _pass2.text.trim();

    if (p1.isEmpty || p2.isEmpty) {
      _toast("Tape deux fois le nouveau mot de passe.");
      return;
    }
    if (p1 != p2) {
      _toast("Les deux mots de passe ne correspondent pas.");
      return;
    }
    if (p1.length < 6) {
      _toast("Mot de passe trop court (min 6 caractères).");
      return;
    }

    setState(() => _loading = true);
  try {
    // Met à jour le mot de passe pour la session "recovery"
    await supa.auth.updateUser(UserAttributes(password: p1));

    // On coupe la session de recovery par sécurité
    await supa.auth.signOut();

    if (!mounted) return;

    _toast(
      "Mot de passe mis à jour ✔ Connecte-toi avec ton nouveau mot de passe.",
    );

    // On revient proprement sur l'écran de login
    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthPage()),
      (route) => false,
    );
  } on AuthException catch (e) {
    _toast('Auth: ${e.message}');
  } catch (e) {
    _toast('Erreur: $e');
  } finally {
    if (mounted) setState(() => _loading = false);
  }
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nouveau mot de passe')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Choisis ton nouveau mot de passe',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _pass1,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Nouveau mot de passe',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _pass2,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Confirme le mot de passe',
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 46,
                child: OutlinedButton(
                  onPressed: _loading ? null : _changePassword,
                  child: Text(_loading ? '...' : 'Valider'),
                ),
              ),
            ],
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
