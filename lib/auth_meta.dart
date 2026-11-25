import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Mémorise la dernière session connectée, pour la reconnexion par Face ID.
class Session {
  static const _kNom = 'session_nom';
  static const _kToken = 'session_token';

  static Future<void> save(String nom, String token) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kNom, nom);
    await p.setString(_kToken, token);
  }

  static Future<String?> savedNom() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kNom);
  }

  static Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kNom);
    await p.remove(_kToken);
  }
}

/// Authentification biométrique (Face ID / empreinte) sur téléphone.
/// Renvoie true si l'accès est autorisé.
/// - Sur le web ou si aucune biométrie n'est disponible : on laisse passer (pas de blocage).
/// - Sur téléphone avec biométrie : exige Face ID / empreinte.
Future<bool> biometricGate() async {
  if (kIsWeb) return true; // pas de biométrie sur le web
  final auth = LocalAuthentication();
  try {
    final supported = await auth.isDeviceSupported();
    final canCheck = await auth.canCheckBiometrics;
    if (!supported || !canCheck) return true; // appareil sans biométrie -> on n'empêche pas
    return await auth.authenticate(
      localizedReason: 'Confirmez votre identité pour accéder à l\'app',
      biometricOnly: true,
      persistAcrossBackgrounding: true,
    );
  } catch (_) {
    return true; // en cas d'erreur plateforme, ne pas bloquer
  }
}

/// URL de base de l'API Node.
/// - Web / desktop : http://127.0.0.1:3000
/// - Émulateur Android : http://10.0.2.2:3000
/// - Téléphone réel : http://<IP-de-ton-PC>:3000
const String apiBaseUrl = 'http://127.0.0.1:3000';

// Couleurs façon Meta / Facebook
const metaBlue = Color(0xFF1877F2);
const metaGreen = Color(0xFF42B72A);
const metaBg = Color(0xFFF0F2F5);
const metaMuted = Color(0xFF606770);

class ApiService {
  static Future<Map<String, dynamic>> _post(String path, Map body) async {
    final res = await http.post(
      Uri.parse('$apiBaseUrl$path'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode >= 400) {
      throw Exception(data['error'] ?? 'Erreur (${res.statusCode})');
    }
    return data;
  }

  static Future<Map<String, dynamic>> register(
          String nom, String email, String mdp) =>
      _post('/register', {'nom': nom, 'email': email, 'mot_de_passe': mdp});

  static Future<Map<String, dynamic>> login(String email, String mdp) =>
      _post('/login', {'email': email, 'mot_de_passe': mdp});
}

/// Champ de saisie arrondi, style Meta.
class _MetaField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool obscure;
  final TextInputType? type;
  const _MetaField({
    required this.controller,
    required this.hint,
    this.obscure = false,
    this.type,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: type,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFDDDFE2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: metaBlue, width: 1.5),
        ),
      ),
    );
  }
}

