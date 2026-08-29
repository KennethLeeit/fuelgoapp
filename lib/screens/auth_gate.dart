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
/// Hydration only runs once per signed-in uid, not on every rebuild.
/// StreamBuilder/FutureBuilder `builder` callbacks can re-run for reasons
/// unrelated to auth (e.g. an ancestor widget rebuilding), and re-creating
/// the profile Future / re-calling hydrate() on those would silently
/// overwrite a local change (like a just-toggled vehicle preference or
/// favourite) that hadn't finished writing to Firestore yet — which is
/// what made those changes look like they "didn't save".
///
/// After the initial decision, in-app navigation (login success, register
/// success, logout) uses explicit Navigator calls rather than reacting to
/// this stream again, to avoid fighting with pushed routes.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  // Caches the profile Future per uid so FutureBuilder doesn't restart
  // the fetch (and thus doesn't re-run hydration) on an incidental
  // rebuild that isn't actually a new sign-in.
  String? _profileFutureUid;
  Future<Map<String, dynamic>?>? _profileFuture;

  // Tracks which uid has already been hydrated, so the hydrate() calls
  // themselves only ever run once per sign-in even if this build method
  // runs again while the same (now-completed) future is still current.
  String? _hydratedForUid;

  Future<Map<String, dynamic>?> _profileFor(String uid) {
    if (_profileFutureUid != uid) {
      _profileFutureUid = uid;
      _profileFuture = AuthService.getProfile(uid);
    }
    return _profileFuture!;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: AuthService.authStateChanges,
      builder: (context, authSnap) {
        if (authSnap.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        final user = authSnap.data;
        if (user == null) {
          _profileFutureUid = null;
          _profileFuture = null;
          _hydratedForUid = null;
          return const LoginScreen();
        }

        return FutureBuilder<Map<String, dynamic>?>(
          future: _profileFor(user.uid),
          builder: (context, profileSnap) {
            if (profileSnap.connectionState == ConnectionState.waiting) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }

            if (_hydratedForUid != user.uid) {
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
              _hydratedForUid = user.uid;
            }
            return const MainNavScreen();
          },
        );
      },
    );
  }
}
