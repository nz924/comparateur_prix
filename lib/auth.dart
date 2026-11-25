import 'dart:async';  
import 'dart:io';  
import 'dart:math';  
import 'package:camera/camera.dart';  
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';  
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

// ---------- Étape 1 : connexion e-mail / mot de passe ----------  
class LoginPage extends StatefulWidget {  
  final WidgetBuilder suivant; // écran affiché après la réussite  
  const LoginPage({super.key, required this.suivant});

  @override  
  State<LoginPage> createState() => _LoginPageState();  
}

class _LoginPageState extends State<LoginPage> {  
  final _email = TextEditingController();  
  final _mdp = TextEditingController();  
  bool _chargement = false;  
  String? _erreur;

  // À REMPLACER par un appel à votre serveur (FastAPI) ou à Firebase Auth  
  Future<bool> seConnecter(String email, String mdp) async {  
    await Future.delayed(const Duration(milliseconds: 600));  
    return email == 'test@test.com' && mdp == '1234'; // identifiants de démo  
  }

  Future<void> _valider() async {  
    setState(() {  
      _chargement = true;  
      _erreur = null;  
    });  
    final ok = await seConnecter(_email.text.trim(), _mdp.text);  
    if (!mounted) return;  
    setState(() => _chargement = false);  
    if (ok) {  
      Navigator.of(context).push(MaterialPageRoute(  
        builder: (_) => FaceCheckPage(suivant: widget.suivant),  
      ));  
    } else {  
      setState(() => _erreur = 'E-mail ou mot de passe incorrect');  
    }  
  }

  @override  
  Widget build(BuildContext context) {  
    return Scaffold(  
      body: Center(  
        child: SingleChildScrollView(  
          padding: const EdgeInsets.all(24),  
          child: ConstrainedBox(  
            constraints: const BoxConstraints(maxWidth: 400),  
            child: Column(  
              mainAxisSize: MainAxisSize.min,  
              children: [  
                const Icon(Icons.lock_outline, size: 64),  
                const SizedBox(height: 16),  
                const Text('Connexion',  
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),  
                const SizedBox(height: 24),  
                TextField(  
                  controller: _email,  
                  keyboardType: TextInputType.emailAddress,  
                  decoration: const InputDecoration(  
                      labelText: 'E-mail', border: OutlineInputBorder()),  
                ),  
                const SizedBox(height: 12),  
                TextField(  
                  controller: _mdp,  
                  obscureText: true,  
                  decoration: const InputDecoration(  
                      labelText: 'Mot de passe', border: OutlineInputBorder()),  
                ),  
                if (_erreur != null) ...[  
                  const SizedBox(height: 12),  
                  Text(_erreur!, style: const TextStyle(color: Colors.red)),  
                ],  
                const SizedBox(height: 20),  
                SizedBox(  
                  width: double.infinity,  
                  child: FilledButton(  
                    onPressed: _chargement ? null : _valider,  
                    child: _chargement  
                        ? const SizedBox(  
                            height: 20,  
                            width: 20,  
                            child: CircularProgressIndicator(strokeWidth: 2))  
                        : const Text('Se connecter'),  
                  ),  
                ),  
                const SizedBox(height: 8),  
                const Text('Démo : test@test.com / 1234',  
                    style: TextStyle(color: Colors.grey)),  
              ],  
            ),  
          ),  
        ),  
      ),  
    );  
  }  
}

// ---------- Étape 2 : vérification du visage ----------  
class FaceCheckPage extends StatefulWidget {  
  final WidgetBuilder suivant;  
  const FaceCheckPage({super.key, required this.suivant});

  @override  
  State<FaceCheckPage> createState() => _FaceCheckPageState();  
}

class _FaceCheckPageState extends State<FaceCheckPage> {  
  CameraController? _cam;  
  FaceDetector? _detector;  
  Timer? _timer;  
  bool _occupe = false;  
  bool _visageVu = false;  
  String _message = 'Initialisation de la caméra...';  
  String? _erreur;

  // Défi aléatoire : sourire, tourner la tête à gauche ou à droite  
  late final String _defi = ['sourire', 'gauche', 'droite'][Random().nextInt(3)];

  String get _consigne => switch (_defi) {  
        'sourire' => 'Souriez 😀',  
        'gauche' => 'Tournez la tête vers la gauche',  
        _ => 'Tournez la tête vers la droite',  
      };

