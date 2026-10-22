import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/auth_service.dart';
import '../../core/chat/chat_service.dart';
import '../../core/crypto/key_manager.dart';
import '../../core/theme/criptivo_theme.dart';
import '../chat/chat_page.dart';
import '../chat/new_chat_page.dart';
import '../profile/profile_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Map<String, dynamic>> _conversations = [];
  bool _loading = true;

  final Set<String> _unread = {};
  final Set<String> _notifiedMessageIds = {};

  /// Разговор, отворен в момента — без известия за него
  String? _activeConversationId;

  RealtimeChannel? _messagesChannel;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _forceSyncKey();
    await _loadConversations();
    _subscribeToNewMessages();
    _startPoll();
  }

  Future<void> _forceSyncKey() async {
    final user = AuthService.currentUser;
    if (user == null) return;

    try {
      await KeyManager.ensureKeys();
      final local = await KeyManager.getPublicKeyBase64();
      if (local == null) return;

      await Supabase.instance.client
          .from('profiles')
          .update({
            'public_key': local,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', user.id);
    } catch (e) {
      debugPrint('Key sync failed: $e');
    }
  }

  void _clearNotificationUi() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
  }

  void _subscribeToNewMessages() {
    final myId = AuthService.currentUser?.id;
    if (myId == null) return;

    _messagesChannel?.unsubscribe();
    _messagesChannel = Supabase.instance.client
        .channel('home-messages-$myId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (payload) {
            final row = Map<String, dynamic>.from(payload.newRecord);
            final senderId = row['sender_id'] as String?;
            final conversationId = row['conversation_id'] as String?;
            final messageId = row['id'] as String?;

            if (senderId == null ||
                conversationId == null ||
                senderId == myId) {
              return;
            }

            if (conversationId == _activeConversationId) {
              return;
            }

            if (messageId != null && _notifiedMessageIds.contains(messageId)) {
              return;
            }
            if (messageId != null) {
              _notifiedMessageIds.add(messageId);
            }

            _onIncomingMessage(conversationId);
          },
        )
        .subscribe();
  }

  void _startPoll() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      _loadConversations(quiet: true);
    });
  }

  void _onIncomingMessage(String conversationId) {
    if (!mounted) return;
    if (conversationId == _activeConversationId) return;

    setState(() {
      _unread.add(conversationId);
    });

    final conv = _conversations.cast<Map<String, dynamic>?>().firstWhere(
          (c) => c?['conversation_id'] == conversationId,
          orElse: () => null,
        );

    final other = conv?['other_user'] as Map<String, dynamic>?;
    final name = other?['display_name'] ?? other?['username'] ?? 'Някой';

    _clearNotificationUi();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Ново съобщение от $name'),
        backgroundColor: CriptivoColors.surfaceLight,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        action: conv == null
            ? null
            : SnackBarAction(
                label: 'Отвори',
                textColor: CriptivoColors.neon,
                onPressed: () {
                  _clearNotificationUi();
                  _openChat(conv);
                },
              ),
      ),
    );

    _loadConversations(quiet: true);
  }

  Future<Map<String, dynamic>> _freshOtherUser(
    Map<String, dynamic>? other,
    String? otherUserId,
  ) async {
    final id = other?['id'] as String? ?? otherUserId;
    if (id == null) return {...?other};

    try {
      final row = await Supabase.instance.client
          .from('profiles')
          .select('id, username, display_name, avatar_url, public_key')
          .eq('id', id)
          .maybeSingle();

      if (row != null) {
        return Map<String, dynamic>.from(row);
      }
    } catch (e) {
      debugPrint('Failed to refresh other user: $e');
    }

    return {...?other, 'id': id};
  }

  Future<void> _openChat(Map<String, dynamic> item) async {
    final conversationId = item['conversation_id'] as String;

    _clearNotificationUi();
    setState(() {
      _unread.remove(conversationId);
      _activeConversationId = conversationId;
    });

    await _forceSyncKey();

    final other = item['other_user'] as Map<String, dynamic>?;
    final otherId = other?['id'] as String? ?? item['other_user_id'] as String?;
    final freshOther = await _freshOtherUser(other, otherId);

    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ChatPage(conversationId: conversationId, otherUser: freshOther),
      ),
    );

    if (!mounted) return;
    setState(() {
      _activeConversationId = null;
      _unread.remove(conversationId);
    });
    _clearNotificationUi();

    await _loadConversations();
  }

  Future<void> _loadConversations({bool quiet = false}) async {
    if (!mounted) return;
    if (!quiet) setState(() => _loading = true);

    try {
      final list = await ChatService.getMyConversations();
      if (!mounted) return;

      if (quiet && _conversations.isNotEmpty) {
        for (final item in list) {
          final id = item['conversation_id'] as String?;
          if (id == null) continue;
          if (id == _activeConversationId) continue;

          final old = _conversations.cast<Map<String, dynamic>?>().firstWhere(
                (c) => c?['conversation_id'] == id,
                orElse: () => null,
              );

          final newAt = item['last_message_at'] as String?;
          final oldAt = old?['last_message_at'] as String?;

          if (newAt != null && newAt != oldAt && !_unread.contains(id)) {
            setState(() => _unread.add(id));

            final other = item['other_user'] as Map<String, dynamic>?;
            final name =
                other?['display_name'] ?? other?['username'] ?? 'Някой';

            _clearNotificationUi();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Ново съобщение от $name'),
                backgroundColor: CriptivoColors.surfaceLight,
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 3),
                action: SnackBarAction(
                  label: 'Отвори',
                  textColor: CriptivoColors.neon,
                  onPressed: () {
                    _clearNotificationUi();
                    _openChat(item);
                  },
                ),
              ),
            );
          }
        }
      }

      setState(() {
        _conversations = list;
        if (!quiet) _loading = false;
      });
    } catch (e) {
      debugPrint('Грешка при зареждане на разговори: $e');
      if (!mounted) return;
      if (!quiet) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _messagesChannel?.unsubscribe();
    super.dispose();
  }

  Widget _buildAvatar(Map<String, dynamic>? other, String name) {
    final avatarUrl = other?['avatar_url'] as String?;
    final hasAvatar = avatarUrl != null && avatarUrl.isNotEmpty;

    return CircleAvatar(
      backgroundColor: CriptivoColors.surfaceLight,
      backgroundImage: hasAvatar ? NetworkImage(avatarUrl) : null,
      child: hasAvatar
          ? null
          : Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: const TextStyle(color: CriptivoColors.neon),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CriptivoColors.background,
      appBar: AppBar(
        title: const Text('Criptivo'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: 'Профил',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfilePage()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Изход',
            onPressed: () => AuthService.signOut(),
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: CriptivoColors.neon),
            )
          : _conversations.isEmpty
              ? const Center(
                  child: Text(
                    'Няма разговори.\nНатисни + за да започнеш нов чат.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: CriptivoColors.textSecondary),
                  ),
                )
              : RefreshIndicator(
                  color: CriptivoColors.neon,
                  onRefresh: () => _loadConversations(),
                  child: ListView.builder(
                    itemCount: _conversations.length,
                    itemBuilder: (context, index) {
                      final item = _conversations[index];
                      final conversationId =
                          item['conversation_id'] as String? ?? '';
                      final other =
                          item['other_user'] as Map<String, dynamic>?;
                      final name = other?['display_name'] ??
                          other?['username'] ??
                          'Unknown';
                      final isUnread = _unread.contains(conversationId);

                      return ListTile(
                        leading: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            _buildAvatar(other, name),
                            if (isUnread)
                              Positioned(
                                right: -2,
                                top: -2,
                                child: Container(
                                  width: 12,
                                  height: 12,
                                  decoration: const BoxDecoration(
                                    color: CriptivoColors.neon,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        title: Text(
                          name,
                          style: TextStyle(
                            color: CriptivoColors.textPrimary,
                            fontWeight: isUnread
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                        subtitle: Text(
                          isUnread
                              ? 'Ново съобщение'
                              : (other?['username'] ?? ''),
                          style: TextStyle(
                            color: isUnread
                                ? CriptivoColors.neon
                                : CriptivoColors.textSecondary,
                          ),
                        ),
                        trailing: isUnread
                            ? const Icon(
                                Icons.mark_email_unread,
                                color: CriptivoColors.neon,
                                size: 20,
                              )
                            : null,
                        onTap: () => _openChat(item),
                      );
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const NewChatPage()),
          );
          _loadConversations();
        },
        child: const Icon(Icons.chat),
      ),
    );
  }
}
