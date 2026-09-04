import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' show Persistence;
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../services/auth_service.dart';
import '../services/vehicle_preference_service.dart';
import '../services/favourites_service.dart';
import '../services/location_service.dart';
import '../services/station_cache_service.dart';
import '../utils/validators.dart';
import 'register_screen.dart';
import 'main_nav_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const _rememberedEmailKey = 'remembered_email';
  // Plaintext on-device storage (SharedPreferences) — same tradeoff as a
  // browser's "save password" feature. Fine for a personal device; if this
  // needs to be hardened later, swap this specific read/write pair for the
  // flutter_secure_storage package (Keychain/Keystore-backed) without
  // touching anything else in this screen.
  static const _rememberedPasswordKey = 'remembered_password';
  static const _rememberMeKey = 'remember_me_enabled';

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordFocusNode = FocusNode();
  bool _obscure = true;
  bool _submitting = false;
  bool _submitted = false;
  // Off by default — only turns on (and only then starts saving
  // credentials) once the user explicitly opts in.
  bool _rememberMe = false;
  String? _formError;

  @override
  void initState() {
    super.initState();
    // Get the GPS fix / permission prompt started now, while the user is
    // still typing their credentials, so the map has a location ready to
    // go the moment it's opened instead of waiting on it from scratch.
    LocationService.prewarm();
    // Also warm the nearby fuel/EV cache using that same location, so the
    // map and station lists are often already populated by the time the
    // user logs in and reaches the main app — not just the location fix.
    StationCacheService.instance.prefetchNearby();
    _loadRememberedCredentials();
  }

  @override
  void dispose() {
    _passwordFocusNode.dispose();
    super.dispose();
  }

  // Logging out intentionally does NOT clear these — a remembered login
  // should still be sitting here pre-filled the next time this screen is
  // reached, exactly like it would right after being saved. Only an
  // explicit uncheck-then-login (see _persistRememberedCredentials) clears
  // it.
  Future<void> _loadRememberedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final rememberMe = prefs.getBool(_rememberMeKey) ?? false;
    if (!rememberMe || !mounted) return;
    final savedEmail = prefs.getString(_rememberedEmailKey);
    final savedPassword = prefs.getString(_rememberedPasswordKey);
    setState(() {
      _rememberMe = true;
      if (savedEmail != null) _emailController.text = savedEmail;
      if (savedPassword != null) _passwordController.text = savedPassword;
    });
  }

  Future<void> _persistRememberedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    if (_rememberMe) {
      await prefs.setBool(_rememberMeKey, true);
      await prefs.setString(_rememberedEmailKey, _emailController.text.trim());
      await prefs.setString(_rememberedPasswordKey, _passwordController.text);
    } else {
      await prefs.setBool(_rememberMeKey, false);
      await prefs.remove(_rememberedEmailKey);
      await prefs.remove(_rememberedPasswordKey);
    }
  }

  String? get _emailError => _submitted ? Validators.emailError(_emailController.text) : null;
  String? get _passwordError => _submitted && _passwordController.text.isEmpty ? 'Password is required' : null;

  Future<void> _login() async {
    setState(() {
      _submitted = true;
      _formError = null;
    });
    if (_emailError != null || _passwordError != null) return;

    setState(() => _submitting = true);
    try {
      // "Remember me" controls whether the session survives closing the
      // browser tab entirely (web only — Firebase Auth on mobile always
      // persists locally regardless, there's no equivalent toggle there).
      if (kIsWeb) {
        try {
          await AuthService.setPersistence(_rememberMe ? Persistence.LOCAL : Persistence.SESSION);
        } catch (_) {
          // Non-fatal — sign-in still proceeds with whatever the default is.
        }
      }

      final user = await AuthService.signIn(email: _emailController.text, password: _passwordController.text);

      // Only remember credentials once they're confirmed correct — saving
      // before this point risked remembering a mistyped password.
      await _persistRememberedCredentials();

      final profile = await AuthService.getProfile(user.uid);

      if (!mounted) return;

      // Hydrate the local vehicle-preference and favourites caches from
      // the account's saved data so they carry over between sessions.
      if (profile != null) {
        VehiclePreferenceService.instance.hydrate(
          drivesFuel: profile['drivesFuel'] ?? true,
          drivesEV: profile['drivesEV'] ?? true,
        );
        FavouritesService.instance.hydrate(
          fuelIds: Set<String>.from(profile['favouriteFuelIds'] ?? const []),
          evIds: Set<String>.from(profile['favouriteEvIds'] ?? const []),
        );
        final lastLat = profile['lastLat'];
        final lastLng = profile['lastLng'];
        if (lastLat is num && lastLng is num) {
          LocationService.rememberLocation(AppLatLng(lastLat.toDouble(), lastLng.toDouble()));
        }
      }

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MainNavScreen()),
        (route) => false,
      );
    } catch (e) {
      setState(() => _formError = AuthService.friendlyError(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _forgotPassword() async {
    final controller = TextEditingController(text: _emailController.text);
    final email = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Password'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(hintText: 'Enter your account email'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Send Link')),
        ],
      ),
    );
    if (email == null || email.trim().isEmpty) return;
    if (!Validators.isValidEmail(email)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid email first')));
      }
      return;
    }
    try {
      await AuthService.sendPasswordResetEmail(email);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Password reset email sent to $email')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AuthService.friendlyError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Container(
            height: 260,
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1FA98D), Color(0xFF57C4E5)],
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned(
                  top: 16,
                  left: 20,
                  child: SafeArea(
                    child: Row(
                      children: const [
                        Text('Fuel',
                            style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                        Text('Go',
                            style: TextStyle(color: Color(0xFF0E1F63), fontSize: 22, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
                const Icon(Icons.ev_station_rounded, color: Colors.white, size: 90),
              ],
            ),
          ),
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: const BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Welcome Back!',
                        style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).textTheme.bodyLarge?.color ?? AppColors.textDark)),
                    const SizedBox(height: 6),
                    const Text('Login to continue your smart mobility journey.', style: TextStyle(color: AppColors.textGrey)),
                    const SizedBox(height: 24),
                    if (_formError != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(10)),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.error_outline, color: Colors.red, size: 18),
                            const SizedBox(width: 8),
                            Expanded(child: Text(_formError!, style: const TextStyle(color: Colors.red, fontSize: 13))),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    const Text('Email', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _passwordFocusNode.requestFocus(),
                      decoration: InputDecoration(
                        hintText: 'Enter your email',
                        prefixIcon: const Icon(Icons.email_outlined),
                        errorText: _emailError,
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text('Password', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _passwordController,
                      focusNode: _passwordFocusNode,
                      obscureText: _obscure,
                      textInputAction: TextInputAction.done,
                      onChanged: (_) => setState(() {}),
                      // Enter/Return in the password field submits the form,
                      // same as tapping the Login button.
                      onSubmitted: (_) => _submitting ? null : _login(),
                      decoration: InputDecoration(
                        hintText: 'Enter your password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        errorText: _passwordError,
                        suffixIcon: IconButton(
                          icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        InkWell(
                          onTap: () => setState(() => _rememberMe = !_rememberMe),
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: Checkbox(
                                    value: _rememberMe,
                                    onChanged: (v) => setState(() => _rememberMe = v ?? false),
                                    activeColor: AppColors.primaryBlue,
                                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Text('Remember me', style: TextStyle(fontSize: 13, color: AppColors.textDark)),
                              ],
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: _forgotPassword,
                          child: const Text('Forgot Password?'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ElevatedButton(
                      onPressed: _submitting ? null : _login,
                      child: _submitting
                          ? const SizedBox(
                              width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Login'),
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text("Don't have an account? "),
                          GestureDetector(
                            onTap: () => Navigator.of(context)
                                .push(MaterialPageRoute(builder: (_) => const RegisterScreen())),
                            child: const Text('Register',
                                style: TextStyle(color: AppColors.primaryBlue, fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
