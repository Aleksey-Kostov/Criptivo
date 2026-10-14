import 'package:flutter/material.dart';

import '../../core/chat/chat_service.dart';
import 'chat_page.dart';

class NewChatPage extends StatefulWidget {
  const NewChatPage({super.key});

  @override
  State<NewChatPage> createState() => _NewChatPageState();
}

class _NewChatPageState extends State<NewChatPage> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  bool _loading = false;

  Future<void> _search(String query) async {
    if (query.trim().length < 2) {
      setState(() => _results = []);
      return;
    }

    setState(() => _loading = true);
    try {
      final users = await ChatService.searchUsers(query);
      setState(() {
        _results = users;
        _loading = false;
      });
    } catch (e) {
      print('Search error: $e');
      setState(() => _loading = false);
    }
  }

  Future<void> _startChat(Map<String, dynamic> user) async {
    try {
      final conversationId = await ChatService.getOrCreateConversation(
        user['id'],
      );

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) =>
              ChatPage(conversationId: conversationId, otherUser: user),
        ),
      );
    } catch (e) {
      print('Start chat error: $e');
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Грешка: $e')));
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Нов чат')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'Търси по username',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: _search,
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          Expanded(
            child: ListView.builder(
              itemCount: _results.length,
              itemBuilder: (context, index) {
                final user = _results[index];
                final name =
                    user['display_name'] ?? user['username'] ?? 'Unknown';
                final hasKey = user['public_key'] != null;

                return ListTile(
                  leading: CircleAvatar(child: Text(name[0].toUpperCase())),
                  title: Text(name),
                  subtitle: Text(
                    hasKey
                        ? '@${user['username']}'
                        : '@${user['username']} (няма ключ)',
                  ),
                  trailing: hasKey
                      ? const Icon(Icons.lock, size: 18)
                      : const Icon(
                          Icons.lock_open,
                          size: 18,
                          color: Colors.orange,
                        ),
                  onTap: hasKey ? () => _startChat(user) : null,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
