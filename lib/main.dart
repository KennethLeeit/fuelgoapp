import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'theme/app_theme.dart';
import 'screens/auth_gate.dart';
import 'services/favourites_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FavouritesService.instance.initialize();
  runApp(const _AppBootstrap());
}

/// Initializes Firebase before showing the real app. If Firebase hasn't
/// been configured yet (see FIREBASE_SETUP.md — you need to run
/// `flutterfire configure` once, which generates firebase_options.dart),
/// this shows a clear setup message instead of a raw crash.
class _AppBootstrap extends StatefulWidget {
  const _AppBootstrap();
  @override
  State<_AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<_AppBootstrap> {
  late Future<FirebaseApp> _initFuture;

  @override
  void initState() {
    super.initState();
    _initFuture =
        Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FuelGo',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: FutureBuilder<FirebaseApp>(
        future: _initFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
                body: Center(child: CircularProgressIndicator()));
          }
          if (snapshot.hasError) {
            return Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline,
                          size: 48, color: Colors.red),
                      const SizedBox(height: 16),
                      const Text('Firebase is not set up yet',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center),
                      const SizedBox(height: 8),
                      const Text(
                        'Run "flutterfire configure" in this project to connect a Firebase project, then rebuild the app. See FIREBASE_SETUP.md for step-by-step instructions.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 12),
                      Text('${snapshot.error}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 11, color: Colors.grey)),
                    ],
                  ),
                ),
              ),
            );
          }
          return const AuthGate();
        },
      ),
    );
  }
}
