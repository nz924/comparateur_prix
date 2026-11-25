import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

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

  /// Liste des restaurants (optionnellement filtrés par `q`).
  static Future<List<dynamic>> restaurants({String q = ''}) async {
    final uri = Uri.parse('$apiBaseUrl/restaurants')
        .replace(queryParameters: {'q': q, 'limit': '100'});
    final res = await http.get(uri);
    if (res.statusCode >= 400) {
      throw Exception('Erreur (${res.statusCode})');
    }
    return jsonDecode(res.body) as List<dynamic>;
  }

  static Future<Map<String, dynamic>> restaurantDetail(int id) async {
    final res = await http.get(Uri.parse('$apiBaseUrl/restaurants/$id'));
    if (res.statusCode >= 400) throw Exception('Erreur (${res.statusCode})');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<List<dynamic>> produitsOf(int id) async {
    final res = await http.get(Uri.parse('$apiBaseUrl/restaurants/$id/produits'));
    if (res.statusCode >= 400) throw Exception('Erreur (${res.statusCode})');
    return jsonDecode(res.body) as List<dynamic>;
  }

  /// Compare le prix d'un produit entre restaurants (trié du moins cher).
  static Future<List<dynamic>> comparer(String produit) async {
    final uri = Uri.parse('$apiBaseUrl/comparer')
        .replace(queryParameters: {'produit': produit});
    final res = await http.get(uri);
    if (res.statusCode >= 400) throw Exception('Erreur (${res.statusCode})');
    return jsonDecode(res.body) as List<dynamic>;
  }
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
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Bienvenue, $nom 👋',
                  style: const TextStyle(fontSize: 22)),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: metaBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const RestaurantsPage()),
                  ),
                  icon: const Icon(Icons.restaurant),
                  label: const Text('Voir les restaurants',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------- Liste des restaurants -------------------
class RestaurantsPage extends StatefulWidget {
  const RestaurantsPage({super.key});
  @override
  State<RestaurantsPage> createState() => _RestaurantsPageState();
}

class _RestaurantsPageState extends State<RestaurantsPage> {
  final _recherche = TextEditingController();
  late Future<List<dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = ApiService.restaurants();
  }

  void _chercher() {
    setState(() {
      _future = ApiService.restaurants(q: _recherche.text.trim());
    });
  }

  @override
  void dispose() {
    _recherche.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: metaBg,
      appBar: AppBar(
        backgroundColor: metaBlue,
        foregroundColor: Colors.white,
        title: const Text('Restaurants'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _recherche,
              onSubmitted: (_) => _chercher(),
              decoration: InputDecoration(
                hintText: 'Rechercher (nom, cuisine)…',
                filled: true,
                fillColor: Colors.white,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: _chercher,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<dynamic>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('Impossible de charger les restaurants.\n'
                          '${snap.error}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.red)),
                    ),
                  );
                }
                final liste = snap.data ?? [];
                if (liste.isEmpty) {
                  return const Center(child: Text('Aucun restaurant trouvé.'));
                }
                return ListView.separated(
                  itemCount: liste.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final r = liste[i] as Map<String, dynamic>;
                    final cuisine = (r['type_cuisine'] ?? '').toString();
                    final ville = (r['ville'] ?? '').toString();
                    final sous = [cuisine, ville]
                        .where((s) => s.isNotEmpty)
                        .join(' · ');
                    return ListTile(
                      tileColor: Colors.white,
                      leading: const CircleAvatar(
                        backgroundColor: metaBg,
                        child: Icon(Icons.restaurant, color: metaBlue),
                      ),
                      title: Text(r['nom']?.toString() ?? '—'),
                      subtitle: sous.isEmpty ? null : Text(sous),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => RestaurantDetailPage(
                            id: (r['id'] as num).toInt(),
                            nom: r['nom']?.toString() ?? '—',
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------- Détail d'un restaurant -------------------
class RestaurantDetailPage extends StatefulWidget {
  final int id;
  final String nom;
  const RestaurantDetailPage({super.key, required this.id, required this.nom});
  @override
  State<RestaurantDetailPage> createState() => _RestaurantDetailPageState();
}

class _RestaurantDetailPageState extends State<RestaurantDetailPage> {
  Map<String, dynamic>? _detail;
  List<dynamic> _produits = [];
  String? _erreur;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    try {
      final d = await ApiService.restaurantDetail(widget.id);
      final p = await ApiService.produitsOf(widget.id);
      if (!mounted) return;
      setState(() {
        _detail = d;
        _produits = p;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erreur = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _itineraire() async {
    final lat = _detail?['latitude'];
    final lon = _detail?['longitude'];
    if (lat == null || lon == null) return;
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lon');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossible d\'ouvrir la carte.')),
        );
      }
    }
  }

  // Affiche la comparaison de prix de ce produit entre restaurants.
  Future<void> _comparer(String produit) async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => FutureBuilder<List<dynamic>>(
        future: ApiService.comparer(produit),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const SizedBox(
                height: 180, child: Center(child: CircularProgressIndicator()));
          }
          final liste = (snap.data ?? []);
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Prix de « $produit »',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text('Du moins cher au plus cher',
                    style: TextStyle(color: metaMuted, fontSize: 13)),
                const SizedBox(height: 12),
                ...liste.asMap().entries.map((e) {
                  final i = e.key;
                  final r = e.value as Map<String, dynamic>;
                  final best = i == 0;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      best ? Icons.emoji_events : Icons.store,
                      color: best ? metaGreen : metaMuted,
                    ),
                    title: Text(r['restaurant']?.toString() ?? '—'),
                    subtitle: (r['ville'] ?? '').toString().isEmpty
                        ? null
                        : Text(r['ville'].toString()),
                    trailing: Text('${r['prix']} DT',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: best ? metaGreen : Colors.black87,
                        )),
                  );
                }),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: metaBg,
      appBar: AppBar(
        backgroundColor: metaBlue,
        foregroundColor: Colors.white,
        title: Text(widget.nom),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _erreur != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_erreur!,
                        style: const TextStyle(color: Colors.red)),
                  ),
                )
              : ListView(
                  children: [
                    // Infos + itinéraire
                    Container(
                      color: Colors.white,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if ((_detail?['type_cuisine'] ?? '').toString().isNotEmpty)
                            Text(_detail!['type_cuisine'].toString(),
                                style: const TextStyle(color: metaMuted)),
                          if ((_detail?['ville'] ?? '').toString().isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Row(children: [
                                const Icon(Icons.place, size: 16, color: metaMuted),
                                const SizedBox(width: 4),
                                Text(_detail!['ville'].toString()),
                              ]),
                            ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: metaBlue,
                                side: const BorderSide(color: metaBlue),
                              ),
                              onPressed: _itineraire,
                              icon: const Icon(Icons.directions),
                              label: const Text('Itinéraire'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: Text('Menu',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                    if (_produits.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('Aucun produit pour ce restaurant.',
                            style: TextStyle(color: metaMuted)),
                      )
                    else
                      ..._produits.map((p) {
                        final prod = p as Map<String, dynamic>;
                        final nom = prod['nom']?.toString() ?? '—';
                        return Container(
                          color: Colors.white,
                          margin: const EdgeInsets.only(bottom: 1),
                          child: ListTile(
                            title: Text(nom),
                            subtitle: (prod['categorie'] ?? '').toString().isEmpty
                                ? null
                                : Text(prod['categorie'].toString()),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('${prod['prix']} DT',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15)),
                                const SizedBox(width: 6),
                                IconButton(
                                  tooltip: 'Comparer les prix',
                                  icon: const Icon(Icons.compare_arrows,
                                      color: metaBlue),
                                  onPressed: () => _comparer(nom),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    const SizedBox(height: 20),
                  ],
                ),
    );
  }
}
