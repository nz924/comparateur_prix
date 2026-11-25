import 'dart:async';  
import 'dart:convert';  
import 'package:flutter/foundation.dart';  
import 'package:flutter/material.dart';  
import 'package:http/http.dart' as http;

// ---------- Adresse du serveur ----------  
// Chrome / Windows : localhost  
// Émulateur Android : 10.0.2.2  
// Vrai téléphone : mettez l'IP de votre PC, par exemple 192.168.1.20  
const String ipTelephone = ''; // laissez vide sauf test sur vrai téléphone

String get baseUrl {  
  if (ipTelephone.isNotEmpty) return 'http://$ipTelephone:8000';  
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {  
    return 'http://10.0.2.2:8000';  
  }  
  return 'http://localhost:8000';  
}

// ---------- Modèle ----------  
class Offre {  
  final String restaurant;  
  final String quartier;  
  final String produit;  
  final String? taille;  
  final double prix;  
  final String devise;  
  final String? dateMaj;

  Offre({  
    required this.restaurant,  
    required this.quartier,  
    required this.produit,  
    this.taille,  
    required this.prix,  
    required this.devise,  
    this.dateMaj,  
  });

  factory Offre.fromJson(Map<String, dynamic> j) => Offre(  
        restaurant: j['nom'] ?? '',  
        quartier: j['quartier'] ?? '',  
        produit: j['produit'] ?? '',  
        taille: j['taille'],  
        prix: (j['prix'] as num).toDouble(),  
        devise: j['devise'] ?? 'TND',  
        dateMaj: j['date_maj'],  
      );  
}

// ---------- Appel au serveur ----------  
Future<List<Offre>> chercher(String q) async {  
  final uri = Uri.parse('$baseUrl/recherche').replace(queryParameters: {'q': q});  
  final r = await http.get(uri).timeout(const Duration(seconds: 15));  
  if (r.statusCode != 200) {  
    throw Exception('Erreur serveur (${r.statusCode})');  
  }  
  final data = jsonDecode(utf8.decode(r.bodyBytes));  
  final liste = (data['resultats'] as List);  
  return liste.map((e) => Offre.fromJson(e)).toList();  
}

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {  
  const MyApp({super.key});

  @override  
  Widget build(BuildContext context) {  
    return MaterialApp(  
      title: 'Meilleur prix Tunis',  
      debugShowCheckedModeBanner: false,  
      theme: ThemeData(colorSchemeSeed: Colors.orange, useMaterial3: true),  
      home: const PageRecherche(),  
    );  
  }  
}

class PageRecherche extends StatefulWidget {  
  const PageRecherche({super.key});

  @override  
  State<PageRecherche> createState() => _PageRechercheState();  
}

class _PageRechercheState extends State<PageRecherche> {  
  Timer? _debounce;  
  bool chargement = false;  
  String? erreur;  
  String derniereRecherche = '';  
  List<Offre> resultats = [];

  void onChange(String v) {  
    _debounce?.cancel();  
    // attend 500 ms après la dernière touche pour ne pas surcharger le serveur  
    _debounce = Timer(const Duration(milliseconds: 500), () => lancer(v));  
  }

  Future<void> lancer(String v) async {  
    final q = v.trim();  
    if (q.isEmpty) {  
      setState(() {  
        resultats = [];  
        erreur = null;  
        derniereRecherche = '';  
      });  
      return;  
    }  
    setState(() {  
      chargement = true;  
      erreur = null;  
      derniereRecherche = q;  
    });  
    try {  
      final res = await chercher(q);  
      if (!mounted || q != derniereRecherche) return;  
      setState(() => resultats = res);  
    } catch (e) {  
      if (!mounted) return;  
      setState(() {  
        resultats = [];  
        erreur = 'Impossible de joindre le serveur.\n($e)';  
      });  
    } finally {  
      if (mounted) setState(() => chargement = false);  
    }  
  }

  @override  
  void dispose() {  
    _debounce?.cancel();  
    super.dispose();  
  }

  @override  
  Widget build(BuildContext context) {  
    return Scaffold(  
      appBar: AppBar(title: const Text('Meilleur prix à Tunis')),  
      body: Padding(  
        padding: const EdgeInsets.all(16),  
        child: Column(  
          children: [  
            TextField(  
              autofocus: true,  
              decoration: const InputDecoration(  
                hintText: 'Tapez : pizza, sandwich, tacos...',  
                prefixIcon: Icon(Icons.search),  
                border: OutlineInputBorder(),  
              ),  
              onChanged: onChange,  
              onSubmitted: lancer,  
            ),  
            const SizedBox(height: 16),  
            if (chargement) const LinearProgressIndicator(),  
            Expanded(child: _contenu()),  
          ],  
        ),  
      ),  
    );  
  }

  Widget _contenu() {  
    if (erreur != null) {  
      return Center(  
        child: Text(erreur!, textAlign: TextAlign.center,  
            style: const TextStyle(color: Colors.red)),  
      );  
    }  
    if (derniereRecherche.isEmpty) {  
      return const Center(child: Text('Tapez un plat pour comparer les prix'));  
    }  
    if (!chargement && resultats.isEmpty) {  
      return const Center(child: Text('Aucun résultat'));  
    }  
    return ListView.builder(  
      itemCount: resultats.length,  
      itemBuilder: (context, i) {  
        final o = resultats[i];  
        final meilleur = i == 0;  
        final details = [  
          o.produit,  
          if (o.taille != null && o.taille!.isNotEmpty) o.taille!,  
          if (o.dateMaj != null) 'maj ${o.dateMaj}',  
        ].join('  •  ');  
        return Card(  
          color: meilleur ? Colors.green.shade100 : null,  
          child: ListTile(  
            leading: Icon(meilleur ? Icons.emoji_events : Icons.restaurant),  
            title: Text('${o.restaurant} (${o.quartier})'),  
            subtitle: Text(meilleur ? '$details\nMeilleur prix' : details),  
            isThreeLine: meilleur,  
            trailing: Text(  
              '${o.prix.toStringAsFixed(1)} ${o.devise}',  
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),  
            ),  
          ),  
        );  
      },  
    );  
  }  
}  