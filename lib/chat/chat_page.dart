import 'package:flutter/material.dart';

class ChatPage extends StatelessWidget {
  final String conversationId;
  final Map<String, dynamic> otherUser;

  const ChatPage({
    super.key,
    required this.conversationId,
    required this.otherUser,
  });

  @override
  Widget build(BuildContext context) {
    final name =
        otherUser['display_name'] ?? otherUser['username'] ?? 'Chat';

    return Scaffold(
      appBar: AppBar(
        title: Text(name),
      ),
      body: Center(
        child: Text(
          'Чат с $name\n\nConversation ID:\n$conversationId\n\nСледва: криптирани съобщения',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
