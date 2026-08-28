import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';
import '../theme/app_theme.dart';
import '../services/auth_service.dart';
import '../utils/validators.dart';
import '../widgets/password_strength_meter.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Profile picture
  final ImagePicker _picker = ImagePicker();
  Uint8List? _pickedImageBytes;
  bool _isUploadingPhoto = false;

  // Username
  late final TextEditingController _nameController;
  bool _isSavingName = false;

  // Change password
  final _passwordFormKey = GlobalKey<FormState>();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _isChangingPassword = false;
  String? _currentPasswordError;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: AuthService.currentUser?.displayName ?? '');
    _newPasswordController.addListener(() => setState(() {})); // drive the strength meter
  }

  @override
  void dispose() {
    _nameController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _snack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : AppColors.evGreen,
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Profile picture
  // ---------------------------------------------------------------------

  Future<void> _showPhotoOptions() async {
    await showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.cardBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined, color: AppColors.primaryBlue),
                title: const Text('Take a photo'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _pickImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined, color: AppColors.primaryBlue),
                title: const Text('Choose from gallery'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _pickImage(ImageSource.gallery);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final xFile = await _picker.pickImage(source: source, maxWidth: 1200, imageQuality: 90);
      if (xFile == null) return;
      final rawBytes = await xFile.readAsBytes();
      if (!mounted) return;

      // Let the user crop/zoom before we upload anything.
      final cropped = await showDialog<Uint8List>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _ImageCropDialog(sourceBytes: rawBytes),
      );
      if (cropped == null) return; // user hit Cancel

      setState(() {
        _pickedImageBytes = cropped;
        _isUploadingPhoto = true;
      });

      // A hung upload (e.g. Storage not set up, network stall) used to spin
      // forever — now it times out and surfaces a clear error instead.
      await AuthService.updateProfilePhoto(cropped).timeout(
        const Duration(seconds: 20),
        onTimeout: () => throw TimeoutException(
          'Upload timed out. Check your internet connection and make sure '
              'Firebase Storage is enabled for this project in the Firebase console.',
        ),
      );
      if (!mounted) return;
      setState(() => _isUploadingPhoto = false);
      _snack('Profile picture updated');
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUploadingPhoto = false);
      _snack(
        e is FirebaseAuthException
            ? AuthService.friendlyError(e)
            : (e is TimeoutException ? e.message! : 'Could not update photo: $e'),
        isError: true,
      );
    }
  }

  // ---------------------------------------------------------------------
  // Username
  // ---------------------------------------------------------------------

  Future<void> _saveName() async {
    final newName = _nameController.text.trim();
    if (newName.isEmpty) {
      _snack('Name cannot be empty', isError: true);
      return;
    }
    if (newName == (AuthService.currentUser?.displayName ?? '')) return;

    setState(() => _isSavingName = true);
    try {
      await AuthService.updateDisplayName(newName);
      if (!mounted) return;
      setState(() => _isSavingName = false);
      _snack('Name updated');
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSavingName = false);
      _snack(e is FirebaseAuthException ? AuthService.friendlyError(e) : 'Could not update name: $e',
          isError: true);
    }
  }

  // ---------------------------------------------------------------------
  // Change password
  // ---------------------------------------------------------------------

  Future<void> _changePassword() async {
    setState(() => _currentPasswordError = null);
    if (!_passwordFormKey.currentState!.validate()) return;

    setState(() => _isChangingPassword = true);
    try {
      await AuthService.changePassword(
        currentPassword: _currentPasswordController.text,
        newPassword: _newPasswordController.text,
      );
      if (!mounted) return;
      _currentPasswordController.clear();
      _newPasswordController.clear();
      _confirmPasswordController.clear();
      setState(() => _isChangingPassword = false);
      _snack('Password updated');
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _isChangingPassword = false);
      if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        setState(() => _currentPasswordError = 'Current password is incorrect');
        _passwordFormKey.currentState!.validate();
      } else {
        _snack(AuthService.friendlyError(e), isError: true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isChangingPassword = false);
      _snack('Could not update password: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService.currentUser;
    final avatarImage = _pickedImageBytes != null
        ? MemoryImage(_pickedImageBytes!) as ImageProvider
        : (user?.photoURL?.trim().isNotEmpty == true ? NetworkImage(user!.photoURL!) : null);

    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textDark,
        title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Profile picture
              Center(
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 48,
                      backgroundColor: const Color(0xFFEFF3F8),
                      backgroundImage: avatarImage,
                      child: avatarImage == null
                          ? const Icon(Icons.person, size: 48, color: AppColors.primaryBlue)
                          : null,
                    ),
                    if (_isUploadingPhoto)
                      Positioned.fill(
                        child: CircleAvatar(
                          radius: 48,
                          backgroundColor: Colors.black.withOpacity(0.35),
                          child: const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                          ),
                        ),
                      ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: GestureDetector(
                        onTap: _isUploadingPhoto ? null : _showPhotoOptions,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: AppColors.primaryBlue,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: const Icon(Icons.camera_alt, size: 16, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // Username
              _SectionCard(
                title: 'Username',
                icon: Icons.badge_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _nameController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        hintText: 'Your name',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: ElevatedButton(
                        onPressed: _isSavingName ? null : _saveName,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryBlue,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: _isSavingName
                            ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                            : const Text('Save'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Change password
              _SectionCard(
                title: 'Change Password',
                icon: Icons.lock_outline,
                child: Form(
                  key: _passwordFormKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        controller: _currentPasswordController,
                        obscureText: _obscureCurrent,
                        decoration: InputDecoration(
                          labelText: 'Current password',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(_obscureCurrent ? Icons.visibility_off : Icons.visibility),
                            onPressed: () => setState(() => _obscureCurrent = !_obscureCurrent),
                          ),
                        ),
                        validator: (v) {
                          if (_currentPasswordError != null) return _currentPasswordError;
                          if (v == null || v.isEmpty) return 'Enter your current password';
                          return null;
                        },
                        onChanged: (_) {
                          if (_currentPasswordError != null) {
                            setState(() => _currentPasswordError = null);
                          }
                        },
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _newPasswordController,
                        obscureText: _obscureNew,
                        decoration: InputDecoration(
                          labelText: 'New password',
                          prefixIcon: const Icon(Icons.lock_reset_outlined),
                          suffixIcon: IconButton(
                            icon: Icon(_obscureNew ? Icons.visibility_off : Icons.visibility),
                            onPressed: () => setState(() => _obscureNew = !_obscureNew),
                          ),
                        ),
                        validator: (v) => Validators.passwordError(v ?? ''),
                      ),
                      const SizedBox(height: 10),
                      PasswordStrengthMeter(password: _newPasswordController.text),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _confirmPasswordController,
                        obscureText: _obscureConfirm,
                        decoration: InputDecoration(
                          labelText: 'Confirm new password',
                          prefixIcon: const Icon(Icons.lock_person_outlined),
                          suffixIcon: IconButton(
                            icon: Icon(_obscureConfirm ? Icons.visibility_off : Icons.visibility),
                            onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                          ),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Re-enter your new password';
                          if (v != _newPasswordController.text) return 'Passwords do not match';
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isChangingPassword ? null : _changePassword,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryBlue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: _isChangingPassword
                              ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                              : const Text('Update Password'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  const _SectionCard({required this.title, required this.icon, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.primaryBlue),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// Lets the user pan/zoom [sourceBytes] inside a circular crop guide, then
/// rasterizes exactly what's visible into new PNG bytes. Pure Flutter (no
/// native crop plugin), so it behaves identically on web, Android and iOS.
/// Pops with the cropped `Uint8List` on Apply, or `null` on Cancel.
class _ImageCropDialog extends StatefulWidget {
  final Uint8List sourceBytes;
  const _ImageCropDialog({required this.sourceBytes});

  @override
  State<_ImageCropDialog> createState() => _ImageCropDialogState();
}

class _ImageCropDialogState extends State<_ImageCropDialog> {
  static const double _viewportSize = 260;
  static const double _minScale = 1.0;
  static const double _maxScale = 4.0;

  final GlobalKey _boundaryKey = GlobalKey();
  final TransformationController _controller = TransformationController();
  double _scale = _minScale;
  bool _isProcessing = false;

  void _onSliderChanged(double value) {
    setState(() {
      _scale = value;
      _controller.value = Matrix4.identity()..scale(value);
    });
  }

  void _onInteractionUpdate(ScaleUpdateDetails details) {
    final current = _controller.value.getMaxScaleOnAxis();
    if ((current - _scale).abs() > 0.01) {
      setState(() => _scale = current.clamp(_minScale, _maxScale));
    }
  }

  void _reset() {
    setState(() {
      _scale = _minScale;
      _controller.value = Matrix4.identity();
    });
  }

  Future<void> _apply() async {
    setState(() => _isProcessing = true);
    try {
      // Give the widget tree a frame to settle before capturing.
      await Future.delayed(const Duration(milliseconds: 20));
      final boundary = _boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData!.buffer.asUint8List();
      if (!mounted) return;
      Navigator.of(context).pop(bytes);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not crop image: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Edit Photo', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: _isProcessing ? null : () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Drag to reposition, use the slider to zoom.',
              style: TextStyle(fontSize: 12, color: AppColors.textGrey),
            ),
            const SizedBox(height: 16),

            // Crop viewport
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                width: _viewportSize,
                height: _viewportSize,
                color: Colors.black,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    RepaintBoundary(
                      key: _boundaryKey,
                      child: ClipOval(
                        child: InteractiveViewer(
                          transformationController: _controller,
                          minScale: _minScale,
                          maxScale: _maxScale,
                          boundaryMargin: const EdgeInsets.all(200),
                          onInteractionUpdate: _onInteractionUpdate,
                          child: Image.memory(
                            widget.sourceBytes,
                            width: _viewportSize,
                            height: _viewportSize,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                    IgnorePointer(
                      child: Container(
                        width: _viewportSize,
                        height: _viewportSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Zoom slider
            Row(
              children: [
                const Icon(Icons.zoom_out, size: 18, color: AppColors.textGrey),
                Expanded(
                  child: Slider(
                    value: _scale,
                    min: _minScale,
                    max: _maxScale,
                    activeColor: AppColors.primaryBlue,
                    onChanged: _isProcessing ? null : _onSliderChanged,
                  ),
                ),
                const Icon(Icons.zoom_in, size: 18, color: AppColors.textGrey),
              ],
            ),
            const SizedBox(height: 8),

            // Cancel / Reset / Apply
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isProcessing ? null : () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isProcessing ? null : _reset,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Reset'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isProcessing ? null : _apply,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: _isProcessing
                        ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                        : const Text('Apply'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
