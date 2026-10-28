import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/profile/profile_service.dart';
import '../../../core/theme/criptivo_theme.dart';

/// Ограничена карта според privacy на другия.
class PublicProfileSheet extends StatefulWidget {
  final String userId;
  final String? fallbackName;
  final String? fallbackAvatar;

  const PublicProfileSheet({
    super.key,
    required this.userId,
    this.fallbackName,
    this.fallbackAvatar,
  });

  static Future<void> show(
    BuildContext context, {
    required String userId,
    String? fallbackName,
    String? fallbackAvatar,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: CriptivoColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => PublicProfileSheet(
        userId: userId,
        fallbackName: fallbackName,
        fallbackAvatar: fallbackAvatar,
      ),
    );
  }

  @override
  State<PublicProfileSheet> createState() => _PublicProfileSheetState();
}

class _PublicProfileSheetState extends State<PublicProfileSheet> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await ProfileService.getPublicProfile(widget.userId);
      if (!mounted) return;
      setState(() {
        _data = p;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final name =
        _data?['display_name'] as String? ??
        widget.fallbackName ??
        'Потребител';
    final username = _data?['username'] as String? ?? '';
    final avatar = _data?['avatar_url'] as String? ?? widget.fallbackAvatar;
    final phone = _data?['phone'] as String?;
    final bio = _data?['bio'] as String?;
    final email = _data?['email'] as String?;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: _loading
            ? const SizedBox(
                height: 180,
                child: Center(
                  child: CircularProgressIndicator(color: CriptivoColors.neon),
                ),
              )
            : _error != null
            ? Text(_error!, style: const TextStyle(color: CriptivoColors.error))
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: CriptivoColors.neon.withValues(alpha: 0.4),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: CriptivoColors.neon.withValues(alpha: 0.15),
                          blurRadius: 16,
                        ),
                      ],
                    ),
                    child: CircleAvatar(
                      backgroundColor: CriptivoColors.surfaceLight,
                      backgroundImage: avatar != null && avatar.isNotEmpty
                          ? NetworkImage(avatar)
                          : null,
                      child: avatar == null || avatar.isEmpty
                          ? Text(
                              initial,
                              style: const TextStyle(
                                fontSize: 32,
                                color: CriptivoColors.neon,
                                fontWeight: FontWeight.w700,
                              ),
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    name,
                    style: const TextStyle(
                      color: CriptivoColors.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (username.isNotEmpty)
                    Text(
                      '@$username',
                      style: const TextStyle(
                        color: CriptivoColors.neon,
                        fontSize: 14,
                      ),
                    ),
                  if (bio != null && bio.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text(
                      bio,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: CriptivoColors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  if (phone != null && phone.isNotEmpty)
                    _infoRow(Icons.phone_rounded, phone, copyable: true),
                  if (email != null && email.isNotEmpty)
                    _infoRow(Icons.email_outlined, email, copyable: true),
                  if ((phone == null || phone.isEmpty) &&
                      (email == null || email.isEmpty) &&
                      (bio == null || bio.isEmpty))
                    Text(
                      'Няма публична контактна информация',
                      style: TextStyle(
                        color: CriptivoColors.textSecondary.withValues(
                          alpha: 0.8,
                        ),
                        fontSize: 13,
                      ),
                    ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Затвори'),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String value, {bool copyable = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: copyable
            ? () {
                Clipboard.setData(ClipboardData(text: value));
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('Копирано')));
              }
            : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: CriptivoColors.surfaceLight,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(icon, color: CriptivoColors.neon, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  value,
                  style: const TextStyle(color: CriptivoColors.textPrimary),
                ),
              ),
              if (copyable)
                const Icon(
                  Icons.copy_rounded,
                  size: 16,
                  color: CriptivoColors.textSecondary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
