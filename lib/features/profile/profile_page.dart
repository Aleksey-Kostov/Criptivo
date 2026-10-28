import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/profile/profile_privacy.dart';
import '../../core/profile/profile_service.dart';
import '../../core/storage/avatar_service.dart';
import '../../core/theme/criptivo_theme.dart';
import 'widgets/visibility_tile.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  Map<String, dynamic>? _profile;
  bool _loading = true;
  bool _saving = false;
  bool _uploading = false;

  final _nameController = TextEditingController();
  final _bioController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();

  ProfileVisibility _phoneVis = ProfileVisibility.nobody;
  ProfileVisibility _emailVis = ProfileVisibility.nobody;
  ProfileVisibility _bioVis = ProfileVisibility.everyone;
  bool _phoneSearchable = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final p = await ProfileService.getMyProfile();
      if (!mounted) return;
      setState(() {
        _profile = p;
        _nameController.text = p?['display_name'] as String? ?? '';
        _bioController.text = p?['bio'] as String? ?? '';
        _phoneController.text = p?['phone'] as String? ?? '';
        _emailController.text = p?['email'] as String? ?? '';
        _phoneVis = ProfileVisibility.fromDb(p?['phone_visibility'] as String?);
        _emailVis = ProfileVisibility.fromDb(p?['email_visibility'] as String?);
        _bioVis = ProfileVisibility.fromDb(p?['bio_visibility'] as String?);
        _phoneSearchable = p?['phone_searchable'] == true;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Грешка: $e')));
    }
  }

  Future<void> _changeAvatar() async {
    final file = await AvatarService.pickImage();
    if (file == null) return;
    setState(() => _uploading = true);
    try {
      final url = await AvatarService.updateMyAvatar(file);
      if (!mounted) return;
      setState(() => _profile = {...?_profile, 'avatar_url': url});
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Снимката е обновена')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Качване: $e')));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _saveProfile() async {
    setState(() => _saving = true);
    try {
      await ProfileService.updateDisplayName(_nameController.text);
      await ProfileService.updateBio(_bioController.text);
      await ProfileService.updatePhone(
        phone: _phoneController.text.trim().isEmpty
            ? null
            : _phoneController.text,
        visibility: _phoneVis,
        searchable: _phoneSearchable,
      );
      await ProfileService.updatePrivacy(
        phoneVisibility: _phoneVis,
        emailVisibility: _emailVis,
        bioVisibility: _bioVis,
        phoneSearchable: _phoneSearchable,
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Профилът е запазен')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _changeEmail() async {
    final next = _emailController.text.trim().toLowerCase();
    final current = (_profile?['email'] as String?)?.toLowerCase() ?? '';
    if (next.isEmpty || next == current) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Въведи нов email')));
      return;
    }
    setState(() => _saving = true);
    try {
      await ProfileService.requestEmailChange(next);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Изпратихме линк за потвърждение на новия email. '
            'Провери кутията си.',
          ),
          duration: Duration(seconds: 5),
        ),
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final avatarUrl = _profile?['avatar_url'] as String?;
    final username = _profile?['username'] as String? ?? '';

    return Scaffold(
      backgroundColor: CriptivoColors.background,
      appBar: AppBar(
        title: const Text('Профил'),
        actions: [
          TextButton(
            onPressed: _saving || _loading ? null : _saveProfile,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: CriptivoColors.neon,
                    ),
                  )
                : const Text('Запази'),
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: CriptivoColors.neon),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
              children: [
                // Avatar
                Center(
                  child: Stack(
                    children: [
                      Container(
                        width: 112,
                        height: 112,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: CriptivoColors.neon.withValues(alpha: 0.35),
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: CriptivoColors.neon.withValues(
                                alpha: 0.12,
                              ),
                              blurRadius: 20,
                            ),
                          ],
                        ),
                        child: CircleAvatar(
                          radius: 54,
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
                                    fontWeight: FontWeight.w700,
                                  ),
                                )
                              : null,
                        ),
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
                const SizedBox(height: 10),
                Center(
                  child: Text(
                    '@$username',
                    style: const TextStyle(
                      color: CriptivoColors.neon,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 28),

                _sectionTitle('Основни'),
                TextField(
                  controller: _nameController,
                  style: const TextStyle(color: CriptivoColors.textPrimary),
                  decoration: const InputDecoration(
                    labelText: 'Display name',
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _bioController,
                  style: const TextStyle(color: CriptivoColors.textPrimary),
                  maxLines: 3,
                  maxLength: 160,
                  decoration: const InputDecoration(
                    labelText: 'За мен',
                    alignLabelWithHint: true,
                    prefixIcon: Icon(Icons.info_outline),
                  ),
                ),
                VisibilityTile(
                  title: 'Видимост на „За мен“',
                  subtitle: 'Дали другите виждат биографията',
                  value: _bioVis,
                  onChanged: (v) => setState(() => _bioVis = v),
                ),

                const SizedBox(height: 8),
                _sectionTitle('Телефон'),
                TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(color: CriptivoColors.textPrimary),
                  decoration: const InputDecoration(
                    labelText: 'Телефон (по желание)',
                    hintText: '+3598...',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                ),
                const SizedBox(height: 10),
                VisibilityTile(
                  title: 'Видимост на телефона',
                  subtitle: 'Кой вижда номера в профила',
                  value: _phoneVis,
                  onChanged: (v) => setState(() => _phoneVis = v),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: CriptivoColors.neon,
                  title: const Text(
                    'Намерим по телефон',
                    style: TextStyle(color: CriptivoColors.textPrimary),
                  ),
                  subtitle: const Text(
                    'Други могат да те намерят при търсене по номер',
                    style: TextStyle(
                      color: CriptivoColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  value: _phoneSearchable,
                  onChanged: (v) => setState(() => _phoneSearchable = v),
                ),

                const SizedBox(height: 8),
                _sectionTitle('Email'),
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(color: CriptivoColors.textPrimary),
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _saving ? null : _changeEmail,
                    icon: const Icon(Icons.mark_email_read_outlined),
                    label: const Text('Смени email (с потвърждение)'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: CriptivoColors.neon,
                      side: BorderSide(
                        color: CriptivoColors.neon.withValues(alpha: 0.5),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                VisibilityTile(
                  title: 'Видимост на email',
                  subtitle: 'За бъдеща публична карта (по подразбиране скрит)',
                  value: _emailVis,
                  onChanged: (v) => setState(() => _emailVis = v),
                ),

                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _saveProfile,
                    child: Text(_saving ? 'Запис…' : 'Запази профила'),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _sectionTitle(String t) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 6),
      child: Text(
        t,
        style: const TextStyle(
          color: CriptivoColors.neon,
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}
