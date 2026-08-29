import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import '../services/vehicle_preference_service.dart';
import '../services/favourites_service.dart';
import 'login_screen.dart';
import 'main_nav_screen.dart';

/// Decides what to show on cold app start based on the persisted Firebase
/// session: signed out -> Login, signed in -> the main app (hydrating the
/// local vehicle-preference and favourites caches from Firestore first).
///
/// After this initial decision, in-app navigation (login success, register
/// success, logout) uses explicit Navigator calls rather than reacting to
/// this stream again, to avoid fighting with pushed routes.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: AuthService.authStateChanges,
      builder: (context, authSnap) {
        if (authSnap.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        final user = authSnap.data;
        if (user == null) return const LoginScreen();

        return FutureBuilder<Map<String, dynamic>?>(
          future: AuthService.getProfile(user.uid),
          builder: (context, profileSnap) {
            if (profileSnap.connectionState == ConnectionState.waiting) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }

            final profile = profileSnap.data;
            if (profile != null) {
              VehiclePreferenceService.instance.hydrate(
                drivesFuel: profile['drivesFuel'] ?? true,
                drivesEV: profile['drivesEV'] ?? true,
              );
              FavouritesService.instance.hydrate(
                fuelIds: Set<String>.from(profile['favouriteFuelIds'] ?? const []),
                evIds: Set<String>.from(profile['favouriteEvIds'] ?? const []),
              );
            }
            return const MainNavScreen();
          },
        );
      },
    );
  }
}
