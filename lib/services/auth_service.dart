import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static User? get currentUser => _auth.currentUser;
  static Stream<User?> get authStateChanges => _auth.authStateChanges();

  static Future<User> register({
    required String fullName,
    required String email,
    required String password,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(), password: password);
    final user = credential.user!;

    try {
      await user.updateDisplayName(fullName.trim());
    } catch (_) {}

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
      print(
          '[AuthService] Could not save Firestore profile for ${user.uid}: $e');
    }

    return user;
  }

  static Future<User> signIn(
      {required String email, required String password}) async {
    final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(), password: password);
    return credential.user!;
  }

  static Future<void> sendPasswordResetEmail(String email) {
    return _auth.sendPasswordResetEmail(email: email.trim());
  }

  static Future<void> signOut() => _auth.signOut();

  static Future<void> setPersistence(Persistence persistence) {
    return _auth.setPersistence(persistence);
  }

  static Future<Map<String, dynamic>?> getProfile(String uid) async {
    try {
      final doc = await _db.collection('users').doc(uid).get();
      return doc.data();
    } catch (e) {
      print('[AuthService] Could not read Firestore profile for $uid: $e');
      return null;
    }
  }

  static Stream<DocumentSnapshot<Map<String, dynamic>>> profileStream(
      String uid) {
    return _db.collection('users').doc(uid).snapshots();
  }

  static Future<String?> updateVehiclePreference(
      {required bool drivesFuel, required bool drivesEV}) async {
    final uid = currentUser?.uid;
    if (uid == null) return 'You need to be signed in to do that.';
    try {
      await _db.collection('users').doc(uid).set(
        {'drivesFuel': drivesFuel, 'drivesEV': drivesEV},
        SetOptions(merge: true),
      );
      return null;
    } catch (e) {
      print('[AuthService] Could not save vehicle preference: $e');
      return friendlyError(e);
    }
  }

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
    final credential = EmailAuthProvider.credential(
        email: user.email!, password: currentPassword);
    await user.reauthenticateWithCredential(credential);
    await user.updatePassword(newPassword);
  }

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
      print('[AuthService] Could not save display name: $e');
      return friendlyError(e);
    }
  }

  static Future<String?> updateFavourites(
      {required Set<String> fuelIds, required Set<String> evIds}) async {
    final uid = currentUser?.uid;
    if (uid == null) return 'You need to be signed in to do that.';
    try {
      await _db.collection('users').doc(uid).set(
        {
          'favouriteFuelIds': fuelIds.toList(),
          'favouriteEvIds': evIds.toList()
        },
        SetOptions(merge: true),
      );
      return null;
    } catch (e) {
      print('[AuthService] Could not save favourites: $e');
      return friendlyError(e);
    }
  }

  static Future<String?> updateAvatarPreset(
      {required String emoji, required int colorValue}) async {
    final user = currentUser;
    if (user == null) return 'You need to be signed in to do that.';
    try {
      if (user.photoURL != null) {
        try {
          await user.updatePhotoURL(null);
        } catch (_) {}
      }
      await _db.collection('users').doc(user.uid).set({
        'avatarEmoji': emoji,
        'avatarColor': colorValue,
        'photoUrl': null,
      }, SetOptions(merge: true));
      return null;
    } catch (e) {
      print('[AuthService] Could not save avatar preset: $e');
      return friendlyError(e);
    }
  }

  static Future<void> updateLastLocation(double lat, double lng) async {
    final uid = currentUser?.uid;
    if (uid == null) return;
    try {
      await _db.collection('users').doc(uid).set(
        {
          'lastLat': lat,
          'lastLng': lng,
          'lastLocationAt': FieldValue.serverTimestamp()
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      print('[AuthService] Could not save last location: $e');
    }
  }

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
          return error.message ??
              'Auth error (${error.code}). Please try again.';
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
