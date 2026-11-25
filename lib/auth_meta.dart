import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// URL de base de l'API Node.
/// - Web / desktop : http://127.0.0.1:3000
/// - Émulateur Android : http://10.0.2.2:3000
/// - Téléphone réel : http://<IP-de-ton-PC>:3000
const String apiBaseUrl = 'http://127.0.0.1:3000';

// Couleurs façon Meta / Facebook
const metaBlue = Color(0xFF1877F2);
const metaGreen = Color(0xFF42B72A);
const metaBg = Color(0xFFF0F2F5);

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

  Future<void> _valider() async {
    setState(() {
      _loading = true;
      _erreur = null;
    });
    try {
      final r = await ApiService.login(_email.text.trim(), _mdp.text);
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => HomePage(nom: r['user']['nom'])),
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
                const SizedBox(height: 24),
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
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => HomePage(nom: r['user']['nom'])),
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
