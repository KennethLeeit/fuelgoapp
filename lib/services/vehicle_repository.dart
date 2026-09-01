import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'vehicle_api_service.dart';

/// Thrown when a Firestore vehicle read/write can't complete.
class VehicleRepositoryException implements Exception {
  final String message;
  VehicleRepositoryException(this.message);
  @override
  String toString() => message;
}

/// Persists and reads the signed-in user's saved vehicles from Cloud
/// Firestore.
///
/// Vehicles live in a top-level `vehicles` collection; each document is
/// tagged with the owning user's [userId] so a single user can save many
/// cars while the collection stays easy to query/filter (e.g. from the
/// console or for an admin view).
class VehicleRepository {
  static final _db = FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>> get _vehicles =>
      _db.collection('vehicles');

  /// Saves [vehicle] for the currently signed-in user and returns the new
  /// Firestore document id.
  static Future<String> addVehicle(VehicleFuelEconomy vehicle) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw VehicleRepositoryException(
        'You need to be signed in to save a vehicle.',
      );
    }
    try {
      final doc = await _vehicles.add({
        'userId': user.uid,
        'fuelEconomyId': vehicle.id,
        'year': vehicle.year,
        'make': vehicle.make,
        'model': vehicle.model,
        'trans': vehicle.trans,
        'drive': vehicle.drive,
        'fuelType': vehicle.fuelType,
        'cityMpg': vehicle.cityMpg,
        'highwayMpg': vehicle.highwayMpg,
        'combinedMpg': vehicle.combinedMpg,
        'isElectric': vehicle.isElectric,
        'combinedKwhPer100Miles': vehicle.combinedKwhPer100Miles,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return doc.id;
    } catch (e) { print('Firestore save error: $e'); throw VehicleRepositoryException('Could not save the vehicle.'); }
  }

  /// Deletes a saved vehicle document by its Firestore id.
  static Future<void> deleteVehicle(String docId) async {
    try {
      await _vehicles.doc(docId).delete();
    } catch (_) {
      throw VehicleRepositoryException('Could not delete the vehicle.');
    }
  }

  /// Streams the signed-in user's saved vehicles, newest first.
  /// Emits an empty stream if nobody is signed in.
  static Stream<QuerySnapshot<Map<String, dynamic>>> watchMyVehicles() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Stream.empty();
    return _vehicles
        .where('userId', isEqualTo: user.uid)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }
}
