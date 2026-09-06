import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/auth_service.dart';

const List<(String emoji, Color color)> avatarPresets = [
  ('🚗', Color(0xFF2F6FED)),
  ('🚙', Color(0xFFFF9800)),
  ('🏎️', Color(0xFFE53935)),
  ('🛵', Color(0xFF27AE60)),
  ('🚕', Color(0xFFFFC107)),
  ('😎', Color(0xFF8E44AD)),
  ('🦊', Color(0xFFEE7623)),
  ('🐱', Color(0xFF00AEEF)),
  ('🐶', Color(0xFF795548)),
  ('🐼', Color(0xFF37474F)),
  ('🦁', Color(0xFFF9A825)),
  ('🐯', Color(0xFFEF6C00)),
  ('🐨', Color(0xFF9E9E9E)),
  ('🐸', Color(0xFF43A047)),
  ('🤖', Color(0xFF546E7A)),
  ('👽', Color(0xFF00BFA5)),
  ('🌟', Color(0xFFFDD835)),
  ('⚡', Color(0xFF29B6F6)),
];

Future<void> showAvatarPickerSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => const _AvatarPickerSheet(),
  );
}

class _AvatarPickerSheet extends StatefulWidget {
  const _AvatarPickerSheet();

  @override
  State<_AvatarPickerSheet> createState() => _AvatarPickerSheetState();
}

class _AvatarPickerSheetState extends State<_AvatarPickerSheet> {
  bool _busy = false;
  String? _error;

  Future<void> _choosePreset((String, Color) preset) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await AuthService.updateAvatarPreset(
      emoji: preset.$1,
      colorValue: preset.$2.toARGB32(),
    );
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _busy = false;
        _error = error;
      });
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Choose a profile picture',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 16),
            GridView.count(
              crossAxisCount: 5,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              children: avatarPresets.map((preset) {
                return InkWell(
                  borderRadius: BorderRadius.circular(30),
                  onTap: _busy ? null : () => _choosePreset(preset),
                  child: CircleAvatar(
                    backgroundColor: preset.$2,
                    child:
                        Text(preset.$1, style: const TextStyle(fontSize: 20)),
                  ),
                );
              }).toList(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: const TextStyle(color: Colors.red, fontSize: 12)),
            ],
            if (_busy) ...[
              const SizedBox(height: 14),
              const Center(child: CircularProgressIndicator()),
            ],
          ],
        ),
      ),
    );
  }
}
