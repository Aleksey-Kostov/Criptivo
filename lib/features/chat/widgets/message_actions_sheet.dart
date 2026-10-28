import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/storage/media_local_cache.dart';
import '../../../core/theme/criptivo_theme.dart';

enum MessageAction {
  reply,
  copy,
  share,
  download,
  viewOnceInfo,
}

/// Bottom sheet: Reply · Copy · Share · Download (ако има media).
class MessageActionsSheet extends StatelessWidget {
  final String plaintextDisplay;
  final Map<String, dynamic>? media;
  final bool isMe;
  final void Function(MessageAction action) onAction;

  const MessageActionsSheet({
    super.key,
    required this.plaintextDisplay,
    required this.onAction,
    this.media,
    this.isMe = false,
  });

  static Future<void> show(
    BuildContext context, {
    required String plaintextDisplay,
    Map<String, dynamic>? media,
    bool isMe = false,
    required void Function(MessageAction action) onAction,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: CriptivoColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => MessageActionsSheet(
        plaintextDisplay: plaintextDisplay,
        media: media,
        isMe: isMe,
        onAction: (a) {
          Navigator.pop(context);
          onAction(a);
        },
      ),
    );
  }

  bool get _hasMedia => media != null && media!['url'] != null;

  bool get _isPlainText {
    if (_hasMedia) return false;
    final t = plaintextDisplay.trim();
    return t.isNotEmpty &&
        !t.startsWith('[') &&
        t != '🖼️' &&
        t != '🎬' &&
        t != '📎' &&
        t != '🎵';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            _tile(
              icon: Icons.reply_rounded,
              label: 'Отговор',
              onTap: () => onAction(MessageAction.reply),
            ),
            if (_isPlainText)
              _tile(
                icon: Icons.copy_rounded,
                label: 'Копирай',
                onTap: () => onAction(MessageAction.copy),
              ),
            if (_isPlainText || _hasMedia)
              _tile(
                icon: Icons.ios_share_rounded,
                label: 'Сподели',
                onTap: () => onAction(MessageAction.share),
              ),
            if (_hasMedia)
              _tile(
                icon: Icons.download_rounded,
                label: 'Изтегли',
                onTap: () => onAction(MessageAction.download),
              ),
          ],
        ),
      ),
    );
  }

  Widget _tile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: CriptivoColors.neon),
      title: Text(label, style: const TextStyle(color: CriptivoColors.textPrimary)),
      onTap: onTap,
    );
  }
}

/// Помощни операции — викай от chat_page handler.
class MessageActionHandlers {
  static Future<void> copyText(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
  }

  static Future<void> shareText(String text) async {
    await Share.share(text);
  }

  static Future<void> shareOrDownloadMedia(
    Map<String, dynamic> media, {
    required bool share,
  }) async {
    final file = await MediaLocalCache.getDecryptedFile(
      url: media['url'] as String,
      keyBase64: media['key'] as String,
      nonceBase64: media['nonce'] as String,
      preferredName: media['name'] as String? ?? 'file',
    );
    if (share) {
      await Share.shareXFiles([XFile(file.path)]);
    }
    // download = вече е в temp; open_filex може от MediaMessageContent
  }
}