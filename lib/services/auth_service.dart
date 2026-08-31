import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Wraps Firebase Authentication (email/password) and Firestore so account
/// info is persisted for real, not just in-memory mock data.
///
/// Requires a Firebase project connected via `flutterfire configure` — see
/// FIREBASE_SETUP.md. Everything in this file is real, free-tier Firebase
/// (Spark plan): email/password auth, password reset emails, and Firestore
/// document storage.
class AuthService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static User? get currentUser => _auth.currentUser;
  static Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Creates the Firebase Auth account, then tries to save a matching
  /// Firestore profile document at users/{uid}. The Auth account is the
  /// part that matters most, so a Firestore failure (e.g. Firestore
  /// database not created yet in the console, or security rules blocking
  /// the write) does NOT fail the whole registration — it's caught and
  /// logged instead, so users can still sign in even if the profile save
  /// didn't go through. Check FIREBASE_SETUP.md if you see profile-save
  /// warnings in the console.
  static Future<User> register({
    required String fullName,
    required String email,
    required String password,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(email: email.trim(), password: password);
    final user = credential.user!;

    try {
      await user.updateDisplayName(fullName.trim());
    } catch (_) {
      // Non-critical — the account still works without a display name set.
    }

    try {
      await _db.collection('users').doc(user.uid).set({
        'fullName': fullName.trim(),
        'email': email.trim(),
        'createdAt': FieldValue.serverTimestamp(),
        'drivesFuel': true,
        'drivesEV': true,
        'favouriteFuelIds': <String>[],
        'favouriteEvIds': <String>[],
      });
    } catch (e) {
      // ignore: avoid_print
      print('[AuthService] Could not save Firestore profile for ${user.uid}: $e');
    }

    return user;
  }

  static Future<User> signIn({required String email, required String password}) async {
    final credential = await _auth.signInWithEmailAndPassword(email: email.trim(), password: password);
    return credential.user!;
  }

  static Future<void> sendPasswordResetEmail(String email) {
    return _auth.sendPasswordResetEmail(email: email.trim());
  }

  static Future<void> signOut() => _auth.signOut();

  static Future<Map<String, dynamic>?> getProfile(String uid) async {
    try {
      final doc = await _db.collection('users').doc(uid).get();
      return doc.data();
    } catch (e) {
      // ignore: avoid_print
      print('[AuthService] Could not read Firestore profile for $uid: $e');
      return null;
    }
  }

  static Stream<DocumentSnapshot<Map<String, dynamic>>> profileStream(String uid) {
    return _db.collection('users').doc(uid).snapshots();
  }

  /// Returns null on success, or a user-facing error message describing
  /// why the save failed (e.g. Firestore not set up, permission denied,
  /// no network) — callers should show this instead of a generic message,
  /// since a generic "check your connection" message looks identical
  /// whether the real cause is a network blip or a Firestore project
  /// that was never fully set up (see FIREBASE_SETUP.md).
  static Future<String?> updateVehiclePreference({required bool drivesFuel, required bool drivesEV}) async {
    final uid = currentUser?.uid;
    if (uid == null) return 'You need to be signed in to do that.';
    try {
      await _db.collection('users').doc(uid).set(
        {'drivesFuel': drivesFuel, 'drivesEV': drivesEV},
        SetOptions(merge: true),
      );
      return null;
    } catch (e) {
      // ignore: avoid_print
      print('[AuthService] Could not save vehicle preference: $e');
      return friendlyError(e);
    }
  }

  /// Changes the signed-in user's password. Firebase requires a "recent"
  /// login for this, so we first re-authenticate with [currentPassword] —
  /// this also doubles as verifying the user actually knows it. Throws a
  /// [FirebaseAuthException] on failure (wrong current password, weak new
  /// password, etc.) — callers should catch it and check `error.code`
  /// (e.g. 'wrong-password' / 'invalid-credential' means the current
  /// password entered was wrong) or fall back to `AuthService.friendlyError`.
  static Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) {
      throw FirebaseAuthException(
        code: 'no-current-user',
        message: 'You need to be signed in to change your password.',
      );
    }
    final credential = EmailAuthProvider.credential(email: user.email!, password: currentPassword);
    await user.reauthenticateWithCredential(credential);
    await user.updatePassword(newPassword);
  }

  /// Updates the Auth display name and mirrors it to the Firestore profile.
  /// Returns null on success, or a user-facing error message describing
  /// why the Firestore mirror failed (the Auth display name itself will
  /// still have been updated even if this returns an error, since that
  /// part happens first and isn't wrapped in the same try/catch).
  static Future<String?> updateDisplayName(String fullName) async {
    final user = _auth.currentUser;
    if (user == null) return 'You need to be signed in to do that.';
    final trimmed = fullName.trim();
    await user.updateDisplayName(trimmed);
    await user.reload();
    try {
      await _db.collection('users').doc(user.uid).set(
        {'fullName': trimmed},
        SetOptions(merge: true),
      );
      return null;
    } catch (e) {
      // ignore: avoid_print
      print('[AuthService] Could not save display name: $e');
      return friendlyError(e);
    }
  }

  /// Persists the current set of favourited fuel stations / EV chargers
  /// (by their OSM ids) to the account's Firestore profile, so favourites
  /// carry over between sessions and devices instead of resetting on
  /// every app restart. Returns null on success, or a user-facing error
  /// message on failure — see [updateVehiclePreference] for why that
  /// matters instead of failing silently.
  static Future<String?> updateFavourites({required Set<String> fuelIds, required Set<String> evIds}) async {
    final uid = currentUser?.uid;
    if (uid == null) return 'You need to be signed in to do that.';
    try {
      await _db.collection('users').doc(uid).set(
        {'favouriteFuelIds': fuelIds.toList(), 'favouriteEvIds': evIds.toList()},
        SetOptions(merge: true),
      );
      return null;
    } catch (e) {
      // ignore: avoid_print
      print('[AuthService] Could not save favourites: $e');
      return friendlyError(e);
    }
  }

  /// Remembers roughly where the user last was, so a future session (a
  /// fresh install, a different device, or simply before the OS has a
  /// cached GPS fix yet) can start the map from somewhere close to right
  /// instead of waiting on a location resolution from scratch. This is a
  /// pure loading-speed optimization — failures here are silent/low-stakes
  /// since nothing user-entered is ever lost, unlike favourites/preferences.
  static Future<void> updateLastLocation(double lat, double lng) async {
    final uid = currentUser?.uid;
    if (uid == null) return;
    try {
      await _db.collection('users').doc(uid).set(
        {'lastLat': lat, 'lastLng': lng, 'lastLocationAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
    } catch (e) {
      // ignore: avoid_print
      print('[AuthService] Could not save last location: $e');
    }
  }

  /// Turns Firebase's error codes into short, user-facing messages instead
  /// of raw exception text. Falls back to showing the real error message
  /// (rather than a generic "something went wrong") for anything
  /// unrecognized, so problems are easy to diagnose instead of hidden.
  static String friendlyError(Object error) {
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'email-already-in-use':
          return 'An account already exists for that email.';
        case 'invalid-email':
          return 'That email address looks invalid.';
        case 'weak-password':
          return 'Password is too weak.';
        case 'user-not-found':
        case 'wrong-password':
        case 'invalid-credential':
          return 'Incorrect email or password.';
        case 'too-many-requests':
          return 'Too many attempts. Try again in a moment.';
        case 'network-request-failed':
          return 'Network error. Check your connection.';
        case 'requires-recent-login':
          return 'For security, please log out and log back in, then try again.';
        case 'no-current-user':
          return error.message ?? 'You need to be signed in to do that.';
        case 'configuration-not-found':
        case 'operation-not-allowed':
          return 'Email/Password sign-in isn\'t enabled for this Firebase project yet. Enable it in Firebase Console → Authentication → Sign-in method.';
        default:
          return error.message ?? 'Auth error (${error.code}). Please try again.';
      }
    }
    if (error is FirebaseException) {
      if (error.code == 'permission-denied') {
        return 'Firestore rejected this write (permission-denied). Your security rules likely only allow '
            'creating the profile document, not updating it — see the Rules example in FIREBASE_SETUP.md, '
            'it needs "allow read, write" (not just "create") for a signed-in user\'s own document.';
      }
      if (error.code == 'unavailable') {
        return 'Could not reach Firestore. Check your internet connection and try again.';
      }
      return 'Firebase error (${error.plugin}/${error.code}): ${error.message ?? 'Please try again.'}';
    }
    return 'Something went wrong: $error';
  }
}