part of 'chat_page.dart';

extension _ChatPageWidgets on _ChatPageState {
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: CriptivoColors.surfaceLight,
              border: Border.all(
                color: CriptivoColors.neon.withValues(alpha: 0.3),
              ),
            ),
            child: const Icon(
              Icons.lock_outline_rounded,
              size: 36,
              color: CriptivoColors.neon,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Защитен разговор',
            style: TextStyle(
              color: CriptivoColors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Съобщенията са end-to-end криптирани.\nНапиши първото.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: CriptivoColors.textSecondary.withValues(alpha: 0.85),
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> msg) {
    final isMe = msg['is_me'] == true;
    final time = _formatTime(msg['created_at']);
    final text = msg['text'] ?? '';
    final isRead = msg['read_at'] != null;
    final media = msg['media'] as Map<String, dynamic>?;
    final reactions =
        (msg['reactions'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final messageId = msg['id'] as String? ?? '';
    final expireLabel = _expireLabel(msg['expires_at']);
    final replyPreview = msg['reply_preview'] as String?;
    final hasLink =
        media == null &&
        text is String &&
        LinkPreviewService.firstUrl(text) != null;

    return Padding(
      padding: EdgeInsets.only(
        top: 4,
        bottom: 4,
        left: isMe ? 48 : 8,
        right: isMe ? 8 : 48,
      ),
      child: Column(
        crossAxisAlignment: isMe
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onLongPress: () => _onBubbleLongPress(msg),
            onDoubleTap: () async {
              if (messageId.isEmpty || messageId.startsWith('temp_')) return;
              final emoji = await showReactionPicker(context);
              if (emoji != null) await _toggleReaction(messageId, emoji);
            },
            child: Container(
              padding: media != null
                  ? const EdgeInsets.all(6)
                  : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                gradient: isMe
                    ? LinearGradient(
                        colors: [
                          CriptivoColors.bubbleMe,
                          CriptivoColors.bubbleMe.withValues(alpha: 0.85),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                color: isMe ? null : CriptivoColors.bubbleOther,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isMe ? 18 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 18),
                ),
                border: Border.all(
                  color: isMe
                      ? CriptivoColors.neon.withValues(alpha: 0.25)
                      : Colors.white.withValues(alpha: 0.06),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (replyPreview != null && replyPreview.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: const Border(
                          left: BorderSide(
                            color: CriptivoColors.neon,
                            width: 2,
                          ),
                        ),
                      ),
                      child: Text(
                        replyPreview,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: CriptivoColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  if (media != null)
                    ViewOnce.isViewOnce(media)
                        ? ViewOnceTile(media: media, messageId: messageId)
                        : MediaMessageContent(media: media)
                  else ...[
                    Text(
                      text,
                      style: const TextStyle(
                        color: CriptivoColors.textPrimary,
                        fontSize: 15,
                        height: 1.35,
                      ),
                    ),
                    if (hasLink) LinkPreviewCard(text: text),
                  ],
                ],
              ),
            ),
          ),
          ReactionBar(
            aggregated: reactions,
            onToggle: (emoji) => _toggleReaction(messageId, emoji),
          ),
          const SizedBox(height: 3),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (time.isNotEmpty)
                  Text(
                    time,
                    style: TextStyle(
                      color: CriptivoColors.textSecondary.withValues(
                        alpha: 0.7,
                      ),
                      fontSize: 11,
                    ),
                  ),
                if (expireLabel != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    expireLabel,
                    style: TextStyle(
                      color: CriptivoColors.neon.withValues(alpha: 0.85),
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                if (isMe) ...[
                  const SizedBox(width: 4),
                  Icon(
                    isRead ? Icons.done_all_rounded : Icons.done_rounded,
                    size: 14,
                    color: isRead
                        ? CriptivoColors.neon
                        : CriptivoColors.textSecondary.withValues(alpha: 0.7),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
