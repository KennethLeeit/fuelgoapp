import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

/// Shows the signed-in user's profile picture: a custom uploaded photo if
/// one exists, otherwise a preset "cartoon" avatar (emoji on a coloured
/// circle) if one was chosen, otherwise a plain default person icon.
///
/// Driven by AuthService.profileStream — the same Firestore document used
/// for the rest of the account's profile data — so it updates live the
/// moment a new avatar is saved from AvatarPickerSheet, without needing
/// any extra plumbing between the two.
///
/// Pass [onTap] to make it tappable (shows a small edit badge in the
/// corner); omit it for a purely decorative, read-only avatar elsewhere
/// in the app.
class UserAvatar extends StatelessWidget {
  final double radius;
  final VoidCallback? onTap;

  const UserAvatar({super.key, this.radius = 32, this.onTap});

  @override
  Widget build(BuildContext context) {
    final uid = AuthService.currentUser?.uid;
    final avatar = uid == null
        ? _fallback()
        : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: AuthService.profileStream(uid),
            builder: (context, snapshot) {
              final data = snapshot.data?.data();
              final photoUrl = (data?['photoUrl'] as String?)?.trim();
              final emoji = (data?['avatarEmoji'] as String?)?.trim();
              final colorValue = data?['avatarColor'] as int?;

              if (photoUrl != null && photoUrl.isNotEmpty) {
                return CircleAvatar(
                  radius: radius,
                  backgroundColor: const Color(0xFFEFF3F8),
                  backgroundImage: NetworkImage(photoUrl),
                  // If the URL fails to load (deleted from Storage,
                  // network hiccup), fall back to the plain icon rather
                  // than a broken-image box.
                  onBackgroundImageError: (_, __) {},
                  child: null,
                );
              }
              if (emoji != null && emoji.isNotEmpty) {
                return CircleAvatar(
                  radius: radius,
                  backgroundColor: colorValue != null ? Color(colorValue) : AppColors.primaryBlue,
                  child: Text(emoji, style: TextStyle(fontSize: radius * 0.9)),
                );
              }
              return _fallback();
            },
          );

    if (onTap == null) return avatar;
    return InkWell(
      borderRadius: BorderRadius.circular(radius),
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          avatar,
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: AppColors.primaryBlue,
                shape: BoxShape.circle,
                border: Border.fromBorderSide(BorderSide(color: Colors.white, width: 2)),
              ),
              child: const Icon(Icons.edit, size: 12, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fallback() => CircleAvatar(
        radius: radius,
        backgroundColor: const Color(0xFFEFF3F8),
        child: Icon(Icons.person, size: radius * 1.05, color: AppColors.primaryBlue),
      );
}
