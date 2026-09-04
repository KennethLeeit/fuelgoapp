import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/auth_service.dart';
import '../services/review_service.dart';
import '../theme/app_theme.dart';

/// Lists every review the signed-in user has written, across both fuel
/// stations and EV chargers, so they can review/edit/delete them in one
/// place instead of hunting through individual station detail pages.
/// Editing/deleting here calls the exact same ReviewService methods a
/// station's own ReviewSection uses, so both stay in sync automatically
/// via the live Firestore stream — no separate "refresh" step needed.
class MyReviewsScreen extends StatelessWidget {
  const MyReviewsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = AuthService.currentUser?.uid;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('My Reviews', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: uid == null
            ? const Center(child: Text('Sign in to see your reviews.'))
            : StreamBuilder<List<Review>>(
          stream: ReviewService.streamMyReviews(uid),
          builder: (context, snapshot) {
            final loading = snapshot.connectionState == ConnectionState.waiting;
            if (loading) return const Center(child: CircularProgressIndicator());

            if (snapshot.hasError) {
              return Padding(
                padding: const EdgeInsets.all(20),
                child: Container(
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
                      const Text('Could not load your reviews.',
                          style: TextStyle(color: AppColors.textDark, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      // Same reasoning as ReviewSection: on first run this is
                      // very likely a missing-index error with a direct
                      // console link to create it — surface it, don't hide it.
                      SelectableText('${snapshot.error}',
                          style: const TextStyle(fontSize: 11, color: AppColors.textGrey)),
                    ],
                  ),
                ),
              );
            }

            final reviews = snapshot.data ?? const <Review>[];
            if (reviews.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    "You haven't written any reviews yet.\nRate a fuel station or EV charger to see it here.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textGrey),
                  ),
                ),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.all(20),
              itemCount: reviews.length + 1,
              itemBuilder: (context, i) {
                if (i == 0) return _LevelHeader(reviewCount: reviews.length);
                return _MyReviewTile(review: reviews[i - 1]);
              },
            );
          },
        ),
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

class _MyReviewTile extends StatelessWidget {
  final Review review;
  const _MyReviewTile({required this.review});

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

  void _edit(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
        child: _EditReviewSheet(review: review),
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete review?'),
        content: Text('This will remove your review of ${review.stationName} permanently.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              final error = await ReviewService.deleteReview(
                stationId: review.stationId,
                stationType: review.stationType,
              );
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

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                review.stationType == ReviewStationType.ev ? Icons.electric_car : Icons.local_gas_station,
                size: 18,
                color: review.stationType == ReviewStationType.ev ? AppColors.evGreen : AppColors.fuelOrange,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(review.stationName,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 18, color: AppColors.textGrey),
                onSelected: (value) => value == 'edit' ? _edit(context) : _confirmDelete(context),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _StarRow(rating: review.rating.toDouble(), size: 15),
              const SizedBox(width: 6),
              Text(_relativeTime(review.updatedAt ?? review.createdAt),
                  style: const TextStyle(fontSize: 11, color: AppColors.textGrey)),
            ],
          ),
          if (review.comment.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(review.comment,
                style: TextStyle(
                    color: Theme.of(context).textTheme.bodyLarge?.color ?? AppColors.textDark, height: 1.35)),
          ],
        ],
      ),
    );
  }
}

/// A trimmed-down edit-only sheet for My Reviews. Unlike ReviewSection's
/// write sheet, this always has an [existing] review (you can only edit
/// something you already wrote), so it skips the "new vs edit" branching
/// entirely and just needs rating + comment.
class _EditReviewSheet extends StatefulWidget {
  final Review review;
  const _EditReviewSheet({required this.review});

  @override
  State<_EditReviewSheet> createState() => _EditReviewSheetState();
}

