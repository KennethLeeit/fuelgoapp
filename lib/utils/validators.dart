class Validators {
  static final RegExp _emailRegex =
      RegExp(r'^[\w\.\-]+@[\w\-]+\.[a-zA-Z]{2,}(\.[a-zA-Z]{2,})?$');

  static bool isValidEmail(String value) => _emailRegex.hasMatch(value.trim());

  static String? emailError(String value) {
    if (value.trim().isEmpty) return 'Email is required';
    if (!isValidEmail(value)) return 'Enter a valid email address';
    return null;
  }

  static const int minLength = 8;
  static final RegExp _symbolRegex =
      RegExp(r'[!@#$%^&*(),.?":{}|<>_\-+=\[\]\\/;~`]');
  static final RegExp _upperRegex = RegExp(r'[A-Z]');
  static final RegExp _lowerRegex = RegExp(r'[a-z]');
  static final RegExp _digitRegex = RegExp(r'[0-9]');

  static bool hasMinLength(String v) => v.length >= minLength;
  static bool hasSymbol(String v) => _symbolRegex.hasMatch(v);
  static bool hasUpper(String v) => _upperRegex.hasMatch(v);
  static bool hasLower(String v) => _lowerRegex.hasMatch(v);
  static bool hasDigit(String v) => _digitRegex.hasMatch(v);

  static String? passwordError(String value) {
    if (value.isEmpty) return 'Password is required';
    if (!hasMinLength(value)) return 'Use at least $minLength characters';
    return null;
  }

  static int strengthScore(String value) {
    if (value.isEmpty) return 0;
    int score = 0;
    if (hasMinLength(value)) score++;
    if (value.length >= 12) score++;
    if (hasSymbol(value)) score++;
    final varietyCount = [hasUpper(value), hasLower(value), hasDigit(value)]
        .where((v) => v)
        .length;
    if (varietyCount >= 2) score++;
    if (varietyCount >= 3 && value.length >= 10) score++;
    return score.clamp(0, 4);
  }

  static String strengthLabel(int score) {
    switch (score) {
      case 0:
      case 1:
        return 'Weak';
      case 2:
        return 'Fair';
      case 3:
        return 'Good';
      default:
        return 'Strong';
    }
  }
}
