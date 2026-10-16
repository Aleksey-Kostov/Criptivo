import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/crypto/key_manager.dart';
import '../../core/crypto/safety_number.dart';
import '../../core/theme/criptivo_theme.dart';

Future<void> showSafetyNumberSheet({
  required BuildContext context,
  required String theirPublicKeyBase64,
  required String otherUserName,
}) async {
  final myPublicKey = await KeyManager.getPublicKeyBase64();

  if (myPublicKey == null || myPublicKey.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Липсва твоят public key')));
    }
    return;
  }

  final number = await SafetyNumber.generate(
    myPublicKeyBase64: myPublicKey,
    theirPublicKeyBase64: theirPublicKeyBase64,
  );

  final formatted = SafetyNumber.format(number);

  if (!context.mounted) return;

  showModalBottomSheet(
    context: context,
    backgroundColor: CriptivoColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    isScrollControlled: true,
    builder: (context) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: CriptivoColors.neon.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),

            // Title
            Text(
              'Safety Number',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: CriptivoColors.neon,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'с $otherUserName',
              style: const TextStyle(
                color: CriptivoColors.textSecondary,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 24),

            // Explanation
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: CriptivoColors.surfaceLight,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: CriptivoColors.neon.withValues(alpha: 0.2),
                ),
              ),
              child: const Text(
                'Сравни този номер с този на другия човек '
                '(на живо, по телефона или лично). '
                'Ако съвпадат – връзката е защитена и няма man-in-the-middle атака.',
                style: TextStyle(
                  color: CriptivoColors.textSecondary,
                  fontSize: 13,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 28),

            // The number itself
            SelectableText(
              formatted,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 18,
                letterSpacing: 1.2,
                height: 1.6,
                color: CriptivoColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),

            // Copy button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: formatted));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Safety Number копиран'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('Копирай номера'),
              ),
            ),
            const SizedBox(height: 12),

            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Затвори'),
            ),
          ],
        ),
      );
    },
  );
}
