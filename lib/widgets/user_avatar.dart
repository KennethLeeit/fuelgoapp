import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

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
                  onBackgroundImageError: (_, __) {},
                  child: null,
                );
              }
              if (emoji != null && emoji.isNotEmpty) {
                return CircleAvatar(
                  radius: radius,
                  backgroundColor: colorValue != null
                      ? Color(colorValue)
                      : AppColors.primaryBlue,
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
                border: Border.fromBorderSide(
                    BorderSide(color: Colors.white, width: 2)),
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
        child: Icon(Icons.person,
            size: radius * 1.05, color: AppColors.primaryBlue),
      );
}
