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

  /// Returns true if the write succeeded. Callers can show an error if it
  /// didn't — a failure here used to only print to the debug console,
  /// which made a real problem (e.g. Firestore security rules rejecting
  /// the write) look identical to it silently doing nothing.
  static Future<bool> updateVehiclePreference({required bool drivesFuel, required bool drivesEV}) async {
    final uid = currentUser?.uid;
    if (uid == null) return false;
    try {
      await _db.collection('users').doc(uid).set(
        {'drivesFuel': drivesFuel, 'drivesEV': drivesEV},
        SetOptions(merge: true),
      );
      return true;
    } catch (e) {
      // ignore: avoid_print
      print('[AuthService] Could not save vehicle preference: $e');
      return false;
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

  /// Updates the Auth display name and mirrors it to the Firestore profile
  /// (best-effort — same non-fatal pattern as [register]).
  static Future<void> updateDisplayName(String fullName) async {
    final user = _auth.currentUser;
    if (user == null) return;
    final trimmed = fullName.trim();
    await user.updateDisplayName(trimmed);
    await user.reload();
    try {
      await _db.collection('users').doc(user.uid).set(
        {'fullName': trimmed},
        SetOptions(merge: true),
      );
    } catch (e) {
      // ignore: avoid_print
      print('[AuthService] Could not save display name: $e');
    }
  }

  /// Persists the current set of favourited fuel stations / EV chargers
  /// (by their OSM ids) to the account's Firestore profile, so favourites
  /// carry over between sessions and devices instead of resetting on
  /// every app restart.
  static Future<void> updateFavourites({required Set<String> fuelIds, required Set<String> evIds}) async {
    final uid = currentUser?.uid;
    if (uid == null) return;
    try {
      await _db.collection('users').doc(uid).set(
        {'favouriteFuelIds': fuelIds.toList(), 'favouriteEvIds': evIds.toList()},
        SetOptions(merge: true),
      );
    } catch (e) {
      // ignore: avoid_print
      print('[AuthService] Could not save favourites: $e');
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
      return 'Firebase error (${error.plugin}/${error.code}): ${error.message ?? 'Please try again.'}';
    }
    return 'Something went wrong: $error';
  }
}