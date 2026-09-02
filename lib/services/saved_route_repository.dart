import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/trip_models.dart';
import 'auth_service.dart';

class SavedRouteRepositoryException implements Exception {
  final String message;
  const SavedRouteRepositoryException(this.message);
  @override
  String toString() => message;
}

class SavedRouteRepository {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static CollectionReference<Map<String, dynamic>> get _routes =>
      _db.collection('savedRoutes');

  static String _requireUserId() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      throw const SavedRouteRepositoryException(
          'You need to be signed in to manage saved routes.');
    }
    return uid;
  }

  static Stream<List<SavedRoute>> watchMine() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return Stream.value(const []);
    return _routes
        .where('userId', isEqualTo: uid)
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(SavedRoute.fromDoc).toList());
  }

  static Future<String> create(SavedRoute route) async {
    final uid = _requireUserId();
    _validate(route, uid);
    try {
      final doc = await _routes.add(route.toFirestore(create: true));
      return doc.id;
    } catch (error) {
      throw SavedRouteRepositoryException(AuthService.friendlyError(error));
    }
  }

  static Future<void> update(SavedRoute route) async {
    final uid = _requireUserId();
    if (route.id.isEmpty) {
      throw const SavedRouteRepositoryException('This saved route is invalid.');
    }
    _validate(route, uid);
    try {
      await _routes.doc(route.id).update(route.toFirestore(create: false));
    } catch (error) {
      throw SavedRouteRepositoryException(AuthService.friendlyError(error));
    }
  }

  static Future<void> rename(String routeId, String name) async {
    _requireUserId();
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > 60) {
      throw const SavedRouteRepositoryException(
          'Route name must be between 1 and 60 characters.');
    }
    try {
      await _routes.doc(routeId).update({
        'name': trimmed,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (error) {
      throw SavedRouteRepositoryException(AuthService.friendlyError(error));
    }
  }

  static Future<void> delete(String routeId) async {
    _requireUserId();
    try {
      await _routes.doc(routeId).delete();
    } catch (error) {
      throw SavedRouteRepositoryException(AuthService.friendlyError(error));
    }
  }

  static void _validate(SavedRoute route, String uid) {
    if (route.userId != uid) {
      throw const SavedRouteRepositoryException(
          'This route belongs to another account.');
    }
    if (route.name.trim().isEmpty || route.name.trim().length > 60) {
      throw const SavedRouteRepositoryException(
          'Route name must be between 1 and 60 characters.');
    }
    if (route.vehicleId.isEmpty || route.oneWayDistanceKm <= 0) {
      throw const SavedRouteRepositoryException(
          'Complete the route calculation before saving.');
    }
  }
}