// ------------------- Connexion -------------------
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _email = TextEditingController();
  final _mdp = TextEditingController();
  bool _loading = false;
  String? _erreur;
  String? _savedNom; // dernière session connue (pour Face ID)

  @override
  void initState() {
    super.initState();
    Session.savedNom().then((n) {
      if (mounted) setState(() => _savedNom = n);
    });
  }

  // Reconnexion rapide par Face ID / empreinte, sans retaper le mot de passe.
  Future<void> _loginFaceId() async {
    final nom = _savedNom;
    if (nom == null) return;
    setState(() {
      _loading = true;
      _erreur = null;
    });
    final ok = await biometricGate();
    if (!mounted) return;
    setState(() => _loading = false);
    if (ok) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => HomePage(nom: nom)),
      );
    } else {
      setState(() => _erreur = 'Face ID / empreinte non reconnu.');
    }
  }

  Future<void> _valider() async {
    setState(() {
      _loading = true;
      _erreur = null;
    });
    try {
      final r = await ApiService.login(_email.text.trim(), _mdp.text);
      final nom = r['user']['nom'];
      await Session.save(nom, r['token'] ?? '');
      final okBio = await biometricGate();
      if (!mounted) return;
      if (!okBio) {
        setState(() => _erreur = 'Authentification biométrique annulée.');
        return;
      }
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => HomePage(nom: nom)),
      );
    } catch (e) {
      setState(() => _erreur = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _mdp.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: metaBg,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'comparateur',
                  style: TextStyle(
                    color: metaBlue,
                    fontSize: 44,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -1.5,
                  ),
                ),
                const SizedBox(height: 32),
                _MetaField(
                  controller: _email,
                  hint: 'Adresse e-mail',
                  type: TextInputType.emailAddress,
                ),
                const SizedBox(height: 12),
                _MetaField(
                  controller: _mdp,
                  hint: 'Mot de passe',
                  obscure: true,
                ),
                if (_erreur != null) ...[
                  const SizedBox(height: 12),
                  Text(_erreur!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: metaBlue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _loading ? null : _valider,
                    child: _loading
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('Se connecter',
                            style: TextStyle(
                                fontSize: 17, fontWeight: FontWeight.bold)),
                  ),
                ),
                if (!kIsWeb && _savedNom != null) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: metaBlue,
                        side: const BorderSide(color: metaBlue),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _loading ? null : _loginFaceId,
                      icon: const Icon(Icons.fingerprint),
                      label: Text('Face ID — continuer comme $_savedNom',
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 16),
                SizedBox(
                  height: 48,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: metaGreen,
                      side: const BorderSide(color: metaGreen),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _loading
                        ? null
                        : () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const RegisterPage()),
                            ),
                    child: const Text('Créer un compte',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ------------------- Inscription -------------------
class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});
  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _nom = TextEditingController();
  final _email = TextEditingController();
  final _mdp = TextEditingController();
  bool _loading = false;
  String? _erreur;

  Future<void> _valider() async {
    setState(() {
      _loading = true;
      _erreur = null;
    });
    try {
      final r = await ApiService.register(
          _nom.text.trim(), _email.text.trim(), _mdp.text);
      final nom = r['user']['nom'];
      await Session.save(nom, r['token'] ?? '');
      final okBio = await biometricGate();
      if (!mounted) return;
      if (!okBio) {
        setState(() => _erreur = 'Authentification biométrique annulée.');
        return;
      }
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => HomePage(nom: nom)),
      );
    } catch (e) {
      setState(() => _erreur = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _nom.dispose();
    _email.dispose();
    _mdp.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: metaBg,
      appBar: AppBar(
        backgroundColor: metaBg,
        elevation: 0,
        foregroundColor: metaBlue,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Créer un compte',
                    style: TextStyle(
                        fontSize: 28, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text('C’est rapide et gratuit.',
                    style: TextStyle(color: Colors.black54, fontSize: 15)),
                const SizedBox(height: 24),
                _MetaField(controller: _nom, hint: 'Nom complet'),
                const SizedBox(height: 12),
                _MetaField(
                    controller: _email,
                    hint: 'Adresse e-mail',
                    type: TextInputType.emailAddress),
                const SizedBox(height: 12),
                _MetaField(
                    controller: _mdp,
                    hint: 'Mot de passe (6 car. min.)',
                    obscure: true),
                if (_erreur != null) ...[
                  const SizedBox(height: 12),
                  Text(_erreur!,
                      style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: metaGreen,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _loading ? null : _valider,
                    child: _loading
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text("S'inscrire",
                            style: TextStyle(
                                fontSize: 17, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ------------------- Accueil -------------------
class HomePage extends StatelessWidget {
  final String nom;
  const HomePage({super.key, required this.nom});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: metaBlue,
        foregroundColor: Colors.white,
        title: const Text('Comparateur Tunis'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const LoginPage()),
            ),
          ),
        ],
      ),
      body: Center(
        child: Text('Bienvenue, $nom 👋',
            style: const TextStyle(fontSize: 22)),
      ),
    );
  }
}
