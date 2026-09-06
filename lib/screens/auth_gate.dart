import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import '../services/vehicle_preference_service.dart';
import '../services/favourites_service.dart';
import '../services/location_service.dart';
import 'login_screen.dart';
import 'main_nav_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  String? _profileFutureUid;
  Future<Map<String, dynamic>?>? _profileFuture;

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
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
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
              return const Scaffold(
                  body: Center(child: CircularProgressIndicator()));
            }

            if (_hydratedForUid != user.uid) {
              final profile = profileSnap.data;
              if (profile != null) {
                VehiclePreferenceService.instance.hydrate(
                  drivesFuel: profile['drivesFuel'] ?? true,
                  drivesEV: profile['drivesEV'] ?? true,
                );
                FavouritesService.instance.hydrate(
                  fuelIds:
                      Set<String>.from(profile['favouriteFuelIds'] ?? const []),
                  evIds:
                      Set<String>.from(profile['favouriteEvIds'] ?? const []),
                );
                final lastLat = profile['lastLat'];
                final lastLng = profile['lastLng'];
                if (lastLat is num && lastLng is num) {
                  LocationService.rememberLocation(
                      AppLatLng(lastLat.toDouble(), lastLng.toDouble()));
                }
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
