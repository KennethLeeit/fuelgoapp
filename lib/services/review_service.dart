import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/models.dart';
import 'auth_service.dart';

class ReviewService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const _collection = 'reviews';

  static String _sanitize(String stationId) => stationId.replaceAll('/', '-');

  static String stationKeyFor(ReviewStationType type, String stationId) =>
      '${type.key}_${_sanitize(stationId)}';

  static String _docId(ReviewStationType type, String stationId, String uid) =>
      '${stationKeyFor(type, stationId)}_$uid';

  static Stream<List<Review>> streamReviews(
      String stationId, ReviewStationType type) {
    return _db
        .collection(_collection)
        .where('stationKey', isEqualTo: stationKeyFor(type, stationId))
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => Review.fromFirestore(d.id, d.data()))
            .toList());
  }

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
      final userName = (user.displayName?.trim().isNotEmpty ?? false)
          ? user.displayName!.trim()
          : 'FuelGo user';
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
      print('[ReviewService] Could not save review: $e');
      return AuthService.friendlyError(e);
    }
  }

  static Stream<int> watchMyReviewCount(String uid) {
    return _db
        .collection(_collection)
        .where('userId', isEqualTo: uid)
        .snapshots()
        .map((s) => s.docs.length);
  }

  static Stream<List<Review>> streamMyReviews(String uid) {
    return _db
        .collection(_collection)
        .where('userId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => Review.fromFirestore(d.id, d.data()))
            .toList());
  }

  static Future<String?> deleteReview({
    required String stationId,
    required ReviewStationType stationType,
  }) async {
    final user = AuthService.currentUser;
    if (user == null) return 'You need to be signed in to do that.';
    try {
      await _db
          .collection(_collection)
          .doc(_docId(stationType, stationId, user.uid))
          .delete();
      return null;
    } catch (e) {
      print('[ReviewService] Could not delete review: $e');
      return AuthService.friendlyError(e);
    }
  }
}