  @override  
  void initState() {  
    super.initState();  
    if (kIsWeb) {  
      _erreur = 'La vérification faciale n’est pas disponible sur navigateur.';  
      return;  
    }  
    _detector = FaceDetector(  
      options: FaceDetectorOptions(  
        enableClassification: true, // nécessaire pour détecter le sourire  
        performanceMode: FaceDetectorMode.fast,  
      ),  
    );  
    _initCamera();  
  }

  Future<void> _initCamera() async {  
    try {  
      final cams = await availableCameras();  
      final front = cams.firstWhere(  
        (c) => c.lensDirection == CameraLensDirection.front,  
        orElse: () => cams.first,  
      );  
      final cam = CameraController(front, ResolutionPreset.medium,  
          enableAudio: false);  
      await cam.initialize();  
      if (!mounted) return;  
      setState(() {  
        _cam = cam;  
        _message = 'Placez votre visage dans le cercle';  
      });  
      _timer = Timer.periodic(  
          const Duration(milliseconds: 900), (_) => _analyser());  
    } catch (e) {  
      if (!mounted) return;  
      setState(() => _erreur = 'Caméra indisponible : $e');  
    }  
  }

  Future<void> _analyser() async {  
    if (_occupe || _cam == null || !_cam!.value.isInitialized) return;  
    _occupe = true;  
    try {  
      final photo = await _cam!.takePicture();  
      final faces = await _detector!.  
          processImage(InputImage.fromFilePath(photo.path));  
      File(photo.path).delete().ignore(); // on ne garde aucune photo

      if (!mounted) return;  
      if (faces.isEmpty) {  
        setState(() => _message = 'Aucun visage détecté');  
      } else if (faces.length > 1) {  
        setState(() => _message = 'Un seul visage, s\'il vous plaît');  
      } else {  
        final f = faces.first;  
        if (!_visageVu) {  
          _visageVu = true;  
          setState(() => _message = _consigne);  
        } else if (_defiReussi(f)) {  
          _timer?.cancel();  
          setState(() => _message = 'Vérification réussie ✅');  
          await Future.delayed(const Duration(milliseconds: 600));  
          if (!mounted) return;  
          Navigator.of(context).pushAndRemoveUntil(  
            MaterialPageRoute(builder: widget.suivant),  
            (_) => false,  
          );  
        }  
      }  
    } catch (e) {  
      if (mounted) setState(() => _message = 'Erreur d\'analyse : $e');  
    } finally {  
      _occupe = false;  
    }  
  }

  bool _defiReussi(Face f) {  
    switch (_defi) {  
      case 'sourire':  
        return (f.smilingProbability ?? 0) > 0.8;  
      case 'gauche':  
        return (f.headEulerAngleY ?? 0) > 20;  
      default:  
        return (f.headEulerAngleY ?? 0) < -20;  
    }  
  }

  @override  
  void dispose() {  
    _timer?.cancel();  
    _cam?.dispose();  
    _detector?.close();  
    super.dispose();  
  }

  @override  
  Widget build(BuildContext context) {  
    final cam = _cam;  
    return Scaffold(  
      appBar: AppBar(title: const Text('Vérification du visage')),  
      body: Center(  
        child: _erreur != null  
            ? Padding(  
                padding: const EdgeInsets.all(24),  
                child: Column(  
                  mainAxisSize: MainAxisSize.min,  
                  children: [  
                    Text(_erreur!, textAlign: TextAlign.center),  
                    if (kIsWeb) ...[  
                      const SizedBox(height: 16),  
                      FilledButton(  
                        onPressed: () => Navigator.of(context).pushAndRemoveUntil(  
                          MaterialPageRoute(builder: widget.suivant),  
                          (_) => false,  
                        ),  
                        child: const Text('Continuer dans la démo web'),  
                      ),  
                    ],  
                  ],  
                ),  
              )  
            : Column(  
                mainAxisAlignment: MainAxisAlignment.center,  
                children: [  
                  if (cam != null && cam.value.isInitialized)  
                    SizedBox(  
                      width: 280,  
                      height: 280,  
                      child: ClipOval(  
                        child: FittedBox(  
                          fit: BoxFit.cover,  
                          child: SizedBox(  
                            width: cam.value.previewSize!.height,  
                            height: cam.value.previewSize!.width,  
                            child: CameraPreview(cam),  
                          ),  
                        ),  
                      ),  
                    )  
                  else  
                    const CircularProgressIndicator(),  
                  const SizedBox(height: 24),  
                  Text(_message,  
                      textAlign: TextAlign.center,  
                      style: const TextStyle(fontSize: 18)),  
                ],  
              ),  
      ),  
    );  
  }  
}  