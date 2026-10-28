import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/auth_service.dart';
import '../../core/chat/chat_service.dart';
import '../../core/chat/conversation_preview_store.dart';
import '../../core/crypto/key_manager.dart';
import '../../core/theme/criptivo_theme.dart';
import '../chat/chat_page.dart';
import '../chat/new_chat_page.dart';
import '../profile/profile_page.dart';
import '../profile/widgets/public_profile_sheet.dart';

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
  final Set<String> _notifiedReactionIds = {};

  String? _activeConversationId;

  RealtimeChannel? _messagesChannel;
  RealtimeChannel? _reactionsChannel;
  Timer? _pollTimer;

  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await ConversationPreviewStore.load();
    await _forceSyncKey();
    await _loadConversations();
    _subscribeToNewMessages();
    _subscribeToReactions();
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

  String _formatLastAt(dynamic lastMessageAt) {
    if (lastMessageAt == null) return '';
    try {
      final dt = DateTime.parse(lastMessageAt.toString()).toLocal();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final day = DateTime(dt.year, dt.month, dt.day);
      final diff = today.difference(day).inDays;

      if (diff == 0) {
        final h = dt.hour.toString().padLeft(2, '0');
        final m = dt.minute.toString().padLeft(2, '0');
        return '$h:$m';
      }
      if (diff == 1) return 'Вчера';
      if (diff < 7) {
        const days = ['пн', 'вт', 'ср', 'чт', 'пт', 'сб', 'нд'];
        return days[dt.weekday - 1];
      }
      return '${dt.day}.${dt.month.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }

  List<Map<String, dynamic>> get _filteredConversations {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return _conversations;

    return _conversations.where((item) {
      final other = item['other_user'] as Map<String, dynamic>?;
      final name = (other?['display_name'] as String? ?? '').toLowerCase();
      final username = (other?['username'] as String? ?? '').toLowerCase();
      final convId = item['conversation_id'] as String? ?? '';
      final preview = (ConversationPreviewStore.get(convId)?.preview ?? '')
          .toLowerCase();
      return name.contains(q) || username.contains(q) || preview.contains(q);
    }).toList();
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

            if (conversationId == _activeConversationId) return;

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

  void _subscribeToReactions() {
    final myId = AuthService.currentUser?.id;
    if (myId == null) return;

    _reactionsChannel?.unsubscribe();
    _reactionsChannel = Supabase.instance.client
        .channel('home-reactions-$myId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'message_reactions',
          callback: (payload) async {
            final row = Map<String, dynamic>.from(payload.newRecord);
            final reactionId = row['id'] as String?;
            final messageId = row['message_id'] as String?;
            final fromUserId = row['user_id'] as String?;
            final emoji = row['emoji'] as String? ?? '👍';

            if (reactionId == null || messageId == null) return;
            if (fromUserId == myId) return;
            if (_notifiedReactionIds.contains(reactionId)) return;

            try {
              final msg = await Supabase.instance.client
                  .from('messages')
                  .select('id, sender_id, conversation_id')
                  .eq('id', messageId)
                  .maybeSingle();

              if (msg == null) return;
              if (msg['sender_id'] != myId) return;

              final conversationId = msg['conversation_id'] as String?;
              if (conversationId == null) return;
              if (conversationId == _activeConversationId) return;

              _notifiedReactionIds.add(reactionId);

              final conv = _conversations
                  .cast<Map<String, dynamic>?>()
                  .firstWhere(
                    (c) => c?['conversation_id'] == conversationId,
                    orElse: () => null,
                  );

              final other = conv?['other_user'] as Map<String, dynamic>?;
              final name =
                  other?['display_name'] ?? other?['username'] ?? 'Някой';

              if (!mounted) return;

              setState(() => _unread.add(conversationId));

              _clearNotificationUi();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('$name реагира с $emoji'),
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
            } catch (e) {
              debugPrint('Reaction notify error: $e');
            }
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

    await ConversationPreviewStore.load();
    await _loadConversations();
    if (mounted) setState(() {});
  }

  Future<void> _openPublicProfile(
    Map<String, dynamic>? other,
    String name,
  ) async {
    final id = other?['id'] as String?;
    if (id == null) return;
    await PublicProfileSheet.show(
      context,
      userId: id,
      fallbackName: name,
      fallbackAvatar: other?['avatar_url'] as String?,
    );
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
    _reactionsChannel?.unsubscribe();
    _searchController.dispose();
    super.dispose();
  }

  Widget _buildAvatar(Map<String, dynamic>? other, String name) {
    final url = other?['avatar_url'] as String?;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return CircleAvatar(
      radius: 24,
      backgroundColor: CriptivoColors.surfaceLight,
      backgroundImage: url != null && url.isNotEmpty ? NetworkImage(url) : null,
      child: url == null || url.isEmpty
          ? Text(
              initial,
              style: const TextStyle(
                color: CriptivoColors.neon,
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            )
          : null,
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: TextField(
        controller: _searchController,
        style: const TextStyle(color: CriptivoColors.textPrimary),
        decoration: InputDecoration(
          hintText: 'Търси разговор…',
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: _searchQuery.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                ),
          isDense: true,
          filled: true,
          fillColor: CriptivoColors.surfaceLight,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
        onChanged: (v) => setState(() => _searchQuery = v),
      ),
    );
  }

  Widget _buildEmptyState({required bool isSearch}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSearch ? Icons.search_off_rounded : Icons.forum_outlined,
              size: 48,
              color: CriptivoColors.neon.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              isSearch ? 'Няма резултати' : 'Няма разговори още',
              style: const TextStyle(
                color: CriptivoColors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isSearch
                  ? 'Опитай с друго име или username'
                  : 'Започни чат с бутона долу',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: CriptivoColors.textSecondary.withValues(alpha: 0.9),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _subtitleFor(
    String conversationId,
    bool isUnread,
    Map<String, dynamic>? other,
  ) {
    final preview = ConversationPreviewStore.get(conversationId);
    if (preview != null && preview.preview.isNotEmpty) {
      return preview.preview;
    }
    if (isUnread) return 'Ново съобщение';
    final username = other?['username'] as String?;
    if (username != null && username.isNotEmpty) return '@$username';
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredConversations;

    return Scaffold(
      backgroundColor: CriptivoColors.background,
      appBar: AppBar(
        title: const Text('Criptivo'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline_rounded),
            tooltip: 'Профил',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfilePage()),
              );
              if (mounted) setState(() {});
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
          : Column(
              children: [
                if (_conversations.isNotEmpty) _buildSearchBar(),
                Expanded(
                  child: _conversations.isEmpty
                      ? _buildEmptyState(isSearch: false)
                      : filtered.isEmpty
                      ? _buildEmptyState(isSearch: true)
                      : RefreshIndicator(
                          color: CriptivoColors.neon,
                          onRefresh: () => _loadConversations(),
                          child: ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final item = filtered[index];
                              final conversationId =
                                  item['conversation_id'] as String? ?? '';
                              final other =
                                  item['other_user'] as Map<String, dynamic>?;
                              final name =
                                  other?['display_name'] ??
                                  other?['username'] ??
                                  'Unknown';
                              final isUnread = _unread.contains(conversationId);
                              final lastAt = _formatLastAt(
                                item['last_message_at'],
                              );
                              final subtitle = _subtitleFor(
                                conversationId,
                                isUnread,
                                other,
                              );

                              return ListTile(
                                leading: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    GestureDetector(
                                      onTap: () =>
                                          _openPublicProfile(other, name),
                                      child: _buildAvatar(other, name),
                                    ),
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
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                                ),
                                subtitle: Text(
                                  subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: isUnread
                                        ? CriptivoColors.neon
                                        : CriptivoColors.textSecondary,
                                    fontWeight: isUnread
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                    fontSize: 13,
                                  ),
                                ),
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    if (lastAt.isNotEmpty)
                                      Text(
                                        lastAt,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: isUnread
                                              ? CriptivoColors.neon
                                              : CriptivoColors.textSecondary,
                                          fontWeight: isUnread
                                              ? FontWeight.w600
                                              : FontWeight.normal,
                                        ),
                                      ),
                                    if (isUnread) ...[
                                      const SizedBox(height: 6),
                                      Container(
                                        width: 10,
                                        height: 10,
                                        decoration: const BoxDecoration(
                                          color: CriptivoColors.neon,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                onTap: () => _openChat(item),
                              );
                            },
                          ),
                        ),
                ),
              ],
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
