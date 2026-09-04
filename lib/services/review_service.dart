import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/models.dart';
import 'auth_service.dart';

/// Star-rating / written reviews for fuel stations and EV chargers — a
/// Google-Maps-style review feature backed by Firestore, so reviews are
/// visible to every user of the app, not just stored locally like
/// favourites (see FavouritesService for that pattern).
///
/// One review per signed-in user per station: each review's document id
/// is deterministic ("<type>_<stationId>_<uid>"), so writing a second
/// review for the same place updates the existing one instead of creating
/// a duplicate — the same behaviour Google Maps has.
///
/// Reviews are queried by a single combined [stationKey] field
/// ("<type>_<stationId>") rather than two separate equality filters, so
/// Firestore only ever needs one composite index (stationKey + createdAt)
/// instead of a three-field one. The very first time this query runs,
/// Firestore may print a console/log error with a direct link to create
/// that index — click it once and it builds automatically within a
/// minute; after that it never prompts again.
class ReviewService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const _collection = 'reviews';

  // Station ids from live sources look like "node/12345" (OSM) or
  // "ocm/123" (Open Charge Map) — they contain a "/", which Firestore
  // document ids cannot contain (it's treated as a sub-collection path
  // separator and would throw "Invalid document reference" at runtime).
  // Sanitized once here so every id/key built from a stationId is safe.
  static String _sanitize(String stationId) => stationId.replaceAll('/', '-');

  static String stationKeyFor(ReviewStationType type, String stationId) =>
      '${type.key}_${_sanitize(stationId)}';

  static String _docId(ReviewStationType type, String stationId, String uid) =>
      '${stationKeyFor(type, stationId)}_$uid';

  /// Live stream of every review for a station, newest first.
  static Stream<List<Review>> streamReviews(String stationId, ReviewStationType type) {
    return _db
        .collection(_collection)
        .where('stationKey', isEqualTo: stationKeyFor(type, stationId))
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => Review.fromFirestore(d.id, d.data())).toList());
  }

  /// Creates or updates the current user's review for this station.
  /// Returns null on success, or a user-facing error message on failure
  /// (see AuthService.friendlyError for how Firestore/auth errors are
  /// turned into readable text elsewhere in the app).
  static Future<String?> submitReview({
    required String stationId,
    required ReviewStationType stationType,
    required String stationName,
    required int rating,
    required String comment,
  }) async {
    final user = AuthService.currentUser;
    if (user == null) return 'You need to be signed in to write a review.';

    final id = _docId(stationType, stationId, user.uid);
    final docRef = _db.collection(_collection).doc(id);

    try {
      final existing = await docRef.get();
      final userName = (user.displayName?.trim().isNotEmpty ?? false) ? user.displayName!.trim() : 'FuelGo user';
      await docRef.set({
        'stationKey': stationKeyFor(stationType, stationId),
        'stationId': stationId,
        'stationType': stationType.key,
        'stationName': stationName.trim(),
        'userId': user.uid,
        'userName': userName,
        'rating': rating.clamp(1, 5),
        'comment': comment.trim(),
        if (!existing.exists) 'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return null;
    } catch (e) {
      // ignore: avoid_print
      print('[ReviewService] Could not save review: $e');
      return AuthService.friendlyError(e);
    }
  }

  /// Live count of reviews user has written, across both fuel
  /// and EV — powers the small level badge on Profile. Kept separate from
  /// [streamMyReviews] since the profile badge only needs a number, not
  /// every review's full content.
  static Stream<int> watchMyReviewCount(String uid) {
    return _db.collection(_collection).where('userId', isEqualTo: uid).snapshots().map((s) => s.docs.length);
  }

  /// Live stream of every review the signed-in user has written, across
  /// both fuel stations and EV chargers, newest first — powers the "My
  /// Reviews" screen. Same first-run index note as [streamReviews]: this
  /// pairs an equality filter with an orderBy on a different field, so
  /// Firestore needs a composite index (userId + createdAt) the first
  /// time it runs; the console error link builds it automatically.
  static Stream<List<Review>> streamMyReviews(String uid) {
    return _db
        .collection(_collection)
        .where('userId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => Review.fromFirestore(d.id, d.data())).toList());
  }

  /// Deletes the current user's review for this station, if any.
  static Future<String?> deleteReview({
    required String stationId,
    required ReviewStationType stationType,
  }) async {
    final user = AuthService.currentUser;
    if (user == null) return 'You need to be signed in to do that.';
    try {
      await _db.collection(_collection).doc(_docId(stationType, stationId, user.uid)).delete();
      return null;
    } catch (e) {
      // ignore: avoid_print
      print('[ReviewService] Could not delete review: $e');
      return AuthService.friendlyError(e);
    }
  }
}
