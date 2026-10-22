import 'package:flutter/material.dart';

import '../../core/storage/avatar_service.dart';
import '../../core/theme/criptivo_theme.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  Map<String, dynamic>? _profile;
  bool _loading = true;
  bool _uploading = false;
  final _nameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final p = await AvatarService.getMyProfile();
      if (!mounted) return;
      setState(() {
        _profile = p;
        _nameController.text = p?['display_name'] as String? ?? '';
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Грешка: $e')),
      );
    }
  }

  Future<void> _changeAvatar() async {
    final file = await AvatarService.pickImage();
    if (file == null) return;

    setState(() => _uploading = true);
    try {
      final url = await AvatarService.updateMyAvatar(file);
      if (!mounted) return;
      setState(() {
        _profile = {...?_profile, 'avatar_url': url};
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Снимката е обновена')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Качването неуспешно: $e')),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _saveName() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    try {
      await AvatarService.updateDisplayName(name);
      if (!mounted) return;
      setState(() {
        _profile = {...?_profile, 'display_name': name};
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Името е запазено')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Грешка: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final avatarUrl = _profile?['avatar_url'] as String?;
    final username = _profile?['username'] as String? ?? '';

    return Scaffold(
      backgroundColor: CriptivoColors.background,
      appBar: AppBar(title: const Text('Профил')),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: CriptivoColors.neon),
            )
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Center(
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 56,
                        backgroundColor: CriptivoColors.surfaceLight,
                        backgroundImage: avatarUrl != null
                            ? NetworkImage(avatarUrl)
                            : null,
                        child: avatarUrl == null
                            ? Text(
                                username.isNotEmpty
                                    ? username[0].toUpperCase()
                                    : '?',
                                style: const TextStyle(
                                  fontSize: 36,
                                  color: CriptivoColors.neon,
                                ),
                              )
                            : null,
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Material(
                          color: CriptivoColors.neon,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: _uploading ? null : _changeAvatar,
                            child: SizedBox(
                              width: 40,
                              height: 40,
                              child: Center(
                                child: _uploading
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.black,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.camera_alt_rounded,
                                        size: 20,
                                        color: Colors.black,
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    '@$username',
                    style: const TextStyle(
                      color: CriptivoColors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: _nameController,
                  style: const TextStyle(color: CriptivoColors.textPrimary),
                  decoration: const InputDecoration(
                    labelText: 'Display name',
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _saveName,
                    child: const Text('Запази името'),
                  ),
                ),
              ],
            ),
    );
  }
}
