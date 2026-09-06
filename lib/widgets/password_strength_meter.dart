import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/validators.dart';

class PasswordStrengthMeter extends StatelessWidget {
  final String password;
  const PasswordStrengthMeter({super.key, required this.password});

  @override
  Widget build(BuildContext context) {
    final score = Validators.strengthScore(password);
    final label = Validators.strengthLabel(score);
    final color = _colorFor(score);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Row(
                children: List.generate(4, (i) {
                  final filled = i < score;
                  return Expanded(
                    child: Container(
                      margin: EdgeInsets.only(right: i == 3 ? 0 : 4),
                      height: 5,
                      decoration: BoxDecoration(
                        color: filled ? color : const Color(0xFFE5E7EB),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              password.isEmpty ? '' : label,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: color),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            _rule('8+ characters', Validators.hasMinLength(password)),
            _rule('Symbol (optional)', Validators.hasSymbol(password)),
            _rule('Number', Validators.hasDigit(password)),
            _rule('Upper & lower case',
                Validators.hasUpper(password) && Validators.hasLower(password)),
          ],
        ),
      ],
    );
  }

  Widget _rule(String label, bool met) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          met ? Icons.check_circle : Icons.radio_button_unchecked,
          size: 14,
          color: met ? AppColors.evGreen : AppColors.textGrey,
        ),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                fontSize: 11,
                color: met ? AppColors.textDark : AppColors.textGrey)),
      ],
    );
  }

  Color _colorFor(int score) {
    switch (score) {
      case 0:
      case 1:
        return Colors.red;
      case 2:
        return AppColors.fuelOrange;
      case 3:
        return const Color(0xFF3B82F6);
      default:
        return AppColors.evGreen;
    }
  }
}
