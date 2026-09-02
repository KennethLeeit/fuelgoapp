import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/auth_service.dart';
import '../services/review_service.dart';
import '../theme/app_theme.dart';

/// Google-Maps-style review block: average rating + star breakdown, a
/// "Write a review" / "Edit review" action, and the live list of every
/// user's review for this station. Drop this at the bottom of a station
/// or charger detail screen — it's fully self-contained (own Firestore
/// stream, own bottom sheet for writing/editing).
class ReviewSection extends StatelessWidget {
  final String stationId;
  final ReviewStationType stationType;
  const ReviewSection({super.key, required this.stationId, required this.stationType});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Review>>(
      stream: ReviewService.streamReviews(stationId, stationType),
      builder: (context, snapshot) {
        final reviews = snapshot.data ?? const <Review>[];
        final loading = snapshot.connectionState == ConnectionState.waiting;
        final hasError = snapshot.hasError;
        final avg = reviews.isEmpty ? 0.0 : reviews.map((r) => r.rating).reduce((a, b) => a + b) / reviews.length;

        final uid = AuthService.currentUser?.uid;
        Review? mine;
        if (uid != null) {
          for (final r in reviews) {
            if (r.userId == uid) {
              mine = r;
              break;
            }
          }
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24),
            const Text('Reviews', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(reviews.isEmpty ? '\u2014' : avg.toStringAsFixed(1),
                    style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _StarRow(rating: avg, size: 18),
                    const SizedBox(height: 2),
                    Text(
                      reviews.isEmpty ? 'No reviews yet' : '${reviews.length} review${reviews.length == 1 ? '' : 's'}',
                      style: const TextStyle(fontSize: 12, color: AppColors.textGrey),
                    ),
                  ],
                ),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: () => _openReviewSheet(context, existing: mine),
                  icon: Icon(mine == null ? Icons.rate_review_outlined : Icons.edit_outlined, size: 16),
                  label: Text(mine == null ? 'Write a review' : 'Edit review'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primaryBlue,
                    side: const BorderSide(color: AppColors.primaryBlue),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (hasError)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF4F4),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFF3C9C9)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Could not load reviews.',
                      style: TextStyle(color: AppColors.textDark, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    // Firestore's own error text goes here on purpose —
                    // for a missing-index error (the most common cause
                    // the first time this query ever runs) it contains a
                    // direct console link to create that index. Hiding
                    // it behind a generic message just makes this
                    // undiagnosable from the running app.
                    SelectableText(
                      '${snapshot.error}',
                      style: const TextStyle(fontSize: 11, color: AppColors.textGrey),
                    ),
                  ],
                ),
              )
            else if (reviews.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F9FC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: const Text(
                  'Be the first to review this location.',
                  style: TextStyle(color: AppColors.textGrey),
                ),
              )
            else
              Column(
                children: reviews
                    .map((r) => _ReviewTile(
                          review: r,
                          isMine: r.userId == uid,
                          onEdit: () => _openReviewSheet(context, existing: r),
                          onDelete: () => _confirmDelete(context, r),
                        ))
                    .toList(),
              ),
          ],
        );
      },
    );
  }

  void _openReviewSheet(BuildContext context, {Review? existing}) {
    if (AuthService.currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to write a review.')),
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
        child: _WriteReviewSheet(
          stationId: stationId,
          stationType: stationType,
          existing: existing,
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, Review review) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete review?'),
        content: const Text('This will remove your review permanently.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              final error = await ReviewService.deleteReview(stationId: stationId, stationType: stationType);
              if (error != null && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

class _StarRow extends StatelessWidget {
  final double rating;
  final double size;
  const _StarRow({required this.rating, this.size = 16});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final filled = rating >= i + 1;
        final half = !filled && rating > i && rating < i + 1;
        return Icon(
          half ? Icons.star_half_rounded : (filled ? Icons.star_rounded : Icons.star_border_rounded),
          size: size,
          color: const Color(0xFFFFB800),
        );
      }),
    );
  }
}

class _ReviewTile extends StatelessWidget {
  final Review review;
  final bool isMine;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _ReviewTile({required this.review, required this.isMine, required this.onEdit, required this.onDelete});

  String _relativeTime(DateTime? dt) {
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inDays >= 365) return '${(diff.inDays / 365).floor()}y ago';
    if (diff.inDays >= 30) return '${(diff.inDays / 30).floor()}mo ago';
    if (diff.inDays >= 1) return '${diff.inDays}d ago';
    if (diff.inHours >= 1) return '${diff.inHours}h ago';
    if (diff.inMinutes >= 1) return '${diff.inMinutes}m ago';
    return 'Just now';
  }

  @override
  Widget build(BuildContext context) {
    final trimmedName = review.userName.trim();
    final initial = trimmedName.isNotEmpty ? trimmedName[0].toUpperCase() : '?';
    final avatarColor = colorForName(review.userName);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: avatarColor.withOpacity(0.15),
                child: Text(initial, style: TextStyle(color: avatarColor, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(review.userName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        _StarRow(rating: review.rating.toDouble(), size: 13),
                        const SizedBox(width: 6),
                        Text(_relativeTime(review.updatedAt ?? review.createdAt),
                            style: const TextStyle(fontSize: 11, color: AppColors.textGrey)),
                      ],
                    ),
                  ],
                ),
              ),
              if (isMine)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 18, color: AppColors.textGrey),
                  onSelected: (value) => value == 'edit' ? onEdit() : onDelete(),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
            ],
          ),
          if (review.comment.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(review.comment, style: const TextStyle(color: AppColors.textDark, height: 1.35)),
          ],
        ],
      ),
    );
  }
}

class _WriteReviewSheet extends StatefulWidget {
  final String stationId;
  final ReviewStationType stationType;
  final Review? existing;
  const _WriteReviewSheet({required this.stationId, required this.stationType, this.existing});

  @override
  State<_WriteReviewSheet> createState() => _WriteReviewSheetState();
}

class _WriteReviewSheetState extends State<_WriteReviewSheet> {
  late int _rating = widget.existing?.rating ?? 5;
  late final TextEditingController _controller = TextEditingController(text: widget.existing?.comment ?? '');
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _saving = true);
    final error = await ReviewService.submitReview(
      stationId: widget.stationId,
      stationType: widget.stationType,
      rating: _rating,
      comment: _controller.text,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.existing == null ? 'Write a review' : 'Edit your review',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(5, (i) {
                  final filled = i < _rating;
                  return IconButton(
                    onPressed: () => setState(() => _rating = i + 1),
                    icon: Icon(filled ? Icons.star_rounded : Icons.star_border_rounded,
                        color: const Color(0xFFFFB800), size: 32),
                  );
                }),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              maxLines: 4,
              maxLength: 500,
              decoration: const InputDecoration(
                hintText: 'Share your experience (optional)...',
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _submit,
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(widget.existing == null ? 'Submit review' : 'Update review'),
              ),
            ),
            if (widget.existing != null) ...[
              const SizedBox(height: 4),
              Center(
                child: TextButton(
                  onPressed: _saving
                      ? null
                      : () async {
                          setState(() => _saving = true);
                          final error = await ReviewService.deleteReview(
                            stationId: widget.stationId,
                            stationType: widget.stationType,
                          );
                          if (!mounted) return;
                          if (error != null) {
                            setState(() => _saving = false);
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
                          } else {
                            Navigator.pop(context);
                          }
                        },
                  child: const Text('Delete my review', style: TextStyle(color: Colors.red)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
