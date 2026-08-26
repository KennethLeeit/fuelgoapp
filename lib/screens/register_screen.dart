import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/auth_service.dart';
import '../utils/validators.dart';
import '../widgets/password_strength_meter.dart';
import 'main_nav_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _obscure1 = true;
  bool _obscure2 = true;
  bool _submitting = false;
  bool _submitted = false; // only show field errors after first submit attempt
  String? _formError;

  String? get _nameError => _submitted && _nameController.text.trim().isEmpty ? 'Full name is required' : null;
  String? get _emailError => _submitted ? Validators.emailError(_emailController.text) : null;
  String? get _passwordError => _submitted ? Validators.passwordError(_passwordController.text) : null;
  String? get _confirmError {
    if (!_submitted) return null;
    if (_confirmController.text.isEmpty) return 'Confirm your password';
    if (_confirmController.text != _passwordController.text) return 'Passwords do not match';
    return null;
  }

  Future<void> _submit() async {
    setState(() {
      _submitted = true;
      _formError = null;
    });

    final valid = _nameError == null &&
        _emailError == null &&
        _passwordError == null &&
        _confirmError == null &&
        _nameController.text.trim().isNotEmpty;
    if (!valid) return;

    setState(() => _submitting = true);
    try {
      await AuthService.register(
        fullName: _nameController.text,
        email: _emailController.text,
        password: _passwordController.text,
      );
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MainNavScreen()),
        (route) => false,
      );
    } catch (e) {
      setState(() {
        _formError = AuthService.friendlyError(e);
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 18), onPressed: () => Navigator.pop(context)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Create Your Account', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text('Register to enjoy a personalised experience.', style: TextStyle(color: AppColors.textGrey)),
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
            const Text('Full Name', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: _nameController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Enter your full name',
                prefixIcon: const Icon(Icons.person_outline),
                errorText: _nameError,
              ),
            ),
            const SizedBox(height: 18),
            const Text('Email', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              onChanged: (_) => setState(() {}),
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
              obscureText: _obscure1,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Create a password',
                prefixIcon: const Icon(Icons.lock_outline),
                errorText: _passwordError,
                suffixIcon: IconButton(
                  icon: Icon(_obscure1 ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                  onPressed: () => setState(() => _obscure1 = !_obscure1),
                ),
              ),
            ),
            const SizedBox(height: 10),
            PasswordStrengthMeter(password: _passwordController.text),
            const SizedBox(height: 18),
            const Text('Confirm Password', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: _confirmController,
              obscureText: _obscure2,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Confirm your password',
                prefixIcon: const Icon(Icons.lock_outline),
                errorText: _confirmError,
                suffixIcon: IconButton(
                  icon: Icon(_obscure2 ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                  onPressed: () => setState(() => _obscure2 = !_obscure2),
                ),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Register'),
            ),
            const SizedBox(height: 16),
            Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Already have an account? '),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Text('Login',
                        style: TextStyle(color: AppColors.primaryBlue, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