class _EditReviewSheetState extends State<_EditReviewSheet> {
  late int _rating = widget.review.rating;
  late final TextEditingController _controller = TextEditingController(text: widget.review.comment);
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _saving = true);
    final error = await ReviewService.submitReview(
      stationId: widget.review.stationId,
      stationType: widget.review.stationType,
      stationName: widget.review.stationName,
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
            Text('Edit your review of ${widget.review.stationName}',
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
                    : const Text('Update review'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full tier ladder (McDonald's-rewards-app style) at the top of My
/// Reviews — shows all 5 tiers at once, not just the current one, so the
/// user can see where they sit and what's still ahead. Takes the count
/// directly from the already-loaded review list rather than a second
/// Firestore listener, since this screen has the full list in memory anyway.
class _LevelHeader extends StatelessWidget {
  final int reviewCount;
  const _LevelHeader({required this.reviewCount});

  @override
  Widget build(BuildContext context) {
    final tiers = ReviewerLevel.allTiers;
    final current = ReviewerLevel.forCount(reviewCount);
    final toNext = current.reviewsToNextTier(reviewCount);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: current.color.withValues(alpha: 0.12),
                child: Icon(current.icon, color: current.color, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(current.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    Text(
                      '$reviewCount ${reviewCount == 1 ? 'review' : 'reviews'} written',
                      style: const TextStyle(fontSize: 12, color: AppColors.textGrey),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          // The ladder: one node per tier, connected by a line that fills
          // in as each threshold is passed. Reached tiers get a filled
          // gradient badge with a small check overlay once passed; the
          // current tier gets a coloured ring and a slightly bigger badge;
          // upcoming tiers are hollow/grey with their threshold shown
          // underneath — same idea as a McDonald's/coffee-app rewards strip.
          // Horizontally scrollable so full tier names never get squeezed.
          SizedBox(
            height: 80,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: List.generate(tiers.length * 2 - 1, (i) {
                  if (i.isOdd) {
                    final beforeTier = tiers[i ~/ 2];
                    final reached = reviewCount >= beforeTier.minReviews;
                    return Padding(
                      padding: const EdgeInsets.only(top: 24),
                      child: Container(
                        width: 80,
                        height: 4,
                        decoration: BoxDecoration(
                          color: reached ? beforeTier.color : const Color(0xFFE7EAF0),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    );
                  }
                  final tier = tiers[i ~/ 2];
                  final isCurrent = tier.tier == current.tier;
                  final isReached = reviewCount >= tier.minReviews;
                  final isCompleted = isReached && !isCurrent;
                  return SizedBox(
                    width: 68,
                    child: Column(
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              width: isCurrent ? 52 : 44,
                              height: isCurrent ? 52 : 44,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: isReached
                                    ? LinearGradient(
                                  colors: [tier.color, tier.color.withValues(alpha: 0.75)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                )
                                    : null,
                                color: isReached ? null : Colors.white,
                                border: Border.all(
                                  color: isCurrent
                                      ? tier.color
                                      : (isReached ? Colors.transparent : const Color(0xFFE1E5EC)),
                                  width: isCurrent ? 3 : 1.5,
                                ),
                                boxShadow: isReached
                                    ? [
                                  BoxShadow(
                                    color: tier.color.withValues(alpha: 0.35),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ]
                                    : null,
                              ),
                              child: Icon(
                                tier.icon,
                                size: isCurrent ? 22 : 18,
                                color: isReached ? Colors.white : const Color(0xFFB0B7C3),
                              ),
                            ),
                            if (isCompleted)
                              Positioned(
                                right: -1,
                                bottom: -1,
                                child: Container(
                                  padding: const EdgeInsets.all(2.5),
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF27AE60),
                                    shape: BoxShape.circle,
                                    border: Border.fromBorderSide(BorderSide(color: Colors.white, width: 1.5)),
                                  ),
                                  child: const Icon(Icons.check_rounded, size: 9, color: Colors.white),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          tier.name,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 9.5,
                            height: 1.15,
                            fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w600,
                            color: isReached
                                ? (Theme.of(context).textTheme.bodyLarge?.color ?? AppColors.textDark)
                                : AppColors.textGrey,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ),
            ),
          ),
          if (toNext != null) ...[
            const SizedBox(height: 10),
            Text(
              '$toNext more ${toNext == 1 ? 'review' : 'reviews'} to reach ${tiers[current.tier].name}',
              style: TextStyle(fontSize: 11.5, color: current.color, fontWeight: FontWeight.w600),
            ),
          ] else ...[
            const SizedBox(height: 10),
            Text(
              "You've reached the highest tier!",
              style: TextStyle(fontSize: 11.5, color: current.color, fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
    );
  }
}