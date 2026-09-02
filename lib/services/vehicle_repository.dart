import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'vehicle_api_service.dart';
import '../models/trip_models.dart';

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

  /// The most vehicles a single user is allowed to save.
  static const int maxVehiclesPerUser = 5;

  // 1 US gallon = 3.785411784 L, 1 mile = 1.609344 km.
  // km per US gallon / L per gallon = km/L per mpg.
  static const _mpgToKmL = 1.609344 / 3.785411784;

  static double _kmL(int mpg) =>
      double.parse((mpg * _mpgToKmL).toStringAsFixed(2));

  /// Throws if [userId] has already reached [maxVehiclesPerUser] saved
  /// vehicles. Uses a server-side count query so we don't have to download
  /// every document just to check the total.
  static Future<void> _assertUnderLimit(String userId) async {
    final countSnapshot =
        await _vehicles.where('userId', isEqualTo: userId).count().get();
    final count = countSnapshot.count ?? 0;
    if (count >= maxVehiclesPerUser) {
      throw VehicleRepositoryException(
        'You can save up to $maxVehiclesPerUser vehicles. Delete one before adding another.',
      );
    }
  }

  /// Saves [vehicle] for the currently signed-in user and returns the new
  /// Firestore document id. Fuel efficiency is converted from the EPA API's
  /// MPG figures to km/L before it's stored.
  static Future<String> addVehicle(VehicleFuelEconomy vehicle) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw VehicleRepositoryException(
        'You need to be signed in to save a vehicle.',
      );
    }
    await _assertUnderLimit(user.uid);
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
        'cityKmL': _kmL(vehicle.cityMpg),
        'highwayKmL': _kmL(vehicle.highwayMpg),
        'combinedKmL': _kmL(vehicle.combinedMpg),
        'isElectric': vehicle.isElectric,
        'combinedKwhPer100Miles': vehicle.combinedKwhPer100Miles,
        'combinedKwhPer100Km': vehicle.combinedKwhPer100Km,
        'isFavourite': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return doc.id;
    } catch (e) {
      print('Firestore save error: $e');
      throw VehicleRepositoryException('Could not save the vehicle.');
    }
  }

  /// Saves a manually entered vehicle (used when the EPA lookup doesn't
  /// have a match, e.g. non-US market cars) for the currently signed-in
  /// user. [avgKmL] is stored as the city/highway/combined figure since a
  /// manual entry only gives us one average number, not an EPA breakdown.
  static Future<String> addManualVehicle({
    required String make,
    required String model,
    double? avgKmL,
    double? combinedKwhPer100Km,
    required String fuelType,
    int? year,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw VehicleRepositoryException(
        'You need to be signed in to save a vehicle.',
      );
    }
    await _assertUnderLimit(user.uid);
    final isElectric = fuelType == 'Electric';
    if (isElectric &&
        (combinedKwhPer100Km == null || combinedKwhPer100Km <= 0)) {
      throw VehicleRepositoryException(
          'Enter a valid EV efficiency in kWh per 100 km.');
    }
    if (!isElectric && (avgKmL == null || avgKmL <= 0)) {
      throw VehicleRepositoryException(
          'Enter a valid fuel efficiency in km/L.');
    }
    final kmL = isElectric ? 0.0 : double.parse(avgKmL!.toStringAsFixed(2));
    try {
      final doc = await _vehicles.add({
        'userId': user.uid,
        'year': year,
        'make': make,
        'model': model,
        'fuelType': fuelType,
        'cityKmL': kmL,
        'highwayKmL': kmL,
        'combinedKmL': kmL,
        'isElectric': isElectric,
        'combinedKwhPer100Km': isElectric
            ? double.parse(combinedKwhPer100Km!.toStringAsFixed(2))
            : null,
        'isManual': true,
        'isFavourite': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return doc.id;
    } catch (e) {
      print('Firestore save error: $e');
      throw VehicleRepositoryException('Could not save the vehicle.');
    }
  }

  /// Sets whether [docId] is the user's favourite vehicle. Favourites are
  /// surfaced first in "My Vehicles" on the home screen.
  static Future<void> setFavourite(String docId, bool isFavourite) async {
    try {
      await _vehicles.doc(docId).update({'isFavourite': isFavourite});
    } catch (_) {
      throw VehicleRepositoryException('Could not update favourite.');
    }
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

  /// Typed stream used by calculator and any UI that needs consistent
  /// powertrain/efficiency parsing, including legacy EV conversion.
  static Stream<List<SavedVehicle>> watchSavedVehicles() =>
      watchMyVehicles().map(
        (snapshot) => snapshot.docs.map(SavedVehicle.fromDoc).toList(),
      );

  static Future<SavedVehicle?> getSavedVehicle(String docId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    try {
      final doc = await _vehicles.doc(docId).get();
      if (!doc.exists || doc.data()?['userId'] != user.uid) return null;
      return SavedVehicle.fromDoc(doc);
    } catch (_) {
      throw VehicleRepositoryException('Could not load the saved vehicle.');
    }
  }
}
